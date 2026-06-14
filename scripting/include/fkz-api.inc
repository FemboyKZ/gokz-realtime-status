/**
 * FKZ API - Native include
 *
 * Async wrappers around the FKZ REST API (https://api.femboykz.com).
 * Requires the fkz-api plugin to be running and sm-ext-json.
 *
 * Usage:
 *   #include <fkz-api>
 *
 *   public void OnPluginStart()
 *   {
 *       FKZ_GetKzPlayer("STEAM_1:0:1234", OnPlayer);
 *   }
 *
 *   void OnPlayer(bool success, int statusCode, JSON response, const char[] body, any data)
 *   {
 *       if (!success || response == null)
 *           return;
 *       // response is a JSONObject or JSONArray owned by the fkz-api plugin.
 *       // It is freed after this callback returns - DeepCopy it to keep it.
 *   }
 *
 * Every native returns true if the request was dispatched (the actual HTTP result arrives later in the callback)
 * and false if it could not be sent.
 */

#if defined _fkz_api_included
    #endinput
#endif
#define _fkz_api_included

#include <json>

/**
 * Result callback for all FKZ API natives.
 *
 * @param success     True if the HTTP status was 2xx.
 * @param statusCode  HTTP status code (0 on transport error).
 * @param response    Parsed JSON document, or null when the body is empty or not valid JSON.
 *                    Owned by the fkz-api plugin and freed after the callback returns,
 *                    use JSON.DeepCopy to retain it.
 * @param body        Raw response body.
 * @param data        Opaque value passed to the originating native.
 */
typedef FKZ_ResponseCallback = function void(bool success, int statusCode, JSON response, const char[] body, any data);

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------

/**
 * Sends an arbitrary request to any FKZ API endpoint.
 *
 * @param method    HTTP verb: GET, POST, PUT, PATCH or DELETE (case-insensitive).
 * @param path      Endpoint path, e.g. "/kzglobal/records?limit=10".
 *                  Leading slash optional.
 * @param body      JSON body for POST/PUT/PATCH, or null.
 *                  Not freed by the native - the caller may delete it once this returns.
 * @param callback  Result callback.
 * @param data      Opaque value forwarded to the callback.
 * @return          True if dispatched, false otherwise.
 */
native bool  FKZ_ApiRequest(const char[] method, const char[] path, JSON body, FKZ_ResponseCallback callback, any data = 0);

/**
 * Copies the configured API base URL (api_url, e.g. "https://api.femboykz.com").
 *
 * @return          Length of the base URL.
 */
native int   FKZ_GetApiBase(char[] buffer, int maxlength);

/** GET /health */
native bool  FKZ_GetHealth(FKZ_ResponseCallback callback, any data = 0);

/**
 * POST /servers/status - submits a live server status report.
 * Requires api_key (admin auth).
 * This is the same endpoint the plugin's own status updater uses.
 *
 * @param payload   JSON body to send.
 * @param callback  Result callback.
 * @param data      Opaque value forwarded to the callback.
 */
native bool  FKZ_PostServerStatus(JSON payload, FKZ_ResponseCallback callback, any data = 0);

/**
 * POST /servers/status/hibernate - signals the server is empty/hibernating.
 * Requires api_key (admin auth).
 *
 * @param payload   JSON body to send (typically { ip, port }).
 * @param callback  Result callback.
 * @param data      Opaque value forwarded to the callback.
 */
native bool  FKZ_PostHibernate(JSON payload, FKZ_ResponseCallback callback, any data = 0);

// ---------------------------------------------------------------------------
// Live servers / players / maps
// ---------------------------------------------------------------------------

/** GET /servers  (limit/offset/sort) */
native bool  FKZ_GetServers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /servers/{ip}  (ip may be "ip" or "ip:port") */
native bool  FKZ_GetServer(const char[] ip, FKZ_ResponseCallback callback, any data = 0);

/** GET /players  (limit/offset/sort) */
native bool  FKZ_GetPlayers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /players/online  (limit/offset/sort) */
native bool  FKZ_GetOnlinePlayers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /players/{steamid} */
native bool  FKZ_GetPlayer(const char[] steamid, FKZ_ResponseCallback callback, any data = 0);

