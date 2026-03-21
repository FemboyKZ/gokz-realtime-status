#include "extension.h"
#include "http_client.h"
#include <sourcemod_version.h>

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <chrono>

CSMExtension g_SMExtension;
SMEXT_LINK(&g_SMExtension);

// Configuration values (loaded from cfg file)
static char g_apiUrl[256] = "";
static char g_apiKey[256] = "";
static float g_interval = 10.0f;

static const char *g_modeNames[] = { "Vanilla", "SimpleKZ", "KZTimer" };

// escape a string for JSON
static std::string JsonEscape(const char *str)
{
	if (!str)
		return "";

	std::string out;
	out.reserve(strlen(str) + 16);
	for (const char *p = str; *p; ++p)
	{
		switch (*p)
		{
			case '"':  out += "\\\""; break;
			case '\\': out += "\\\\"; break;
			case '\b': out += "\\b"; break;
			case '\f': out += "\\f"; break;
			case '\n': out += "\\n"; break;
			case '\r': out += "\\r"; break;
			case '\t': out += "\\t"; break;
			default:
				if ((unsigned char)*p < 0x20)
				{
					char buf[8];
					snprintf(buf, sizeof(buf), "\\u%04x", (unsigned char)*p);
					out += buf;
				}
				else
				{
					out += *p;
				}
				break;
		}
	}
	return out;
}

// SourcePawn Natives, called by companion plugin

// native void RTS_SetGokzLoaded(bool loaded);
static cell_t Native_SetGokzLoaded(IPluginContext *pContext, const cell_t *params)
{
	g_SMExtension.SetGokzLoaded(params[1] != 0);
	return 0;
}

// native void RTS_SetPlayerGokzData(int client, int mode, bool timerRunning, bool paused, float time, int course, int teleports);
static cell_t Native_SetPlayerGokzData(IPluginContext *pContext, const cell_t *params)
{
	int client = params[1];
	if (client < 1 || client > RTS_MAX_PLAYERS)
		return pContext->ThrowNativeError("Invalid client index %d", client);

	PlayerGokzData data;
	data.mode = (GokzMode)params[2];
	data.timerRunning = (params[3] != 0);
	data.paused = (params[4] != 0);
	data.time = sp_ctof(params[5]);
	data.course = params[6];
	data.teleportCount = params[7];

	g_SMExtension.SetPlayerGokzData(client, data);
	return 0;
}

// native void RTS_SetServerInfo(const char[] hostname, const char[] ip, int port);
static cell_t Native_SetServerInfo(IPluginContext *pContext, const cell_t *params)
{
	char *hostname, *ip;
	pContext->LocalToString(params[1], &hostname);
	pContext->LocalToString(params[2], &ip);
	int port = params[3];

	g_SMExtension.SetServerInfo(hostname, ip, port);
	return 0;
}

static const sp_nativeinfo_t g_Natives[] =
{
	{ "RTS_SetGokzLoaded",     Native_SetGokzLoaded },
	{ "RTS_SetPlayerGokzData", Native_SetPlayerGokzData },
	{ "RTS_SetServerInfo",     Native_SetServerInfo },
	{ nullptr,                 nullptr },
};

