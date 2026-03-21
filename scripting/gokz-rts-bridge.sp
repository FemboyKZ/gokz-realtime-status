/**
 * GOKZ Realtime Status - Companion Plugin
 *
 * Bridges GOKZ data to the extension.
 * This plugin calls GOKZ natives and forwards the data to the extension
 * which handles HTTP reporting to the API.
 *
 * Requires: gokz-core, gokz-realtime-status extension
 */

#include <sourcemod>
#include <gokz/core>
#include <SteamWorks>
#include <gokz-rts>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "GOKZ Realtime Status Bridge",
	author = "jvnipers",
	description = "Bridges GOKZ data to the realtime status extension",
	version = "1.0.0",
	url = "https://github.com/FemboyKZ/gokz-realtime-status"
};

// Update interval in seconds for polling GOKZ data
#define UPDATE_INTERVAL 5.0

Handle g_hTimer = INVALID_HANDLE;

public void OnPluginStart()
{
	RTS_SetGokzLoaded(true);

	// Send server info immediately so extension has it even without a map change
	SendServerInfo();
}

public void OnPluginEnd()
{
	RTS_SetGokzLoaded(false);
}

public void OnMapStart()
{
	// Send server info to the extension
	SendServerInfo();

	if (g_hTimer != INVALID_HANDLE)
	{
		KillTimer(g_hTimer);
		g_hTimer = INVALID_HANDLE;
	}
	g_hTimer = CreateTimer(UPDATE_INTERVAL, Timer_UpdateGokzData, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_UpdateGokzData(Handle timer)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		int mode = GOKZ_GetCoreOption(client, Option_Mode);
		bool timerRunning = GOKZ_GetTimerRunning(client);
		bool paused = GOKZ_GetPaused(client);
		float time = GOKZ_GetTime(client);
		int course = GOKZ_GetCourse(client);
		int teleports = GOKZ_GetTeleportCount(client);

		RTS_SetPlayerGokzData(client, mode, timerRunning, paused, time, course, teleports);
	}

	return Plugin_Continue;
}

// Also update immediately on timer events for responsiveness

public void GOKZ_OnTimerStart_Post(int client, int course)
{
	UpdateClientGokzData(client);
}

public void GOKZ_OnTimerEnd_Post(int client, int course, float time, int teleportsUsed)
{
	UpdateClientGokzData(client);
}

public void GOKZ_OnTimerStopped(int client)
{
	UpdateClientGokzData(client);
}

public void GOKZ_OnPause_Post(int client)
{
	UpdateClientGokzData(client);
}

public void GOKZ_OnResume_Post(int client)
{
	UpdateClientGokzData(client);
}

public void GOKZ_OnOptionChanged(int client, const char[] option, any newValue)
{
	// Update when mode changes
	if (StrEqual(option, "GOKZ - Mode"))
	{
		UpdateClientGokzData(client);
	}
}

void UpdateClientGokzData(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;

	int mode = GOKZ_GetCoreOption(client, Option_Mode);
	bool timerRunning = GOKZ_GetTimerRunning(client);
	bool paused = GOKZ_GetPaused(client);
	float time = GOKZ_GetTime(client);
	int course = GOKZ_GetCourse(client);
	int teleports = GOKZ_GetTeleportCount(client);

	RTS_SetPlayerGokzData(client, mode, timerRunning, paused, time, course, teleports);
}

void SendServerInfo()
{
	char hostname[256];
	ConVar cvHostname = FindConVar("hostname");
	if (cvHostname != null)
		cvHostname.GetString(hostname, sizeof(hostname));
	else
		hostname = "unknown";

	int hostip = FindConVar("hostip").IntValue;
	int port = FindConVar("hostport").IntValue;

	// Convert integer IP to dotted notation
	char ip[64];
	FormatEx(ip, sizeof(ip), "%d.%d.%d.%d",
		(hostip >> 24) & 0xFF,
		(hostip >> 16) & 0xFF,
		(hostip >> 8) & 0xFF,
		hostip & 0xFF);

	char version[64];
	ConVar cvVersion = FindConVar("version");
	if (cvVersion != null)
		cvVersion.GetString(version, sizeof(version));
	else
		version = "";

	int tickrate = RoundToNearest(1.0 / GetTickInterval());

	bool secure = SteamWorks_IsVACEnabled();

	RTS_SetServerInfo(hostname, ip, port, version, tickrate, secure);
}
