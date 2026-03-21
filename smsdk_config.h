#ifndef _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_

/**
 * @file smsdk_config.h
 * @brief Contains macros for configuring basic extension information.
 */

/* Basic information exposed publicly */
#define SMEXT_CONF_NAME         "GOKZ Realtime Status"
#define SMEXT_CONF_DESCRIPTION  "Reports server/player/GOKZ data to a remote API"
#define SMEXT_CONF_VERSION      "1.0.0"
#define SMEXT_CONF_AUTHOR       "jvnipers"
#define SMEXT_CONF_URL          "https://github.com/FemboyKZ/gokz-realtime-status"
#define SMEXT_CONF_LOGTAG       "gokz-rts"
#define SMEXT_CONF_LICENSE      "AGPL"
#define SMEXT_CONF_DATESTRING   __DATE__

#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;
#define SMEXT_CONF_METAMOD

/** Enable interfaces we need */
#define SMEXT_ENABLE_FORWARDSYS
#define SMEXT_ENABLE_PLAYERHELPERS
#define SMEXT_ENABLE_GAMEHELPERS
#define SMEXT_ENABLE_TIMERSYS
#define SMEXT_ENABLE_THREADER
#define SMEXT_ENABLE_PLUGINSYS

#endif // _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