/** GET /maps  (limit/offset/sort) */
native bool  FKZ_GetMaps(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /maps/{mapname} */
native bool  FKZ_GetMap(const char[] mapname, FKZ_ResponseCallback callback, any data = 0);

// ---------------------------------------------------------------------------
// KZ Global - records
// ---------------------------------------------------------------------------

/** GET /kzglobal/records  (limit/offset/sort) */
native bool  FKZ_GetKzRecords(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/records/recent  (limit/offset/sort) */
native bool  FKZ_GetKzRecentRecords(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/records/worldrecords  (limit/offset/sort) */
native bool  FKZ_GetKzWorldRecords(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/records/leaderboard/{mapname}  (limit/offset/sort) */
native bool  FKZ_GetKzLeaderboard(const char[] mapname, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/records/{id} */
native bool  FKZ_GetKzRecord(int id, FKZ_ResponseCallback callback, any data = 0);

// ---------------------------------------------------------------------------
// KZ Global - players
// ---------------------------------------------------------------------------

/** GET /kzglobal/players  (limit/offset/sort) */
native bool  FKZ_GetKzPlayers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/players/{steamid} */
native bool  FKZ_GetKzPlayer(const char[] steamid, FKZ_ResponseCallback callback, any data = 0);

/** GET /kzglobal/players/{steamid}/records  (limit/offset/sort) */
native bool  FKZ_GetKzPlayerRecords(const char[] steamid, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/players/{steamid}/pbs  (limit/offset/sort) */
native bool  FKZ_GetKzPlayerPBs(const char[] steamid, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/players/{steamid}/completions  (limit/offset/sort) */
native bool  FKZ_GetKzPlayerCompletions(const char[] steamid, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

// ---------------------------------------------------------------------------
// KZ Global - maps
// ---------------------------------------------------------------------------

/** GET /kzglobal/maps  (limit/offset/sort) */
native bool  FKZ_GetKzMaps(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/maps/{mapname} */
native bool  FKZ_GetKzMap(const char[] mapname, FKZ_ResponseCallback callback, any data = 0);

/** GET /kzglobal/maps/{mapname}/records  (limit/offset/sort) */
native bool  FKZ_GetKzMapRecords(const char[] mapname, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/maps/{mapname}/courses  (limit/offset/sort) */
native bool  FKZ_GetKzMapCourses(const char[] mapname, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

// ---------------------------------------------------------------------------
// KZ Global - servers
// ---------------------------------------------------------------------------

/** GET /kzglobal/servers  (limit/offset/sort) */
native bool  FKZ_GetKzServers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/servers/{id} */
native bool  FKZ_GetKzServer(int id, FKZ_ResponseCallback callback, any data = 0);

// ---------------------------------------------------------------------------
// KZ Global - bans
// ---------------------------------------------------------------------------

/** GET /kzglobal/bans  (limit/offset/sort) */
native bool  FKZ_GetKzBans(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/bans/active  (limit/offset/sort) */
native bool  FKZ_GetKzActiveBans(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzglobal/bans/{id} */
native bool  FKZ_GetKzBan(int id, FKZ_ResponseCallback callback, any data = 0);

/** GET /kzglobal/bans/player/{steamid}  (limit/offset/sort) */
native bool  FKZ_GetKzPlayerBans(const char[] steamid, FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

// ---------------------------------------------------------------------------
// KZ Local (CS:GO 128/64 tick)
// ---------------------------------------------------------------------------

/** GET /kzlocal/maps  (limit/offset/sort) */
native bool  FKZ_GetLocalMaps(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzlocal/maps/{mapname} */
native bool  FKZ_GetLocalMap(const char[] mapname, FKZ_ResponseCallback callback, any data = 0);

/** GET /kzlocal/records  (limit/offset/sort) */
native bool  FKZ_GetLocalRecords(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzlocal/players  (limit/offset/sort) */
native bool  FKZ_GetLocalPlayers(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

// ---------------------------------------------------------------------------
// KZ Local CS2
// ---------------------------------------------------------------------------

/** GET /kzlocal-cs2/maps  (limit/offset/sort) */
native bool  FKZ_GetLocalCS2Maps(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzlocal-cs2/records  (limit/offset/sort) */
native bool  FKZ_GetLocalCS2Records(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzlocal-cs2/players  (limit/offset/sort) */
native bool  FKZ_GetLocalCS2Players(FKZ_ResponseCallback callback, int limit = 0, int offset = 0, const char[] sort = "", any data = 0);

/** GET /kzlocal-cs2/stats */
native bool  FKZ_GetLocalCS2Stats(FKZ_ResponseCallback callback, any data = 0);

// ---------------------------------------------------------------------------
#if !defined FKZ_API_LIBRARY

public SharedPlugin __pl_fkz_api = {
    name = "fkz-api",
    file = "fkz-api.smx",
    #if defined REQUIRE_PLUGIN
    required = 1,
    #else
    required = 0,
    #endif
};

    #if !defined REQUIRE_PLUGIN

public void __pl_fkz_api_SetNTVOptional()
{
    MarkNativeAsOptional("FKZ_ApiRequest");

    MarkNativeAsOptional("FKZ_GetApiBase");
    MarkNativeAsOptional("FKZ_GetHealth");

    MarkNativeAsOptional("FKZ_PostServerStatus");
    MarkNativeAsOptional("FKZ_PostHibernate");

    MarkNativeAsOptional("FKZ_GetServers");
    MarkNativeAsOptional("FKZ_GetServer");
    MarkNativeAsOptional("FKZ_GetPlayers");
    MarkNativeAsOptional("FKZ_GetOnlinePlayers");
    MarkNativeAsOptional("FKZ_GetPlayer");
    MarkNativeAsOptional("FKZ_GetMaps");
    MarkNativeAsOptional("FKZ_GetMap");

    MarkNativeAsOptional("FKZ_GetKzRecords");
    MarkNativeAsOptional("FKZ_GetKzRecentRecords");
    MarkNativeAsOptional("FKZ_GetKzWorldRecords");
    MarkNativeAsOptional("FKZ_GetKzLeaderboard");
    MarkNativeAsOptional("FKZ_GetKzRecord");
    MarkNativeAsOptional("FKZ_GetKzPlayers");
    MarkNativeAsOptional("FKZ_GetKzPlayer");
    MarkNativeAsOptional("FKZ_GetKzPlayerRecords");
    MarkNativeAsOptional("FKZ_GetKzPlayerPBs");
    MarkNativeAsOptional("FKZ_GetKzPlayerCompletions");
    MarkNativeAsOptional("FKZ_GetKzMaps");
    MarkNativeAsOptional("FKZ_GetKzMap");
    MarkNativeAsOptional("FKZ_GetKzMapRecords");
    MarkNativeAsOptional("FKZ_GetKzMapCourses");
    MarkNativeAsOptional("FKZ_GetKzServers");
    MarkNativeAsOptional("FKZ_GetKzServer");
    MarkNativeAsOptional("FKZ_GetKzBans");
    MarkNativeAsOptional("FKZ_GetKzActiveBans");
    MarkNativeAsOptional("FKZ_GetKzBan");
    MarkNativeAsOptional("FKZ_GetKzPlayerBans");

    MarkNativeAsOptional("FKZ_GetLocalMaps");
    MarkNativeAsOptional("FKZ_GetLocalMap");
    MarkNativeAsOptional("FKZ_GetLocalRecords");
    MarkNativeAsOptional("FKZ_GetLocalPlayers");

    MarkNativeAsOptional("FKZ_GetLocalCS2Maps");
    MarkNativeAsOptional("FKZ_GetLocalCS2Records");
    MarkNativeAsOptional("FKZ_GetLocalCS2Players");
    MarkNativeAsOptional("FKZ_GetLocalCS2Stats");
}
    #endif    // !REQUIRE_PLUGIN

#endif    // !FKZ_API_LIBRARY
