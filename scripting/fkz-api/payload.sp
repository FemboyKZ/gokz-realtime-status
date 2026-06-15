/**
 * FKZ API - Payload building
 *
 * Caches static server info and assembles the JSON report
 * (server object + players array + plugins array).
 */

void CacheStaticServerInfo()
{
    DetectOS();

    ConVar cvHostname = FindConVar("hostname");
    if (cvHostname != null)
        cvHostname.GetString(g_cachedHostname, sizeof(g_cachedHostname));
    else
        strcopy(g_cachedHostname, sizeof(g_cachedHostname), "unknown");

    // Game version ("version" is a command, not a ConVar)
    // Output format:
    //   Protocol version 13881 [1575/1575]
    //   Exe version 1.38.8.1 (csgo)
    //   Exe build: ...
    char versionBuf[512];
    ServerCommandEx(versionBuf, sizeof(versionBuf), "version");

    int pos = StrContains(versionBuf, "Exe version ");
    if (pos != -1)
    {
        pos += 12;    // skip "Exe version "
        int out = 0;
        while (versionBuf[pos] != '\0' && versionBuf[pos] != ' ' && versionBuf[pos] != '\n' && versionBuf[pos] != '\r' && out < sizeof(g_cachedVersion) - 1)
        {
            g_cachedVersion[out++] = versionBuf[pos++];
        }
        g_cachedVersion[out] = '\0';
    }
    else
    {
        // Fallback: use first line
        strcopy(g_cachedVersion, sizeof(g_cachedVersion), versionBuf);
        int nl = FindCharInString(g_cachedVersion, '\n');
        if (nl != -1)
            g_cachedVersion[nl] = '\0';
        TrimString(g_cachedVersion);
    }

    g_cachedTickrate        = RoundToNearest(1.0 / GetTickInterval());

    // Note: on first map load after server start, Steam may not be connected yet.
    g_cachedSecureAvailable = (GetFeatureStatus(FeatureType_Native, "SteamWorks_IsVACEnabled") == FeatureStatus_Available);
    if (g_cachedSecureAvailable)
        g_cachedSecure = SteamWorks_IsVACEnabled();

    ConVar cvMM = FindConVar("metamod_version");
    if (cvMM != null)
        cvMM.GetString(g_cachedMMVersion, sizeof(g_cachedMMVersion));
    else
        g_cachedMMVersion[0] = '\0';

    if (g_cachedPlugins != null)
        delete g_cachedPlugins;
    g_cachedPlugins = BuildPluginsArray();

    LogMessage("[FKZ] Cached static info: hostname=%s, version=%s, tickrate=%d", g_cachedHostname, g_cachedVersion, g_cachedTickrate);
}

JSONObject BuildPayload()
{
    JSONObject payload = new JSONObject();

    JSONObject server  = BuildServerObject();
    payload.Set("server", server);
    delete server;

    JSONArray players = BuildPlayersArray();
    payload.Set("players", players);
    delete players;

    return payload;
}

JSONObject BuildServerObject()
{
    JSONObject server = new JSONObject();

    server.SetString("hostname", g_cachedHostname);
    server.SetString("os", g_osName);
    server.SetString("version", g_cachedVersion);
    server.SetInt("tickrate", g_cachedTickrate);

    if (g_cachedSecureAvailable)
        server.SetBool("secure", g_cachedSecure);
    else
        server.SetNull("secure");

    if (g_cachedMMVersion[0] != '\0')
        server.SetString("mm_version", g_cachedMMVersion);

    server.SetString("sm_version", SOURCEMOD_VERSION);
    server.SetBool("gokz_loaded", true);

    if (g_cachedPlugins != null)
    {
        server.Set("plugins", g_cachedPlugins);
    }

    char ip[64];
    if (g_serverIp[0] != '\0')
    {
        strcopy(ip, sizeof(ip), g_serverIp);
    }
    else
    {
        int hostip = FindConVar("hostip").IntValue;
        FormatEx(ip, sizeof(ip), "%d.%d.%d.%d",
                 (hostip >> 24) & 0xFF,
                 (hostip >> 16) & 0xFF,
                 (hostip >> 8) & 0xFF,
                 hostip & 0xFF);
    }
    server.SetString("ip", ip);

    int port = g_serverPort > 0 ? g_serverPort : FindConVar("hostport").IntValue;
    server.SetInt("port", port);

    char map[256];
    GetCurrentMap(map, sizeof(map));
    server.SetString("map", map);

    int playerCount = 0;
    int botCount    = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i))
            continue;
        if (IsFakeClient(i))
        {
            botCount++;
            continue;
        }
        playerCount++;
    }
    server.SetInt("players", playerCount);
    server.SetInt("max_players", MaxClients);
    server.SetInt("bot_count", botCount);

    return server;
}

