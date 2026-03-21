/**
 * GOKZ Realtime Status
 *
 * Reports server status, player info, and GOKZ data to an API endpoint.
 *
 * Dependencies (required):
 *   - sm-ext-json (ProjectSky/sm-ext-json)
 *   - sm-ext-websocket (ProjectSky/sm-ext-websocket)
 *   - gokz-core
 *
 * Dependencies (optional):
 *   - SteamWorks (for VAC status detection)
 *
 * Configuration: addons/sourcemod/configs/gokz-rts.cfg
 */

#include <sourcemod>
#include <json>
#include <websocket>
#include <gokz/core>

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>
#define REQUIRE_EXTENSIONS

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0.0"
#define MODE_NAME_LEN 32

public Plugin myinfo =
{
	name = "GOKZ Realtime Status",
	author = "jvnipers",
	description = "Reports server/player/GOKZ data to API via HTTP",
	version = PLUGIN_VERSION,
	url = "https://github.com/FemboyKZ/gokz-realtime-status"
};

// Config

static char g_apiUrl[256];
static char g_apiKey[256];
static char g_serverIp[64];
static int g_serverPort;
static float g_interval = 10.0;

// Per-player GOKZ tracking

enum struct GokzData
{
	char mode[MODE_NAME_LEN];
	bool timerRunning;
	bool paused;
	float time;
	int course;
	int teleports;
}

static GokzData g_gokzData[MAXPLAYERS + 1];
static float g_connectTime[MAXPLAYERS + 1];

// State

static Handle g_reportTimer = INVALID_HANDLE;
static char g_osName[16];
static int g_successCount;

//  Lifecycle

public void OnPluginStart()
{
	LoadConfig();
	DetectOS();

	if (g_apiUrl[0] == '\0')
	{
		LogMessage("[gokz-rts] No api_url configured, reporting disabled");
		return;
	}

	LogMessage("[gokz-rts] v%s loaded - reporting to %s every %.0fs (key=%s)",
		PLUGIN_VERSION, g_apiUrl, g_interval, g_apiKey[0] != '\0' ? "set" : "NOT SET");

	// Late load: estimate connect time for existing players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && !IsFakeClient(i))
		{
			g_connectTime[i] = GetGameTime() - GetClientTime(i);
			if (IsClientInGame(i))
				UpdateGokzData(i);
		}
	}
}

public void OnMapStart()
{
	if (g_apiUrl[0] == '\0')
		return;

	StopReportTimer();
	g_reportTimer = CreateTimer(g_interval, Timer_Report, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	// Initial report after short delay to let server stabilize
	CreateTimer(2.0, Timer_InitialReport);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;

	g_connectTime[client] = GetGameTime();
	ResetGokzData(client);
}

public void OnClientDisconnect(int client)
{
	g_connectTime[client] = 0.0;
	ResetGokzData(client);
}

//  GOKZ Forwards

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
		UpdateGokzData(client);
}

//  Timer Callbacks

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

//  Core: HTTP Reporting

void SendReport()
{
	// Refresh GOKZ data for all players before building payload
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			UpdateGokzData(i);
	}

	JSONObject payload = BuildPayload();

	HttpRequest req = new HttpRequest(g_apiUrl);
	req.Timeout = 10000;
	req.KeepAlive = true;

	if (g_apiKey[0] != '\0')
		req.SetBearerAuth(g_apiKey);

	bool sent = req.PostJson(payload, OnHttpResponse);
	delete payload;

	if (!sent)
	{
		LogError("[gokz-rts] Failed to send request to %s", g_apiUrl);
		delete req;
	}
}

void OnHttpResponse(HttpRequest http, const char[] body, int statusCode, int bodySize, any value)
{
	if (statusCode == 200)
	{
		g_successCount++;
		if (g_successCount == 1 || g_successCount % 30 == 0)
			LogMessage("[gokz-rts] POST OK (count=%d)", g_successCount);
	}
	else
	{
		LogError("[gokz-rts] POST returned HTTP %d: %.512s", statusCode, body);
	}

	delete http;
}

//  Payload Building

JSONObject BuildPayload()
{
	JSONObject payload = new JSONObject();

	JSONObject server = BuildServerObject();
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

	// Hostname
	char hostname[256];
	ConVar cvHostname = FindConVar("hostname");
	if (cvHostname != null)
		cvHostname.GetString(hostname, sizeof(hostname));
	else
		strcopy(hostname, sizeof(hostname), "unknown");
	server.SetString("hostname", hostname);

	// IP (config override or hostip ConVar)
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

	// Port (config override or hostport ConVar)
	int port = g_serverPort > 0 ? g_serverPort : FindConVar("hostport").IntValue;
	server.SetInt("port", port);

	// OS
	server.SetString("os", g_osName);

	// Map
	char map[256];
	GetCurrentMap(map, sizeof(map));
	server.SetString("map", map);

	// Player/bot counts
	int playerCount = 0;
	int botCount = 0;
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

	// Game version
	char version[64];
	ConVar cvVersion = FindConVar("version");
	if (cvVersion != null)
		cvVersion.GetString(version, sizeof(version));
	else
		version[0] = '\0';
	server.SetString("version", version);

	// Tickrate
	int tickrate = RoundToNearest(1.0 / GetTickInterval());
	server.SetInt("tickrate", tickrate);

	// Secure (VAC status via SteamWorks)
	if (GetFeatureStatus(FeatureType_Native, "SteamWorks_IsVACEnabled") == FeatureStatus_Available)
		server.SetBool("secure", SteamWorks_IsVACEnabled());
	else
		server.SetNull("secure");

	// MetaMod version
	ConVar cvMM = FindConVar("metamod_version");
	if (cvMM != null)
	{
		char mmVer[64];
		cvMM.GetString(mmVer, sizeof(mmVer));
		server.SetString("mm_version", mmVer);
	}

	// SourceMod version
	server.SetString("sm_version", SOURCEMOD_VERSION);

	// GOKZ loaded (obsolete)
	server.SetBool("gokz_loaded", true);

	// Plugins
	JSONArray plugins = BuildPluginsArray();
	server.Set("plugins", plugins);
	delete plugins;

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

		char steamid[32];
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

		// GOKZ data
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

		players.Push(player);
		delete player;
	}

	return players;
}

