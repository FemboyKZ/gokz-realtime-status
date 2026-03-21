// SourcePawn include for gokz-realtime-status extension natives

#if defined _gokz_rts_included
 #endinput
#endif
#define _gokz_rts_included

/**
 * Informs the extension whether GOKZ is loaded.
 *
 * @param loaded    True if GOKZ is available, false otherwise.
 */
native void RTS_SetGokzLoaded(bool loaded);

/**
 * Sends a player's current GOKZ data to the extension as a JSON string.
 * The extension embeds this directly into the payload without parsing.
 * Use sm-json to build the object with keys: mode, timer_running, paused, time, course, teleports.
 *
 * @param client    Client index.
 * @param gokzJson  JSON-encoded string of GOKZ player data.
 */
native void RTS_SetPlayerGokzData(int client, const char[] gokzJson);

/**
 * Sends server info to the extension.
 *
 * @param hostname    Server hostname string.
 * @param ip          Server IP address string (dotted notation).
 * @param port        Server port number.
 * @param version     Game/server version string.
 * @param tickrate    Server tickrate (e.g. 64, 128).
 * @param secure      VAC status: 1=secure, 0=insecure, -1=unknown.
 */
native void RTS_SetServerInfo(const char[] hostname, const char[] ip, int port, const char[] version, int tickrate, int secure);

public Extension __ext_gokz_rts =
{
	name = "GOKZ Realtime Status",
	file = "gokz-realtime-status.ext",
	autoload = 0,
	required = 0,
};
