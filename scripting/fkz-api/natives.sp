/**
 * FKZ API - Natives
 *
 * Exposes the FKZ REST API to other SourcePawn plugins.
 *
 * Design (see addons/sourcemod/scripting/include/fkz-api.inc):
 *   - FKZ_ApiRequest()  generic async request to any endpoint/method.
 *   - FKZ_Get*()        typed convenience wrappers for the main read endpoints.
 *
 * All requests are asynchronous.
 * The result is delivered to an FKZ_ResponseCallback with the HTTP status,
 * the parsed JSON document (null when the body is empty/unparseable) and the raw body.
 * The parsed handle is owned by this plugin and freed after the callback returns,
 * callers that need to keep it must DeepCopy it.
 *
 * Endpoints map to the API root configured as api_url in fkz-api.cfg
 * (e.g. https://api.femboykz.com).
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("fkz-api");

    // Core
    CreateNative("FKZ_ApiRequest", Native_ApiRequest);
    CreateNative("FKZ_GetApiBase", Native_GetApiBase);
    CreateNative("FKZ_GetHealth", Native_GetHealth);
    CreateNative("FKZ_PostServerStatus", Native_PostServerStatus);
    CreateNative("FKZ_PostHibernate", Native_PostHibernate);

    // Live servers / players / maps
    CreateNative("FKZ_GetServers", Native_GetServers);
    CreateNative("FKZ_GetServer", Native_GetServer);
    CreateNative("FKZ_GetPlayers", Native_GetPlayers);
    CreateNative("FKZ_GetOnlinePlayers", Native_GetOnlinePlayers);
    CreateNative("FKZ_GetPlayer", Native_GetPlayer);
    CreateNative("FKZ_GetMaps", Native_GetMaps);
    CreateNative("FKZ_GetMap", Native_GetMap);

    // KZ Global - records
    CreateNative("FKZ_GetKzRecords", Native_GetKzRecords);
    CreateNative("FKZ_GetKzRecentRecords", Native_GetKzRecentRecords);
    CreateNative("FKZ_GetKzWorldRecords", Native_GetKzWorldRecords);
    CreateNative("FKZ_GetKzLeaderboard", Native_GetKzLeaderboard);
    CreateNative("FKZ_GetKzRecord", Native_GetKzRecord);

    // KZ Global - players
    CreateNative("FKZ_GetKzPlayers", Native_GetKzPlayers);
    CreateNative("FKZ_GetKzPlayer", Native_GetKzPlayer);
    CreateNative("FKZ_GetKzPlayerRecords", Native_GetKzPlayerRecords);
    CreateNative("FKZ_GetKzPlayerPBs", Native_GetKzPlayerPBs);
    CreateNative("FKZ_GetKzPlayerCompletions", Native_GetKzPlayerCompletions);

    // KZ Global - maps
    CreateNative("FKZ_GetKzMaps", Native_GetKzMaps);
    CreateNative("FKZ_GetKzMap", Native_GetKzMap);
    CreateNative("FKZ_GetKzMapRecords", Native_GetKzMapRecords);
    CreateNative("FKZ_GetKzMapCourses", Native_GetKzMapCourses);

    // KZ Global - servers
    CreateNative("FKZ_GetKzServers", Native_GetKzServers);
    CreateNative("FKZ_GetKzServer", Native_GetKzServer);

    // KZ Global - bans
    CreateNative("FKZ_GetKzBans", Native_GetKzBans);
    CreateNative("FKZ_GetKzActiveBans", Native_GetKzActiveBans);
    CreateNative("FKZ_GetKzBan", Native_GetKzBan);
    CreateNative("FKZ_GetKzPlayerBans", Native_GetKzPlayerBans);

    // KZ Local (CS:GO)
    CreateNative("FKZ_GetLocalMaps", Native_GetLocalMaps);
    CreateNative("FKZ_GetLocalMap", Native_GetLocalMap);
    CreateNative("FKZ_GetLocalRecords", Native_GetLocalRecords);
    CreateNative("FKZ_GetLocalPlayers", Native_GetLocalPlayers);

    // KZ Local CS2
    CreateNative("FKZ_GetLocalCS2Maps", Native_GetLocalCS2Maps);
    CreateNative("FKZ_GetLocalCS2Records", Native_GetLocalCS2Records);
    CreateNative("FKZ_GetLocalCS2Players", Native_GetLocalCS2Players);
    CreateNative("FKZ_GetLocalCS2Stats", Native_GetLocalCS2Stats);

    return APLRes_Success;
}

/**
 * Native wrapper around FKZ_SendRequest:
 * packs the calling plugin's callback context and delivers the parsed result through OnNativeResponse.
 *
 * @param plugin    Owning plugin handle (from the native call).
 * @param method    HTTP verb (GET/POST/PUT/PATCH/DELETE), case-insensitive.
 * @param path      Endpoint path, with or without a leading slash.
 * @param body      JSON body for POST/PUT/PATCH (null otherwise). Not freed.
 * @param callback  Function to invoke with the result.
 * @param data      Opaque value forwarded to the callback.
 * @return          True if the request was dispatched.
 */
