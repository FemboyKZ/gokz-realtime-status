/**
 * FKZ API - GOKZ per-client data
 *
 * Snapshots a client's GOKZ timer/mode state into g_gokzData.
 */

void UpdateGokzData(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    int mode                        = GOKZ_GetCoreOption(client, Option_Mode);
    g_gokzData[client].timerRunning = GOKZ_GetTimerRunning(client);
    g_gokzData[client].paused       = GOKZ_GetPaused(client);
    g_gokzData[client].time         = GOKZ_GetTime(client);
    g_gokzData[client].course       = GOKZ_GetCourse(client);
    g_gokzData[client].teleports    = GOKZ_GetTeleportCount(client);
    strcopy(g_gokzData[client].mode, MODE_NAME_LEN, gC_ModeNames[mode]);
}

void ResetGokzData(int client)
{
    g_gokzData[client].mode[0]      = '\0';
    g_gokzData[client].timerRunning = false;
    g_gokzData[client].paused       = false;
    g_gokzData[client].time         = 0.0;
    g_gokzData[client].course       = 0;
    g_gokzData[client].teleports    = 0;
}

// Starts per-mode playtime tracking for a client (call on (re)connect).
void InitModePlaytime(int client)
{
    for (int m = 0; m < MODE_COUNT; m++)
        g_modePlaytime[client][m] = 0.0;

    g_lastModeSample[client] = GetGameTime();
    g_currentMode[client]    = (IsClientInGame(client) && !IsFakeClient(client))
                                 ? GOKZ_GetCoreOption(client, Option_Mode)
                                 : 0;
}

// Call before a mode change and before snapshotting a report so each mode gets its true share.
void SampleModePlaytime(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    float now  = GetGameTime();
    float last = g_lastModeSample[client];
    int   cur  = g_currentMode[client];

    if (last > 0.0 && now > last && cur >= 0 && cur < MODE_COUNT)
        g_modePlaytime[client][cur] += now - last;

    g_lastModeSample[client] = now;
    g_currentMode[client]    = GOKZ_GetCoreOption(client, Option_Mode);
}

void ResetModePlaytimeDeltas(int client)
{
    for (int m = 0; m < MODE_COUNT; m++)
        g_modePlaytime[client][m] = 0.0;
}
