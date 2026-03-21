
# GOKZ Realtime status

## Building Extension

### AMBuild

```py
mkdir build && cd build

python ../configure.py --sm-path ../sourcemod --mms-path ../metamod-source --targets x86

ambuild
```

## Building Bridge plugin

### SourceMod 1.11+

1. Copy the contents of `/scripting/` to ``/addons/sourcemod/scripting/` wherever SM is installed.
2. Run `compile.exe` (Windows) or `compile.sh` (Linux).
3. Compiled plugin will be in `/scripting/compiled/`

## Configuration

TBA