bool DoApiRequest(Handle plugin, const char[] method, const char[] path, JSON body, Function callback, any data)
{
    if (callback == INVALID_FUNCTION)
    {
        LogError("[FKZ] FKZ_ApiRequest: invalid callback");
        return false;
    }

    DataPack ctx = new DataPack();
    ctx.WriteCell(plugin);
    ctx.WriteFunction(callback);
    ctx.WriteCell(data);

    if (!FKZ_SendRequest(method, path, body, OnNativeResponse, ctx))
    {
        delete ctx;
        return false;
    }

    return true;
}

void OnNativeResponse(HttpRequest http, const char[] body, int statusCode, int bodySize, any value)
{
    DataPack ctx = view_as<DataPack>(value);
    ctx.Reset();
    Handle   plugin   = ctx.ReadCell();
    Function callback = ctx.ReadFunction();
    any      data     = ctx.ReadCell();
    delete ctx;

    bool success = (statusCode >= 200 && statusCode < 300);

    JSON parsed  = null;
    if (body[0] != '\0')
        parsed = view_as<JSON>(JSON.Parse(body));

    Call_StartFunction(plugin, callback);
    Call_PushCell(success);
    Call_PushCell(statusCode);
    Call_PushCell(parsed);    // null (0) when the body was empty or unparseable
    Call_PushString(body);
    Call_PushCell(data);
    Call_Finish();

    if (parsed != null)
        delete parsed;
}

/**
 * Shared boilerplate for the single-resource GET helpers:
 * reads (callback, data) from the given native param offsets and dispatches a GET to the supplied path.
 */
static int GetRequest(Handle plugin, const char[] path, int cbParam, int dataParam)
{
    Function callback = GetNativeFunction(cbParam);
    any      data     = GetNativeCell(dataParam);
    return DoApiRequest(plugin, "GET", path, null, callback, data) ? 1 : 0;
}

/**
 * Appends limit/offset/sort query parameters to a path, skipping any that are unset (limit/offset <= 0, empty sort).
 * Picks '?' or '&' as needed.
 */
static void BuildPagedPath(char[] out, int maxlen, const char[] base, int limit, int offset, const char[] sort)
{
    strcopy(out, maxlen, base);

    char sep[2];
    sep = (StrContains(out, "?") == -1) ? "?" : "&";

    char part[96];
    if (limit > 0)
    {
        FormatEx(part, sizeof(part), "%slimit=%d", sep, limit);
        StrCat(out, maxlen, part);
        sep = "&";
    }
    if (offset > 0)
    {
        FormatEx(part, sizeof(part), "%soffset=%d", sep, offset);
        StrCat(out, maxlen, part);
        sep = "&";
    }
    if (sort[0] != '\0')
    {
        FormatEx(part, sizeof(part), "%ssort=%s", sep, sort);
        StrCat(out, maxlen, part);
        sep = "&";
    }
}

/**
 * Shared boilerplate for the collection GET helpers.
 * Reads the pagination params (limit, offset, sort) and (callback, data) starting at cbParam,
 * in the order: callback, limit, offset, sort, data.
 */
static int CollectionRequest(Handle plugin, const char[] basePath, int cbParam)
{
    Function callback = GetNativeFunction(cbParam);
    int      limit    = GetNativeCell(cbParam + 1);
    int      offset   = GetNativeCell(cbParam + 2);
    char     sort[64];
    GetNativeString(cbParam + 3, sort, sizeof(sort));
    any  data = GetNativeCell(cbParam + 4);

    char path[768];
    BuildPagedPath(path, sizeof(path), basePath, limit, offset, sort);
    return DoApiRequest(plugin, "GET", path, null, callback, data) ? 1 : 0;
}

// Core
public int Native_ApiRequest(Handle plugin, int numParams)
{
    char method[16];
    GetNativeString(1, method, sizeof(method));
    char path[512];
    GetNativeString(2, path, sizeof(path));
    JSON     body     = view_as<JSON>(GetNativeCell(3));
    Function callback = GetNativeFunction(4);
    any      data     = GetNativeCell(5);

    return DoApiRequest(plugin, method, path, body, callback, data) ? 1 : 0;
}

public int Native_GetApiBase(Handle plugin, int numParams)
{
    int maxlen = GetNativeCell(2);
    SetNativeString(1, g_apiUrl, maxlen);
    return strlen(g_apiUrl);
}

public int Native_PostServerStatus(Handle plugin, int numParams)
{
    JSON     body     = view_as<JSON>(GetNativeCell(1));
    Function callback = GetNativeFunction(2);
    any      data     = GetNativeCell(3);
    return DoApiRequest(plugin, "POST", "/servers/status", body, callback, data) ? 1 : 0;
}

public int Native_PostHibernate(Handle plugin, int numParams)
{
    JSON     body     = view_as<JSON>(GetNativeCell(1));
    Function callback = GetNativeFunction(2);
    any      data     = GetNativeCell(3);
    return DoApiRequest(plugin, "POST", "/servers/status/hibernate", body, callback, data) ? 1 : 0;
}

