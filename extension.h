#ifndef _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_

#include "smsdk_ext.h"
#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <condition_variable>

// Max players in Source engine
#define RTS_MAX_PLAYERS 65

// GOKZ mode enum values (from gokz/core.inc)
enum GokzMode
{
	Mode_Vanilla = 0,
	Mode_SimpleKZ = 1,
	Mode_KZTimer = 2,
	MODE_COUNT = 3,
	Mode_None = -1
};

// Per-player GOKZ state (set by companion plugin via natives)
struct PlayerGokzData
{
	GokzMode mode;
	bool timerRunning;
	bool paused;
	float time;
	int course;
	int teleportCount;

	PlayerGokzData()
		: mode(Mode_None), timerRunning(false), paused(false),
		  time(0.0f), course(0), teleportCount(0) {}
};

// Cached player info (snapshotted from game thread)
struct CachedPlayer
{
	bool active;
	char steamid[32];
	char name[128];
	char ip[64];
	float connectTime; // engine time at connect
	bool inGame;
	PlayerGokzData gokz;

	CachedPlayer() : active(false), connectTime(0.0f), inGame(false) {
		steamid[0] = '\0';
		name[0] = '\0';
		ip[0] = '\0';
	}
};

// Cached plugin info
struct CachedPlugin
{
	std::string name;
	std::string version;
	std::string author;
	std::string file;
	std::string status;
};

class CSMExtension :
	public SDKExtension,
	public ITimedEvent,
	public IClientListener,
	public IPluginsListener
{
public:
	// SDKExtension
	virtual bool SDK_OnLoad(char *error, size_t maxlength, bool late);
	virtual void SDK_OnAllLoaded();
	virtual void SDK_OnUnload();

	// ITimedEvent, game-thread timer for snapshotting SM data
	virtual ResultType OnTimer(ITimer *pTimer, void *pData);
	virtual void OnTimerEnd(ITimer *pTimer, void *pData);

	// IClientListener
	virtual void OnClientPutInServer(int client);
	virtual void OnClientDisconnected(int client);

	// IPluginsListener
	virtual void OnPluginLoaded(IPlugin *plugin);
	virtual void OnPluginUnloaded(IPlugin *plugin);

public:
	// Set GOKZ data for a player (called from native on game thread)
	void SetPlayerGokzData(int client, const PlayerGokzData &data);

	// Set whether GOKZ is available
	void SetGokzLoaded(bool loaded);

	// Set server info from companion plugin
	void SetServerInfo(const char *hostname, const char *ip, int port, const char *version, int tickrate, int secure);

private:
	// Snapshot SM state into thread-safe cache (game thread only)
	void SnapshotGameState();

	// Snapshot plugin list into cache (game thread only, event-driven)
	void SnapshotPlugins();

	// Build JSON from cached/thread-safe data (worker thread)
	std::string BuildPayload();

	// HTTP POST (worker thread)
	void SendPayload(const std::string &json);

	// Worker thread loop, runs independently of game frames
	void WorkerThread();

	float m_sendInterval = 10.0f;

	// SM timer for periodic game state snapshots (ticks with game frames)
	ITimer *m_pSnapshotTimer = nullptr;

	// GOKZ plugin tracking
	std::atomic<bool> m_gokzLoaded{false};

	// Shared data protected by m_dataMutex
	std::mutex m_dataMutex;

	// Server info (set by companion plugin + game thread snapshots)
	char m_hostname[256] = {};
	char m_ip[64] = {};
	int m_port = 27015;
	char m_mapName[256] = {};
	int m_numPlayers = 0;
	int m_maxClients = 0;
	int m_botCount = 0;

	char m_serverVersion[64] = {};
	int m_tickrate = 0;
	int m_secure = -1; // -1=unknown, 0=insecure, 1=secure

	// Per-player GOKZ data (written by companion plugin natives)
	PlayerGokzData m_playerGokz[RTS_MAX_PLAYERS + 1];
	float m_connectTime[RTS_MAX_PLAYERS + 1] = {};

	// Snapshotted data (written by game thread, read by worker thread)
	CachedPlayer m_cachedPlayers[RTS_MAX_PLAYERS + 1];
	std::vector<CachedPlugin> m_cachedPlugins;
	float m_lastSnapshotTime = 0.0f;

	// Worker thread (survives server hibernation)
	std::thread m_workerThread;
	std::atomic<bool> m_running{false};
	std::mutex m_cvMutex;
	std::condition_variable m_cv;
};

extern CSMExtension g_SMExtension;

#endif // _INCLUDE_SOURCEMOD_EXTENSION_PROPER_H_
