#include <clientprefs>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <smlib>
#include <sourcemod>

#include "include/queue"
#include "include/logdebug"
#include "include/mm1v1"

#define PLUGIN_VERSION "v1.0"
#define DEBUG_CVAR "sm_mm1v1_debug"

#pragma semicolon 1
#pragma newdecls required

/** ConVars **/
ConVar g_EnabledCvar;
bool g_Enabled = true;

ConVar g_VerboseCvar;
ConVar g_VersionCvar;

/** Overall global variables **/
int g_maxArenas = 0;    // maximum number of arenas the map can support
Handle g_waitingQueue = INVALID_HANDLE;

/** Handles to arrays of vectors of spawns/angles **/
ArrayList g_TSpawnsList;
ArrayList g_TAnglesList;
ArrayList g_CTSpawnsList;
ArrayList g_CTAnglesList;

/** Client arrays **/
bool g_PluginTeamSwitch[MAXPLAYERS + 1]; // Flags the teamswitches as being done by the plugin
int g_Arena[MAXPLAYERS + 1]; 
int g_LastClientDeathTime[MAXPLAYERS + 1];
int g_ArenaStatsUpdated[MAXPLAYERS + 1];

/** Arena arrays **/
int g_ArenaPlayer1[MAXPLAYERS + 1] = -1; // who is player 1 in each arena
int g_ArenaPlayer2[MAXPLAYERS + 1] = -1; // who is player 2 in each arena

#include "mm1v1/generic.sp"
#include "mm1v1/spawns.sp"
#include "mm1v1/ranks.sp"
#include "mm1v1/natives.sp"

public Plugin myinfo = {
	name = "1 vs 1",
	author = "Codefined",
	description = "A 1 vs 1 server plugin with matchmaking",
	version = PLUGIN_VERSION,
	url = "https://femto.pw"
};

public void OnPluginStart() {
  LoadTranslations("common.phrases");
  LoadTranslations("mm1v1.phrases");

  /** ConVars **/
  g_EnabledCvar = CreateConVar(
    "sm_mm1v1_enabled", "1",
    "Whether the mm1v1 gamemode is enabled or not");

  g_VerboseCvar = CreateConVar(
    "sm_mm1v1_verbose", "0",
    "Enables verbose logging.");

  g_VersionCvar = CreateConVar("sm_mm1v1_version", PLUGIN_VERSION, "Current mm1v1 version",
    FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
  SetConVarString(g_VersionCvar, PLUGIN_VERSION);

  HookConVarChange(g_EnabledCvar, EnabledChanged);

  g_waitingQueue = Queue_Init();

  /** Hooks **/
  HookEvent("player_team", Event_OnPlayerTeam, EventHookMode_Pre);
  HookEvent("player_connect_full", Event_OnFullConnect);
  HookEvent("player_spawn", Event_OnPlayerSpawn);
  HookEvent("player_death", Event_OnPlayerDeath);
  HookEvent("round_prestart", Event_OnRoundPreStart);
  // HookEvent("round_poststart", Event_OnRoundPostStart);
  // HookEvent("round_end", Event_OnRoundEnd);
  // HookEvent("cs_win_panel_match", Event_MatchOver);

  /** Commands **/
  AddCommandListener(Command_JoinTeam, "jointeam");

  PrintToChatAll("[+] Loaded mm1v1");
}

public void OnMapStart() {
  Spawns_MapStart();
  Queue_Clear(g_waitingQueue);

  for (int i = 0; i <= MAXPLAYERS; i++) {
    g_ArenaPlayer1[i] = -1;
    g_ArenaPlayer2[i] = -1;
  }

  // if (db == null && AreStatsEnabled()) {
  //   DB_Connect();
  // }
}

public int EnabledChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
  bool wasEnabled = !StrEqual(oldValue, "0");
  g_Enabled = !StrEqual(newValue, "0");

  if (wasEnabled && !g_Enabled) {
    // plugin disabled
  } else if (!wasEnabled && g_Enabled) {
    // plugin enabled
    Queue_Clear(g_waitingQueue);

    for (int i = 1; i <= MaxClients; i++) {
      if (IsClientConnected(i) && !IsFakeClient(i)) {
        OnClientConnected(i);
        if (IsActivePlayer(i)) {
          SwitchPlayerTeam(i, CS_TEAM_SPECTATOR);
          Queue_Enqueue(g_waitingQueue, i);
        }
      }
    }
  }
}