bool CSMExtension::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
	char cfgPath[PLATFORM_MAX_PATH];
	smutils->BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/gokz-rts.cfg");

	FILE *fp = fopen(cfgPath, "r");
	if (fp)
	{
		char line[512];
		while (fgets(line, sizeof(line), fp))
		{
			char *p = line;
			while (*p == ' ' || *p == '\t') p++;
			if (*p == '/' || *p == '#' || *p == '\n' || *p == '\r' || *p == '\0')
				continue;

			char key[64], value[256];
			if (sscanf(p, "\"%63[^\"]\" \"%255[^\"]\"", key, value) == 2 ||
				sscanf(p, "%63s \"%255[^\"]\"", key, value) == 2)
			{
				if (strcmp(key, "api_url") == 0)
					snprintf(g_apiUrl, sizeof(g_apiUrl), "%s", value);
				else if (strcmp(key, "api_key") == 0)
					snprintf(g_apiKey, sizeof(g_apiKey), "%s", value);
				else if (strcmp(key, "interval") == 0)
					g_interval = (float)atof(value);
			}
		}
		fclose(fp);
	}
	else
	{
		smutils->LogMessage(myself, "[gokz-rts] Config not found: %s", cfgPath);
	}

	if (g_interval < 1.0f)
		g_interval = 1.0f;
	m_sendInterval = g_interval;

	memset(m_connectTime, 0, sizeof(m_connectTime));

	// Register natives for the companion SP plugin
	sharesys->AddNatives(myself, g_Natives);

	return true;
}
void CSMExtension::SDK_OnAllLoaded()
{
	playerhelpers->AddClientListener(this);
	plsys->AddPluginsListener(this);

	// Check if GOKZ is already loaded (late load)
	IPluginIterator *iter = plsys->GetPluginIterator();
	while (iter->MorePlugins())
	{
		IPlugin *pl = iter->GetPlugin();
		if (pl->GetStatus() == Plugin_Running)
		{
			const char *filename = pl->GetFilename();
			if (filename && strstr(filename, "gokz-core") != nullptr)
			{
				m_gokzLoaded.store(true);
				smutils->LogMessage(myself, "[gokz-rts] GOKZ detected (late load)");
				break;
			}
		}
		iter->NextPlugin();
	}
	delete iter;

	if (g_apiUrl[0] != '\0')
	{
		// Start game-thread snapshot timer (5s, updates cached data for worker)
		m_pSnapshotTimer = timersys->CreateTimer(this, 5.0f, nullptr, TIMER_FLAG_REPEAT);

		// Take an initial snapshot of dynamic + static data before starting the worker
		SnapshotGameState();
		SnapshotPlugins();

		// Start the worker thread (survives server hibernation)
		m_running.store(true);
		m_workerThread = std::thread(&CSMExtension::WorkerThread, this);

		smutils->LogMessage(myself, "[gokz-rts] Reporting to %s every %.0fs (hibernation-safe)", g_apiUrl, m_sendInterval);
	}
	else
	{
		smutils->LogMessage(myself, "[gokz-rts] No api_url configured, reporting disabled");
	}
}

void CSMExtension::SDK_OnUnload()
{
	// Stop the worker thread first
	m_running.store(false);
	m_cv.notify_all();
	if (m_workerThread.joinable())
		m_workerThread.join();

	if (m_pSnapshotTimer)
	{
		timersys->KillTimer(m_pSnapshotTimer);
		m_pSnapshotTimer = nullptr;
	}

	playerhelpers->RemoveClientListener(this);
	plsys->RemovePluginsListener(this);
}

// ITimedEvent, game-thread snapshot timer
// Updates cached data that the worker thread reads.
// When server hibernates and this stops ticking, the cached
// data stays valid (0 players, same map/hostname).
ResultType CSMExtension::OnTimer(ITimer *pTimer, void *pData)
{
	SnapshotGameState();
	return Pl_Continue;
}

void CSMExtension::OnTimerEnd(ITimer *pTimer, void *pData)
{
	m_pSnapshotTimer = nullptr;
}

// SnapshotGameState - game thread only
// Reads SM APIs and copies data into the mutex-protected cache.
void CSMExtension::SnapshotGameState()
{
	std::lock_guard<std::mutex> lock(m_dataMutex);

	const char *mapName = gamehelpers->GetCurrentMap();
	if (mapName)
		snprintf(m_mapName, sizeof(m_mapName), "%s", mapName);

	m_maxClients = playerhelpers->GetMaxClients();
	m_numPlayers = playerhelpers->GetNumPlayers();

	m_lastSnapshotTime = timersys->GetTickedTime();

	for (int i = 1; i <= m_maxClients; i++)
	{
		IGamePlayer *player = playerhelpers->GetGamePlayer(i);
		if (!player || !player->IsConnected() || player->IsFakeClient())
		{
			m_cachedPlayers[i].active = false;
			continue;
		}

		CachedPlayer &cp = m_cachedPlayers[i];
		cp.active = true;
		cp.inGame = player->IsInGame();
		cp.connectTime = m_connectTime[i];

		uint64_t steamid = player->GetSteamId64(false);
		snprintf(cp.steamid, sizeof(cp.steamid), "%llu", (unsigned long long)steamid);

		const char *name = player->GetName();
		snprintf(cp.name, sizeof(cp.name), "%s", name ? name : "");

		const char *ip = player->GetIPAddress();
		snprintf(cp.ip, sizeof(cp.ip), "%s", ip ? ip : "");

		// Copy current GOKZ data
		cp.gokz = m_playerGokz[i];
	}
}

