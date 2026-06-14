
# FKZ API SM Plugin

Exposes API endpoint calls as natives and tracks player's/server's realtime status.

This is requires you to have an [FKZ API](https://github.com/FemboyKZ/api) instance.

## Building

### SourceMod 1.11+

1. Copy the contents of `/scripting/` to `/addons/sourcemod/scripting/` wherever SM is installed.
2. Run `compile.exe` (Windows) or `compile.sh` (Linux).
3. Compiled plugin will be in `/scripting/compiled/`

## Natives

Other plugins can read the FKZ API through the natives exposed by this plugin.
Include [`include/fkz-api.inc`](scripting/include/fkz-api.inc) (it pulls in `sm-ext-json`):