/**
 * Full connect event right when a player joins.
 * This sets the auto-pick time to a high value because mp_forcepicktime is broken and
 * if a player does not select a team but leaves their mouse over one, they are
 * put on that team and spawned, so we can't allow that.
 */
public Action Event_OnFullConnect(Event event, const char[] name, bool dontBroadcast) {
  if (!g_Enabled)
    return;

  int client = GetClientOfUserId(event.GetInt("userid"));
  if (IsPlayer(client)) {
    SetEntPropFloat(client, Prop_Send, "m_fForceTeam", 3600.0);
  }
}

/**
 * Silences team join/switch events.
 */
public Action Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast) {
  if (!g_Enabled)
    return Plugin_Continue;

  SetEventBroadcast(event, true);
  return Plugin_Continue;
}

public void OnClientConnected(int client) {
  ResetClientVariables(client);
}

/**
 * Player spawn event - gives the appropriate weapons to a player for his arena.
 * Warning: do NOT assume this is called before or after the round start event!
 */
public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
  if (!g_Enabled)
    return;

  int client = GetClientOfUserId(event.GetInt("userid"));
  if (!IsActivePlayer(client))
    return;

  int arena = g_Arena[client];

  // Error handling if a player somehow joined a team without ever going through the queue.
  if (arena < 1) {
    Queue_Enqueue(g_waitingQueue, client);
    SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
    return;
  }

  CreateTimer(0.1, RemoveRadar, client);

  return;
}

/**
 * Player death event, updates g_arenaWinners/g_arenaLosers for the arena that was just decided.
 */
public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
  if (!g_Enabled)
    return;

  int victim = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int arena = g_Arena[victim];

  PrintToServer("Noticed player death, %i killed %i", attacker, victim);

  if (victim != -1) {
    g_LastClientDeathTime[victim] = GetTime();
  }

  // If we've already decided the arena, don't worry about anything else in it
  if (g_ArenaStatsUpdated[arena])
    return;

  g_ArenaStatsUpdated[arena] = true;
  
  int p1 = g_ArenaPlayer1[arena];
  int p2 = g_ArenaPlayer2[arena];

  // we assume the winner is the person who didn't die.
  int dead = victim == p1 ? p1 : p2;
  int killer = dead == p1 ? p2 : p1;

  UpdateRanking(killer, dead);
}

public Action Event_OnRoundPreStart(Event event, const char[] name, bool dontBroadcast) {
  if (!g_Enabled)
    return;

  // Here we add each player to the queue in their new ranking
  Handle rankingQueue = Queue_Init();

  LoopValidClients(i) {
    PrintToServer("Considering %N", i);
    AddPlayer_NoSpec(i, rankingQueue);
  }

  PrintToServer("starting queue with %i players (from %i)", Queue_Length(rankingQueue), Queue_Length(g_waitingQueue));
}


/*************************
 *                       *
 * Generic 1v1-Functions *
 *                       *
 *************************/

/**
 * Switches a client to a new team.
 */
public void SwitchPlayerTeam(int client, int team) {
  int previousTeam = GetClientTeam(client);
  if (previousTeam == team)
    return;

  g_PluginTeamSwitch[client] = true;
  if (team > CS_TEAM_SPECTATOR) {
    CS_SwitchTeam(client, team);
    CS_UpdateClientModel(client);
  } else {
    ChangeClientTeam(client, team);
  }
  g_PluginTeamSwitch[client] = false;
}

/**
 * Resets all client variables to their default.
 */
public void ResetClientVariables(int client) {
  g_PluginTeamSwitch[client] = false;
  g_Arena[client] = 0;
}

/**
 * Wrapper on the geneic AddPlayer function that doesn't allow spectators not in
 * the waiting queue to join. This is meant to deal with players being moved to spectator
 * by another plugin (e.g. afk managers).
 */
