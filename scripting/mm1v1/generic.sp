#define MESSAGE_PREFIX "[\x05Multi1v1\x01] "
#define HIDE_RADAR_BIT 1 << 12
#define LoopValidClients(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsValidClient(%1))


char g_ColorNames[][] = {"{NORMAL}",     "{DARK_RED}",    "{PURPLE}",    "{GREEN}",
                         "{MOSS_GREEN}", "{LIGHT_GREEN}", "{LIGHT_RED}", "{GRAY}",
                         "{ORANGE}",     "{LIGHT_BLUE}",  "{DARK_BLUE}", "{PURPLE}"};
char g_ColorCodes[][] = {"\x01", "\x02", "\x03", "\x04", "\x05", "\x06",
                         "\x07", "\x08", "\x09", "\x0B", "\x0C", "\x0E"};

/**
 * Removes the radar element from a client's HUD.
 */
public Action RemoveRadar(Handle timer, int client) {
  PrintToServer("Removing radar for %N", client);

  if (IsValidClient(client) && !IsFakeClient(client)) {
    int flags = GetEntProp(client, Prop_Send, "m_iHideHUD");
    SetEntProp(client, Prop_Send, "m_iHideHUD", flags | (HIDE_RADAR_BIT));
  }
  return Plugin_Continue;
}

/**
 * Given an array of vectors, returns the index of the index
 * that minimizes the euclidean distance between the vectors.
 */
stock int NearestNeighborIndex(const float vec[3], ArrayList others) {
  int closestIndex = -1;
  float closestDistance = 0.0;
  for (int i = 0; i < others.Length; i++) {
    float tmp[3];
    others.GetArray(i, tmp);
    float dist = GetVectorDistance(vec, tmp);
    if (closestIndex < 0 || dist < closestDistance) {
      closestDistance = dist;
      closestIndex = i;
    }
  }

  return closestIndex;
}

/**
 * Applies colourised characters across a string to replace color tags.
 */
stock void Colourise(char[] msg, int size) {
  for (int i = 0; i < sizeof(g_ColorNames); i++) {
    ReplaceString(msg, size, g_ColorNames[i], g_ColorCodes[i]);
  }
}

/**
 * Function to identify if a client is valid and in game.
 */
stock bool IsValidClient(int client) {
  return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

stock bool IsConnected(int client) {
  return client > 0 && client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client);
}

/**
 * Returns if a player is on an active/player team.
 */
stock bool IsPlayer(int client) {
  return IsValidClient(client) && !IsFakeClient(client);
}

/**
 * Returns if a player is on an active/player team.
 */
stock bool IsActivePlayer(int client) {
  if (!IsPlayer(client))
    return false;
  int client_team = GetClientTeam(client);
  return (client_team == CS_TEAM_CT) || (client_team == CS_TEAM_T);
}

/**
 * Closes all handles within an arraylist of arraylists.
 */
stock void CloseNestedList(ArrayList list) {
  int n = list.Length;
  for (int i = 0; i < n; i++) {
    ArrayList tmp = view_as<ArrayList>(list.Get(i));
    delete tmp;
  }
  delete list;
}

public float fmin(float x, float y) {
  return (x < y) ? x : y;
}

public float fmax(float x, float y) {
  return (x < y) ? y : x;
}