#define CHECK_CONNECTED(%1) \
  if (!IsConnected(%1))     \
  ThrowNativeError(SP_ERROR_PARAM, "Client %d is not connected", %1)
#define CHECK_ARENA(%1)             \
  if (%1 <= 0 || %1 > g_maxArenas) \
  ThrowNativeError(SP_ERROR_PARAM, "Arena %d is not valid", %1)
#define CHECK_ROUNDTYPE(%1)             \
  if (%1 < 0 || %1 >= g_numRoundTypes) \
  ThrowNativeError(SP_ERROR_PARAM, "Roundtype %d is not valid", %1)

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
  CreateNative("Mm1v1_IsInWaitingQueue", Native_IsInWaitingQueue);
  CreateNative("Mm1v1_Message", Native_Mm1v1Message);
}

public int Native_IsInWaitingQueue(Handle plugin, int numParams) {
  int client = GetNativeCell(1);
  CHECK_CONNECTED(client);

  PrintToServer(">>>>> IsInWaitingQueue (%N, %i)", client, Queue_Length(g_waitingQueue));

  return Queue_Inside(g_waitingQueue, client);
}

public int Native_Mm1v1Message(Handle plugin, int numParams) {
  int client = GetNativeCell(1);
  CHECK_CONNECTED(client);

  char buffer[1024];
  int bytesWritten = 0;

  SetGlobalTransTarget(client);
  FormatNativeString(0, 2, 3, sizeof(buffer), bytesWritten, buffer);
  char finalMsg[1024];

  Format(finalMsg, sizeof(finalMsg), "%s%s", MESSAGE_PREFIX, buffer);

  Colourise(finalMsg, sizeof(finalMsg));
  PrintToChat(client, finalMsg);
}