public void AddPlayer_NoSpec(int client, Handle rankingQueue) {
  if (!IsValidClient(client)) {
    PrintToServer("%N is not a valid client", client);
    return;
  }

  if (GetClientTeam(client) != CS_TEAM_SPECTATOR || Mm1v1_IsInWaitingQueue(client)) {
    PrintToServer("Client %N has passed spectator checks", client);
    AddPlayer(client, rankingQueue);
    return;
  }

  PrintToServer("Client team %b, Client in queue %b", GetClientTeam(client) != CS_TEAM_SPECTATOR, Mm1v1_IsInWaitingQueue(client));
}

/**
 * Function to add a player to the ranking queue with some validity checks.
 */
public void AddPlayer(int client, Handle rankingQueue) {
  if (!IsPlayer(client)) {
    PrintToServer("Client %N is not a player", client);
    return;
  }

  bool space = Queue_Length(rankingQueue) < 2 * g_maxArenas;
  bool alreadyIn = Queue_Inside(rankingQueue, client);

  PrintToServer("Max Arenas: %i, Space in queue: %b, AlreadyIn: %b", g_maxArenas, space, alreadyIn);

  if (space && !alreadyIn) {
    Queue_Enqueue(rankingQueue, client);
  }
}

/**
 * Updates an arena in case a player disconnects or leaves.
 * Checks if we should assign a winner/loser and informs the player they no longer have an opponent.
 */
public void UpdateArena(int arena, int disconnected) {
  if (arena != -1) {
    int p1 = g_ArenaPlayer1[arena];
    int p2 = g_ArenaPlayer2[arena];
    bool hasp1 = IsActivePlayer(p1) && p1 != disconnected;
    bool hasp2 = IsActivePlayer(p2) && p2 != disconnected;

    if (hasp1 && !hasp2) {
      PlayerLeft(arena, p1, p2);
    } else if (hasp2 && !hasp1) {
      PlayerLeft(arena, p2, p1);
    }
  }
}

static void PlayerLeft(int arena, int player, int left) {
  if (!g_ArenaStatsUpdated[arena]) {
    Mm1v1_Message(player, "%t", "OpponentLeft");
    PrintHintText(player, "%t", "OpponentLeftHint");
    UpdateRanking(player, left);
  }

  g_ArenaStatsUpdated[arena] = true;
}

/***********************
 *                     *
 *    Command Hooks    *
 *                     *
 ***********************/

/**
 * teamjoin hook - marks a player as waiting or moves them to spec if appropriate.
 */
public Action Command_JoinTeam(int client, const char[] command, int argc) {
  if (!g_Enabled) {
    return Plugin_Continue;
  }

  if (!IsValidClient(client)) {
    return Plugin_Handled;
  }

  char arg[4];
  GetCmdArg(1, arg, sizeof(arg));
  int team_to = StringToInt(arg);
  int team_from = GetClientTeam(client);

  PrintToServer("%N joining team %i from %i", client, team_to, team_from);

  if (IsFakeClient(client) || g_PluginTeamSwitch[client]) {
    PrintToServer("Fake client, or team swapped by plugin (%N)", client);
    return Plugin_Continue;
  } else if ((team_from == CS_TEAM_CT && team_to == CS_TEAM_T) ||
             (team_from == CS_TEAM_T && team_to == CS_TEAM_CT)) {
    PrintToServer("Client swapping between T -> CT or CT -> T (%N)", client);
    // ignore changes between T/CT
    return Plugin_Handled;
  } else if (team_to == CS_TEAM_SPECTATOR) {
    // player voluntarily joining spec
    PrintToServer("Player voluntarily joining spectator (%N)", client);
    SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
    int arena = g_Arena[client];
    UpdateArena(arena, client);
    CS_SetClientClanTag(client, "");
  } else {
    // Player first joining the game, mark them as waiting to join
    PrintToServer("Adding player to waiting queue (%N)", client);
    Queue_Enqueue(g_waitingQueue, client);
    PrintToServer("Waiting Queue length: %i", Queue_Length(g_waitingQueue));
    SwitchPlayerTeam(client, CS_TEAM_SPECTATOR);
  }

  return Plugin_Handled;
}