public int Native_GetHealth(Handle plugin, int numParams)
{
    return GetRequest(plugin, "/health", 1, 2);
}

// Live servers / players / maps
public int Native_GetServers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/servers", 1);
}

public int Native_GetServer(Handle plugin, int numParams)
{
    char ip[64];
    GetNativeString(1, ip, sizeof(ip));
    char path[128];
    FormatEx(path, sizeof(path), "/servers/%s", ip);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetPlayers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/players", 1);
}

public int Native_GetOnlinePlayers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/players/online", 1);
}

public int Native_GetPlayer(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[96];
    FormatEx(path, sizeof(path), "/players/%s", steamid);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetMaps(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/maps", 1);
}

public int Native_GetMap(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[160];
    FormatEx(path, sizeof(path), "/maps/%s", mapname);
    return GetRequest(plugin, path, 2, 3);
}

// KZ Global - records
public int Native_GetKzRecords(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/records", 1);
}

public int Native_GetKzRecentRecords(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/records/recent", 1);
}

public int Native_GetKzWorldRecords(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/records/worldrecords", 1);
}

public int Native_GetKzLeaderboard(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[192];
    FormatEx(path, sizeof(path), "/kzglobal/records/leaderboard/%s", mapname);
    return CollectionRequest(plugin, path, 2);
}

public int Native_GetKzRecord(Handle plugin, int numParams)
{
    int  id = GetNativeCell(1);
    char path[96];
    FormatEx(path, sizeof(path), "/kzglobal/records/%d", id);
    return GetRequest(plugin, path, 2, 3);
}

// KZ Global - players
public int Native_GetKzPlayers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/players", 1);
}

public int Native_GetKzPlayer(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[96];
    FormatEx(path, sizeof(path), "/kzglobal/players/%s", steamid);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetKzPlayerRecords(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[128];
    FormatEx(path, sizeof(path), "/kzglobal/players/%s/records", steamid);
    return CollectionRequest(plugin, path, 2);
}

public int Native_GetKzPlayerPBs(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[128];
    FormatEx(path, sizeof(path), "/kzglobal/players/%s/pbs", steamid);
    return CollectionRequest(plugin, path, 2);
}

public int Native_GetKzPlayerCompletions(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[128];
    FormatEx(path, sizeof(path), "/kzglobal/players/%s/completions", steamid);
    return CollectionRequest(plugin, path, 2);
}

// KZ Global - maps
public int Native_GetKzMaps(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/maps", 1);
}

public int Native_GetKzMap(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[192];
    FormatEx(path, sizeof(path), "/kzglobal/maps/%s", mapname);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetKzMapRecords(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[192];
    FormatEx(path, sizeof(path), "/kzglobal/maps/%s/records", mapname);
    return CollectionRequest(plugin, path, 2);
}

public int Native_GetKzMapCourses(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[192];
    FormatEx(path, sizeof(path), "/kzglobal/maps/%s/courses", mapname);
    return CollectionRequest(plugin, path, 2);
}

// KZ Global - servers
public int Native_GetKzServers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/servers", 1);
}

public int Native_GetKzServer(Handle plugin, int numParams)
{
    int  id = GetNativeCell(1);
    char path[96];
    FormatEx(path, sizeof(path), "/kzglobal/servers/%d", id);
    return GetRequest(plugin, path, 2, 3);
}

// KZ Global - bans
public int Native_GetKzBans(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/bans", 1);
}

public int Native_GetKzActiveBans(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzglobal/bans/active", 1);
}

public int Native_GetKzBan(Handle plugin, int numParams)
{
    int  id = GetNativeCell(1);
    char path[96];
    FormatEx(path, sizeof(path), "/kzglobal/bans/%d", id);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetKzPlayerBans(Handle plugin, int numParams)
{
    char steamid[32];
    GetNativeString(1, steamid, sizeof(steamid));
    char path[96];
    FormatEx(path, sizeof(path), "/kzglobal/bans/player/%s", steamid);
    return CollectionRequest(plugin, path, 2);
}

// KZ Local (CS:GO 128/64 tick)
public int Native_GetLocalMaps(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal/maps", 1);
}

public int Native_GetLocalMap(Handle plugin, int numParams)
{
    char mapname[128];
    GetNativeString(1, mapname, sizeof(mapname));
    char path[160];
    FormatEx(path, sizeof(path), "/kzlocal/maps/%s", mapname);
    return GetRequest(plugin, path, 2, 3);
}

public int Native_GetLocalRecords(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal/records", 1);
}

public int Native_GetLocalPlayers(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal/players", 1);
}

// KZ Local CS2
public int Native_GetLocalCS2Maps(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal-cs2/maps", 1);
}

public int Native_GetLocalCS2Records(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal-cs2/records", 1);
}

public int Native_GetLocalCS2Players(Handle plugin, int numParams)
{
    return CollectionRequest(plugin, "/kzlocal-cs2/players", 1);
}

public int Native_GetLocalCS2Stats(Handle plugin, int numParams)
{
    return GetRequest(plugin, "/kzlocal-cs2/stats", 1, 2);
}