JSONArray BuildPluginsArray()
{
	JSONArray plugins = new JSONArray();

	Handle iter = GetPluginIterator();
	while (MorePlugins(iter))
	{
		Handle plugin = ReadPlugin(iter);
		PluginStatus pluginStatus = GetPluginStatus(plugin);
		if (pluginStatus != Plugin_Running && pluginStatus != Plugin_Paused)
			continue;

		JSONObject pl = new JSONObject();

		char buffer[256];
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

//  GOKZ Data

void UpdateGokzData(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return;

	int mode = GOKZ_GetCoreOption(client, Option_Mode);
	g_gokzData[client].timerRunning = GOKZ_GetTimerRunning(client);
	g_gokzData[client].paused = GOKZ_GetPaused(client);
	g_gokzData[client].time = GOKZ_GetTime(client);
	g_gokzData[client].course = GOKZ_GetCourse(client);
	g_gokzData[client].teleports = GOKZ_GetTeleportCount(client);
	strcopy(g_gokzData[client].mode, MODE_NAME_LEN, gC_ModeNames[mode]);
}

void ResetGokzData(int client)
{
	g_gokzData[client].mode[0] = '\0';
	g_gokzData[client].timerRunning = false;
	g_gokzData[client].paused = false;
	g_gokzData[client].time = 0.0;
	g_gokzData[client].course = 0;
	g_gokzData[client].teleports = 0;
}

//  Config

void LoadConfig()
{
	char cfgPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/gokz-rts.cfg");

	File file = OpenFile(cfgPath, "r");
	if (file == null)
	{
		LogError("[gokz-rts] Config not found: %s", cfgPath);
		return;
	}

	char line[512];
	while (file.ReadLine(line, sizeof(line)))
	{
		TrimString(line);

		// Skip comments and empty lines
		if (line[0] == '/' || line[0] == '#' || line[0] == '\0')
			continue;

		char key[64], value[256];
		if (ParseConfigLine(line, key, sizeof(key), value, sizeof(value)))
		{
			if (StrEqual(key, "api_url"))
				strcopy(g_apiUrl, sizeof(g_apiUrl), value);
			else if (StrEqual(key, "api_key"))
				strcopy(g_apiKey, sizeof(g_apiKey), value);
			else if (StrEqual(key, "server_ip"))
				strcopy(g_serverIp, sizeof(g_serverIp), value);
			else if (StrEqual(key, "server_port"))
				g_serverPort = StringToInt(value);
			else if (StrEqual(key, "interval"))
			{
				g_interval = StringToFloat(value);
				if (g_interval < 1.0)
					g_interval = 1.0;
			}
		}
	}

	delete file;
}

bool ParseConfigLine(const char[] line, char[] key, int keyLen, char[] value, int valueLen)
{
	int pos = 0;

	// Skip leading whitespace
	while (line[pos] == ' ' || line[pos] == '\t')
		pos++;

	// Read key (optionally quoted)
	if (line[pos] == '"')
	{
		pos++;
		int start = pos;
		while (line[pos] != '"' && line[pos] != '\0')
			pos++;
		int len = pos - start;
		if (len >= keyLen)
			len = keyLen - 1;
		strcopy(key, len + 1, line[start]);
		if (line[pos] == '"')
			pos++;
	}
	else
	{
		int start = pos;
		while (line[pos] != ' ' && line[pos] != '\t' && line[pos] != '\0')
			pos++;
		int len = pos - start;
		if (len >= keyLen)
			len = keyLen - 1;
		strcopy(key, len + 1, line[start]);
	}

	// Skip whitespace between key and value
	while (line[pos] == ' ' || line[pos] == '\t')
		pos++;

	// Read value (must be quoted)
	if (line[pos] == '"')
	{
		pos++;
		int start = pos;
		while (line[pos] != '"' && line[pos] != '\0')
			pos++;
		int len = pos - start;
		if (len >= valueLen)
			len = valueLen - 1;
		strcopy(value, len + 1, line[start]);
		return true;
	}

	return false;
}

//  Helpers

void DetectOS()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "");

	if (path[0] == '/')
		strcopy(g_osName, sizeof(g_osName), "linux");
	else
		strcopy(g_osName, sizeof(g_osName), "windows");
}

void StopReportTimer()
{
	if (g_reportTimer != INVALID_HANDLE)
	{
		KillTimer(g_reportTimer);
		g_reportTimer = INVALID_HANDLE;
	}
}
