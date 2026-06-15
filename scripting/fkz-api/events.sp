/**
 * FKZ API - Forwards & timers
 *
 * Plugin/map/client lifecycle, GOKZ forwards, SteamWorks VAC callback and the report timers.
 */
public void OnPluginStart()
{
    LoadConfig();

    if (g_apiUrl[0] == '\0')
    {
        LogMessage("[FKZ] No api_url configured, reporting disabled");
        return;
    }

    LogMessage("[FKZ] v%s loaded - reporting to %s every %.0fs (key=%s)",
               PLUGIN_VERSION, g_apiUrl, g_interval, g_apiKey[0] != '\0' ? "set" : "NOT SET");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i))
        {
            g_connectTime[i] = GetGameTime() - GetClientTime(i);
            if (IsClientInGame(i))
            {
                UpdateGokzData(i);
                InitModePlaytime(i);
            }
        }
    }
}

public void OnMapStart()
{
    if (g_apiUrl[0] == '\0')
        return;

    CacheStaticServerInfo();

    StopReportTimer();
    g_reportTimer = CreateTimer(g_interval, Timer_Report, _, TIMER_REPEAT);

    CreateTimer(2.0, Timer_InitialReport);
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
        return;

    g_connectTime[client] = GetGameTime();
    ResetGokzData(client);
    InitModePlaytime(client);
}

public void OnClientDisconnect(int client)
{
    if (!IsFakeClient(client))
    {
        int humans = 0;
        for (int i = 1; i <= MaxClients; i++)
        {
            if (i != client && IsClientConnected(i) && !IsFakeClient(i))
            {
                humans++;
                break;
            }
        }
        if (humans == 0)
            SendHibernate();
    }

    g_connectTime[client] = 0.0;
    ResetGokzData(client);
    ResetModePlaytimeDeltas(client);
    g_lastModeSample[client] = 0.0;
}

public int SteamWorks_SteamServersConnected()
{
    g_cachedSecureAvailable = true;
    g_cachedSecure          = SteamWorks_IsVACEnabled();
    LogMessage("[FKZ] Steam connected, VAC status: %s", g_cachedSecure ? "secure" : "insecure");
    return 0;
}

public void GOKZ_OnTimerStart_Post(int client, int course)
{
    UpdateGokzData(client);
}

public void GOKZ_OnTimerEnd_Post(int client, int course, float time, int teleportsUsed)
{
    UpdateGokzData(client);
}

public void GOKZ_OnTimerStopped(int client)
{
    UpdateGokzData(client);
}

public void GOKZ_OnPause_Post(int client)
{
    UpdateGokzData(client);
}

public void GOKZ_OnResume_Post(int client)
{
    UpdateGokzData(client);
}

public void GOKZ_OnOptionChanged(int client, const char[] option, any newValue)
{
    if (StrEqual(option, "GOKZ - Mode"))
    {
        // Attribute time spent so far to the old mode before it switches.
        SampleModePlaytime(client);
        UpdateGokzData(client);
    }
}

public Action Timer_Report(Handle timer, any data)
{
    SendReport();
    return Plugin_Continue;
}

public Action Timer_InitialReport(Handle timer, any data)
{
    SendReport();
    return Plugin_Stop;
}
