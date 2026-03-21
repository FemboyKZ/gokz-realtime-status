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
 * Sends a player's current GOKZ data to the extension.
 *
 * @param client        Client index.
 * @param mode          GOKZ mode (0=Vanilla, 1=SimpleKZ, 2=KZTimer).
 * @param timerRunning  Whether the player's timer is running.
 * @param paused        Whether the player is paused.
 * @param time          Current timer time in seconds.
 * @param course        Current course number.
 * @param teleports     Number of teleports used.
 */
native void RTS_SetPlayerGokzData(int client, int mode, bool timerRunning, bool paused, float time, int course, int teleports);

/**
 * Sends server info to the extension (hostname, IP, port).
 *
 * @param hostname    Server hostname string.
 * @param ip          Server IP address string (dotted notation).
 * @param port        Server port number.
 */
native void RTS_SetServerInfo(const char[] hostname, const char[] ip, int port);

public Extension __ext_gokz_rts =
{
	name = "GOKZ Realtime Status",
	file = "gokz-realtime-status.ext",
	autoload = 0,
	required = 0,
};
