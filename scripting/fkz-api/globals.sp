/**
 * FKZ API - Global state
 *
 * Shared config, cached server info and per-client tracking data.
 * Included first so all globals are declared before any function uses them.
 */

char  g_apiUrl[256];
char  g_apiKey[256];
char  g_serverIp[64];
char  g_tlsCAFile[PLATFORM_MAX_PATH];
int   g_serverPort;
float g_interval = 10.0;
int   g_failCount;

enum struct GokzData
{
    char  mode[MODE_NAME_LEN];
    bool  timerRunning;
    bool  paused;
    float time;
    int   course;
    int   teleports;
}

GokzData  g_gokzData[MAXPLAYERS + 1];
float     g_connectTime[MAXPLAYERS + 1];

Handle    g_reportTimer = INVALID_HANDLE;
char      g_osName[16];
int       g_successCount;

char      g_cachedHostname[256];
char      g_cachedVersion[256];
char      g_cachedMMVersion[64];
int       g_cachedTickrate;
bool      g_cachedSecure;
bool      g_cachedSecureAvailable;
JSONArray g_cachedPlugins = null;