// SnapshotPlugins, game thread only, event-driven
// Called on startup and when plugins load/unload.
// Plugin list rarely changes, no need to poll every 5s.
void CSMExtension::SnapshotPlugins()
{
	std::lock_guard<std::mutex> lock(m_dataMutex);

	m_cachedPlugins.clear();
	IPluginIterator *iter = plsys->GetPluginIterator();
	while (iter->MorePlugins())
	{
		IPlugin *pl = iter->GetPlugin();
		if (pl->GetStatus() == Plugin_Running || pl->GetStatus() == Plugin_Paused)
		{
			const sm_plugininfo_t *info = pl->GetPublicInfo();
			CachedPlugin cp;
			cp.name = info ? (info->name ? info->name : "unknown") : "unknown";
			cp.version = info ? (info->version ? info->version : "") : "";
			cp.author = info ? (info->author ? info->author : "") : "";
			cp.file = pl->GetFilename() ? pl->GetFilename() : "";
			cp.status = (pl->GetStatus() == Plugin_Running) ? "running" : "paused";
			m_cachedPlugins.push_back(std::move(cp));
		}
		iter->NextPlugin();
	}
	delete iter;
}

// WorkerThread, independent of game frames, survives
// server hibernation. Wakes on its own interval.
void CSMExtension::WorkerThread()
{
	while (m_running.load())
	{
		{
			std::unique_lock<std::mutex> lock(m_cvMutex);
			m_cv.wait_for(lock,
				std::chrono::milliseconds((int)(m_sendInterval * 1000.0f)),
				[this]() { return !m_running.load(); });
		}

		if (!m_running.load())
			break;

		std::string json = BuildPayload();
		SendPayload(json);
	}
}

// IClientListener
void CSMExtension::OnClientPutInServer(int client)
{
	if (client < 1 || client > RTS_MAX_PLAYERS)
		return;

	std::lock_guard<std::mutex> lock(m_dataMutex);
	m_connectTime[client] = timersys->GetTickedTime();
	m_playerGokz[client] = PlayerGokzData();
}

void CSMExtension::OnClientDisconnected(int client)
{
	if (client < 1 || client > RTS_MAX_PLAYERS)
		return;

	std::lock_guard<std::mutex> lock(m_dataMutex);
	m_connectTime[client] = 0.0f;
	m_playerGokz[client] = PlayerGokzData();
	m_cachedPlayers[client].active = false;
}

// IPluginsListener
void CSMExtension::OnPluginLoaded(IPlugin *plugin)
{
	const char *filename = plugin->GetFilename();
	if (filename && strstr(filename, "gokz-core") != nullptr)
	{
		m_gokzLoaded.store(true);
		smutils->LogMessage(myself, "[gokz-rts] GOKZ core loaded");
	}

	// Re-snapshot plugin list on any plugin load
	SnapshotPlugins();
}

void CSMExtension::OnPluginUnloaded(IPlugin *plugin)
{
	const char *filename = plugin->GetFilename();
	if (filename && strstr(filename, "gokz-core") != nullptr)
	{
		m_gokzLoaded.store(false);
		smutils->LogMessage(myself, "[gokz-rts] GOKZ core unloaded");

		std::lock_guard<std::mutex> lock(m_dataMutex);
		for (int i = 1; i <= RTS_MAX_PLAYERS; i++)
			m_playerGokz[i] = PlayerGokzData();
	}

	// Re-snapshot plugin list on any plugin unload
	SnapshotPlugins();
}

// SetPlayerGokzData (called from native on game thread)
void CSMExtension::SetPlayerGokzData(int client, const PlayerGokzData &data)
{
	if (client >= 1 && client <= RTS_MAX_PLAYERS)
	{
		std::lock_guard<std::mutex> lock(m_dataMutex);
		m_playerGokz[client] = data;
	}
}

void CSMExtension::SetGokzLoaded(bool loaded)
{
	m_gokzLoaded.store(loaded);
}

// SetServerInfo (called from companion plugin native)
void CSMExtension::SetServerInfo(const char *hostname, const char *ip, int port)
{
	std::lock_guard<std::mutex> lock(m_dataMutex);
	if (hostname)
		snprintf(m_hostname, sizeof(m_hostname), "%s", hostname);
	if (ip)
		snprintf(m_ip, sizeof(m_ip), "%s", ip);
	m_port = port;
}

