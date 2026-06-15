/**
 * FKZ API - Cross-server chat
 *
 * Relays public chat between all FKZ servers through the API.
 *
 *   Send:    OnClientSayCommand captures public "say" lines and POSTs them to
 *            /chat/messages. say_team is left local (never relayed).
 *   Receive: a single long-poll GET /chat/stream is kept open against the API.
 *            It returns the instant any server posts a message, we print it,
 *            then immediately re-open the poll. Near-instant, no busy polling.
 *
 * Players can hide the relay for themselves with !crosschat.
 */

#define CHAT_STREAM_TIMEOUT 30000    // ms; must exceed the API's ~25s park time
#define CHAT_RETRY_DELAY    3.0      // s; backoff after a transport/HTTP error

void SetupCrossChat()
{
    RegConsoleCmd("sm_crosschat", Cmd_CrossChat, "Toggle cross-server chat messages");

    // Only open the stream if someone's here.
    // An empty/hibernating server holds no connection.
    if (HasHumanPlayers())
        StartChatStream();
}

// True if at least one non-bot player is in game.
// Gates the long-poll so an empty server neither holds a connection nor re-handshakes.
bool HasHumanPlayers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            return true;
    }
    return false;
}

// Resolve this server's public endpoint the same way the status report does.
void GetChatEndpoint(char[] ip, int iplen, int& port)
{
    if (g_serverIp[0] != '\0')
    {
        strcopy(ip, iplen, g_serverIp);
    }
    else
    {
        int hostip = FindConVar("hostip").IntValue;
        FormatEx(ip, iplen, "%d.%d.%d.%d",
                 (hostip >> 24) & 0xFF, (hostip >> 16) & 0xFF,
                 (hostip >> 8) & 0xFF, hostip & 0xFF);
    }
    port = g_serverPort > 0 ? g_serverPort : FindConVar("hostport").IntValue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (g_apiUrl[0] == '\0' || client < 1 || IsFakeClient(client))
        return Plugin_Continue;

    // Relay public chat only, keep team chat local.
    if (!StrEqual(command, "say", false))
        return Plugin_Continue;

    int p = 0;
    while (sArgs[p] == ' ')
        p++;

    // Skip empty lines and command triggers (!cmd / /cmd).
    if (sArgs[p] == '\0' || sArgs[p] == '!' || sArgs[p] == '/')
        return Plugin_Continue;

    SendChatMessage(client, sArgs);
    return Plugin_Continue;
}

void SendChatMessage(int client, const char[] message)
{
    char ip[64];
    int  port;
    GetChatEndpoint(ip, sizeof(ip), port);

    char steamid[32];
    if (IsClientAuthorized(client))
        GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    else
        steamid[0] = '\0';

    char name[128];
    GetClientName(client, name, sizeof(name));

    JSONObject body = new JSONObject();
    body.SetString("ip", ip);
    body.SetInt("port", port);
    if (steamid[0] != '\0')
        body.SetString("steamid", steamid);
    body.SetString("name", name);
    body.SetString("message", message);

    FKZ_SendRequest("POST", "/chat/messages", view_as<JSON>(body), OnChatPostResponse, 0);
    delete body;
}

void OnChatPostResponse(HttpRequest http, const char[] body, int statusCode, int bodySize, any value)
{
    if (statusCode != 200)
        LogError("[FKZ] chat POST returned HTTP %d: %.256s", statusCode, body);
}

void StartChatStream()
{
    if (g_apiUrl[0] == '\0' || g_chatStreamActive)
        return;

    char ip[64];
    int  port;
    GetChatEndpoint(ip, sizeof(ip), port);

    char url[1024];
    FormatEx(url, sizeof(url), "%s/chat/stream?after=%d&ip=%s&port=%d",
             g_apiUrl, g_chatCursor, ip, port);

    HttpRequest req    = new HttpRequest(url);
    req.Timeout        = CHAT_STREAM_TIMEOUT;
    req.FollowRedirect = false;

    if (g_tlsCAFile[0] != '\0')
        req.SetTLSCAFile(g_tlsCAFile);
    if (g_apiKey[0] != '\0')
        req.SetBearerAuth(g_apiKey);

    if (req.Get(OnChatStream))
    {
        g_chatStreamActive = true;
    }
    else
    {
        delete req;
        ScheduleChatRetry();
    }
}

void OnChatStream(HttpRequest http, const char[] body, int statusCode, int bodySize, any value)
{
    g_chatStreamActive = false;

    if (statusCode != 200)
    {
        // 0 = transport error (timeout is expected only past the park window).
        ScheduleChatRetry();
        return;
    }

    if (body[0] != '\0')
    {
        JSON doc = view_as<JSON>(JSON.Parse(body));
        if (doc != null)
        {
            // Trust the server's cursor (only one poll is in flight at a time, so replies arrive in order).
            // Adopting it unconditionally lets us recover if the API restarted and reset its cursor below ours.
            g_chatCursor = doc.PtrGetInt("/cursor");

            int count    = doc.PtrGetLength("/messages");
            for (int i = 0; i < count; i++)
            {
                char path[64];
                char alias[64], name[128], message[512];

                FormatEx(path, sizeof(path), "/messages/%d/alias", i);
                doc.PtrGetString(path, alias, sizeof(alias));
                FormatEx(path, sizeof(path), "/messages/%d/name", i);
                doc.PtrGetString(path, name, sizeof(name));
                FormatEx(path, sizeof(path), "/messages/%d/message", i);
                doc.PtrGetString(path, message, sizeof(message));

                PrintCrossChat(alias, name, message);
            }
            delete doc;
        }
    }

    // Re-open the poll for the next message, but only while players are here.
    // When the last player leaves, this in-flight poll is the last one.
    if (HasHumanPlayers())
        StartChatStream();
}

void PrintCrossChat(const char[] alias, const char[] name, const char[] message)
{
    char line[768];
    FormatEx(line, sizeof(line), " \x0E[%s]\x01 %s\x01: %s", alias, name, message);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && !g_crossChatMuted[i])
            PrintToChat(i, "%s", line);
    }
}

void ScheduleChatRetry()
{
    if (g_chatRetryTimer != INVALID_HANDLE)
        return;
    g_chatRetryTimer = CreateTimer(CHAT_RETRY_DELAY, Timer_ChatRetry);
}

public Action Timer_ChatRetry(Handle timer, any data)
{
    g_chatRetryTimer = INVALID_HANDLE;
    if (HasHumanPlayers())
        StartChatStream();
    return Plugin_Stop;
}

public Action Cmd_CrossChat(int client, int args)
{
    if (client < 1)
        return Plugin_Handled;

    g_crossChatMuted[client] = !g_crossChatMuted[client];
    if (g_crossChatMuted[client])
        PrintToChat(client, " \x0EFKZ\x08|\x01 Cross-server messages \x02hidden\x01. Type !crosschat to show.");
    else
        PrintToChat(client, " \x0EFKZ\x08|\x01 Cross-server messages \x04shown\x01.");

    return Plugin_Handled;
}