JSONArray BuildPlayersArray()
{
    JSONArray players = new JSONArray();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i) || IsFakeClient(i))
            continue;

        JSONObject player = new JSONObject();

        char       steamid[32];
        if (IsClientAuthorized(i))
            GetClientAuthId(i, AuthId_SteamID64, steamid, sizeof(steamid));
        else
            steamid[0] = '\0';
        player.SetString("steamid", steamid);

        char name[128];
        GetClientName(i, name, sizeof(name));
        player.SetString("name", name);

        char clientIp[64];
        GetClientIP(i, clientIp, sizeof(clientIp));
        player.SetString("ip", clientIp);

        float timeOnServer = 0.0;
        if (g_connectTime[i] > 0.0)
            timeOnServer = GetGameTime() - g_connectTime[i];
        player.SetFloat("time_on_server", timeOnServer);

        bool inGame = IsClientInGame(i);
        player.SetBool("in_game", inGame);

        if (inGame && g_gokzData[i].mode[0] != '\0')
        {
            JSONObject gokz = new JSONObject();
            gokz.SetString("mode", g_gokzData[i].mode);
            gokz.SetBool("timer_running", g_gokzData[i].timerRunning);
            gokz.SetBool("paused", g_gokzData[i].paused);
            gokz.SetFloat("time", g_gokzData[i].time);
            gokz.SetInt("course", g_gokzData[i].course);
            gokz.SetInt("teleports", g_gokzData[i].teleports);
            player.Set("gokz", gokz);
            delete gokz;
        }

        JSONObject playtimeModes = BuildModePlaytimeObject(i);
        if (playtimeModes != null)
        {
            player.Set("playtime_modes", playtimeModes);
            delete playtimeModes;
        }

        players.Push(player);
        delete player;
    }

    return players;
}

// Builds the per-mode playtime delta object (seconds accrued since the last report).
// Returns null when no mode time has accrued, so the field is omitted.
JSONObject BuildModePlaytimeObject(int client)
{
    JSONObject obj = null;

    for (int m = 0; m < MODE_COUNT; m++)
    {
        if (g_modePlaytime[client][m] <= 0.0)
            continue;

        if (obj == null)
            obj = new JSONObject();

        obj.SetFloat(gC_ModeApiKeys[m], g_modePlaytime[client][m]);
    }

    return obj;
}

JSONArray BuildPluginsArray()
{
    JSONArray plugins = new JSONArray();

    Handle    iter    = GetPluginIterator();
    while (MorePlugins(iter))
    {
        Handle       plugin       = ReadPlugin(iter);
        PluginStatus pluginStatus = GetPluginStatus(plugin);
        if (pluginStatus != Plugin_Running && pluginStatus != Plugin_Paused)
            continue;

        JSONObject pl = new JSONObject();

        char       buffer[256];
        GetPluginInfo(plugin, PlInfo_Name, buffer, sizeof(buffer));
        pl.SetString("name", buffer);

        GetPluginInfo(plugin, PlInfo_Version, buffer, sizeof(buffer));
        pl.SetString("version", buffer);

        GetPluginInfo(plugin, PlInfo_Author, buffer, sizeof(buffer));
        pl.SetString("author", buffer);

        GetPluginFilename(plugin, buffer, sizeof(buffer));
        pl.SetString("file", buffer);

        pl.SetString("status", pluginStatus == Plugin_Running ? "running" : "paused");

        plugins.Push(pl);
        delete pl;
    }
    CloseHandle(iter);

    return plugins;
}
