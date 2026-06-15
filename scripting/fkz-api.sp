/**
 * FKZ API
 *
 * Wrapper plugin for FKZ API natives/forwards
 * Status updater with GOKZ integration, sends live player and server data to FKZ API.
 *
 * Dependencies (required):
 *   - sm-ext-json (ProjectSky/sm-ext-json)
 *   - sm-ext-websocket (ProjectSky/sm-ext-websocket)
 *   - gokz-core
 *
 * Dependencies (optional):
 *   - SteamWorks (for VAC status detection)
 *
 * Configuration: addons/sourcemod/configs/fkz-api.cfg
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

#define PLUGIN_VERSION "2.3.0"
#define MODE_NAME_LEN  32

#define FKZ_API_LIBRARY
#include "include/fkz-api.inc"

public Plugin myinfo =
{
    name        = "FKZ-API",
    author      = "jvnipers",
    description = "Exposes FKZ API fetch/send natives and tracks realtime player/server data.",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/FemboyKZ/sm-fkz-api"
};

// globals.sp must come first
#include "fkz-api/globals.sp"

#include "fkz-api/config.sp"
#include "fkz-api/util.sp"
#include "fkz-api/gokz.sp"
#include "fkz-api/payload.sp"
#include "fkz-api/http.sp"
#include "fkz-api/report.sp"
#include "fkz-api/chat.sp"
#include "fkz-api/events.sp"
#include "fkz-api/natives.sp"