// BuildPayload, reads ONLY from cached/atomic data.
// Safe to call from the worker thread.
std::string CSMExtension::BuildPayload()
{
	std::lock_guard<std::mutex> lock(m_dataMutex);

	std::string json;
	json.reserve(4096);
	json += "{";

	json += "\"server\":{";

	json += "\"hostname\":\"";
	json += JsonEscape(m_hostname[0] ? m_hostname : "unknown");
	json += "\",";

	json += "\"ip\":\"";
	json += JsonEscape(m_ip[0] ? m_ip : "0.0.0.0");
	json += "\",";

	char numBuf[32];
	snprintf(numBuf, sizeof(numBuf), "%d", m_port);
	json += "\"port\":";
	json += numBuf;
	json += ",";

#ifdef _WIN32
	json += "\"os\":\"windows\",";
#else
	json += "\"os\":\"linux\",";
#endif

	json += "\"map\":\"";
	json += JsonEscape(m_mapName);
	json += "\",";

	snprintf(numBuf, sizeof(numBuf), "%d", m_numPlayers);
	json += "\"players\":";
	json += numBuf;
	json += ",";
	snprintf(numBuf, sizeof(numBuf), "%d", m_maxClients);
	json += "\"max_players\":";
	json += numBuf;
	json += ",";

	// Metamod version (safe, g_SMAPI is a global, GetApiVersions is const)
	int mmMajor = 0, mmMinor = 0, mmPlVers = 0, mmPlMin = 0;
	g_SMAPI->GetApiVersions(mmMajor, mmMinor, mmPlVers, mmPlMin);

	char verBuf[64];
	snprintf(verBuf, sizeof(verBuf), "%d.%d", mmMajor, mmMinor);
	json += "\"mm_version\":\"";
	json += verBuf;
	json += "\",";

	json += "\"sm_version\":\"";
	json += JsonEscape(SOURCEMOD_VERSION);
	json += "\",";

	json += "\"gokz_loaded\":";
	json += m_gokzLoaded.load() ? "true" : "false";
	json += ",";

	// Plugins (from cache)
	json += "\"plugins\":[";
	{
		bool first = true;
		for (const auto &pl : m_cachedPlugins)
		{
			if (!first) json += ",";
			first = false;

			json += "{\"name\":\"";
			json += JsonEscape(pl.name.c_str());
			json += "\",\"version\":\"";
			json += JsonEscape(pl.version.c_str());
			json += "\",\"author\":\"";
			json += JsonEscape(pl.author.c_str());
			json += "\",\"file\":\"";
			json += JsonEscape(pl.file.c_str());
			json += "\",\"status\":\"";
			json += JsonEscape(pl.status.c_str());
			json += "\"}";
		}
	}
	json += "]";

	json += "},"; // end server

	// Players (from cache)
	json += "\"players\":[";
	{
		bool first = true;
		bool gokzLoaded = m_gokzLoaded.load();

		for (int i = 1; i <= m_maxClients; i++)
		{
			const CachedPlayer &cp = m_cachedPlayers[i];
			if (!cp.active)
				continue;

			if (!first) json += ",";
			first = false;

			json += "{";

			json += "\"steamid\":\"";
			json += cp.steamid;
			json += "\",";

			json += "\"name\":\"";
			json += JsonEscape(cp.name);
			json += "\",";

			json += "\"ip\":\"";
			json += JsonEscape(cp.ip);
			json += "\",";

			float timeOnServer = 0.0f;
			if (cp.connectTime > 0.0f && m_lastSnapshotTime > 0.0f)
				timeOnServer = m_lastSnapshotTime - cp.connectTime;

			char timeBuf[32];
			snprintf(timeBuf, sizeof(timeBuf), "%.1f", timeOnServer);
			json += "\"time_on_server\":";
			json += timeBuf;
			json += ",";

			json += "\"in_game\":";
			json += cp.inGame ? "true" : "false";

			if (gokzLoaded && cp.inGame && cp.gokz.mode != Mode_None)
			{
				json += ",\"gokz\":{";

				json += "\"mode\":\"";
				if (cp.gokz.mode >= 0 && cp.gokz.mode < MODE_COUNT)
					json += g_modeNames[cp.gokz.mode];
				else
					json += "unknown";
				json += "\",";

				json += "\"timer_running\":";
				json += cp.gokz.timerRunning ? "true" : "false";
				json += ",";

				json += "\"paused\":";
				json += cp.gokz.paused ? "true" : "false";
				json += ",";

				char gokzBuf[32];
				snprintf(gokzBuf, sizeof(gokzBuf), "%.3f", cp.gokz.time);
				json += "\"time\":";
				json += gokzBuf;
				json += ",";

				snprintf(gokzBuf, sizeof(gokzBuf), "%d", cp.gokz.course);
				json += "\"course\":";
				json += gokzBuf;
				json += ",";

				snprintf(gokzBuf, sizeof(gokzBuf), "%d", cp.gokz.teleportCount);
				json += "\"teleports\":";
				json += gokzBuf;

				json += "}";
			}

			json += "}";
		}
	}
	json += "]";

	json += "}";

	return json;
}

// SendPayload, blocking HTTP POST (called from worker thread)
void CSMExtension::SendPayload(const std::string &json)
{
	HttpPostJson(std::string(g_apiUrl), json, std::string(g_apiKey));
}
