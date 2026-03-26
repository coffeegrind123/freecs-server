#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PKG_DIR="$BUILD_DIR/freecs-client"
HLDIR="$PKG_DIR/Half-Life"

FTEQW_URL="https://github.com/fte-team/fteqw/releases/download/2025-09-27/fteqw-win64-c781d13.zip"
VALVE_PK3_URL="https://www.frag-net.com/pkgs/package_valve.pk3"
CSTRIKE_PK3_URL="https://www.frag-net.com/pkgs/package_cstrike.pk3"
CS15_URL="https://archive.org/download/counter-strike-1.5/csv15full_cstrike.zip"

err() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo "==> $*"; }

cleanup() {
    rm -rf "$BUILD_DIR/tmp"
}
trap cleanup EXIT

download() {
    local url="$1" dest="$2"
    if [ -f "$dest" ]; then
        msg "Already downloaded $(basename "$dest"), skipping..."
        return
    fi
    msg "Downloading $(basename "$dest")..."
    curl -fsSL "$url" -o "$dest" || err "Failed to download $url"
}

mkdir -p "$BUILD_DIR/tmp" "$PKG_DIR"

DL_DIR="$BUILD_DIR/downloads"
mkdir -p "$DL_DIR"

download "$FTEQW_URL" "$DL_DIR/fteqw-win64.zip"
download "$VALVE_PK3_URL" "$DL_DIR/package_valve.pk3"
download "$CSTRIKE_PK3_URL" "$DL_DIR/package_cstrike.pk3"
download "$CS15_URL" "$DL_DIR/cs15data.zip"

msg "Setting up directory structure..."
mkdir -p "$HLDIR/valve" "$HLDIR/cstrike"

msg "Copying patched FTEQW Windows client..."
PATCHED_EXE="$SCRIPT_DIR/bin/fteqw64.exe"
if [ -f "$PATCHED_EXE" ]; then
    cp -f "$PATCHED_EXE" "$HLDIR/fteqw64.exe"
else
    msg "No patched binary at bin/fteqw64.exe, extracting stock from zip..."
    TMPEXT="$BUILD_DIR/tmp/fteqw_extract"
    mkdir -p "$TMPEXT"
    unzip -qo "$DL_DIR/fteqw-win64.zip" -d "$TMPEXT"
    cp -f "$TMPEXT/fteqw64.exe" "$HLDIR/fteqw64.exe"
    rm -rf "$TMPEXT"
fi

msg "Copying game data..."
cp -f "$DL_DIR/package_valve.pk3" "$HLDIR/valve/package_valve.pk3"
cp -f "$DL_DIR/package_cstrike.pk3" "$HLDIR/cstrike/package_cstrike.pk3"
cp -f "$DL_DIR/cs15data.zip" "$HLDIR/cstrike/pak0.pk3"

cat > "$HLDIR/valve/liblist.gam" <<'LIBLIST'
game "Half-Life"
startmap "c0a0"
trainmap "t0a0"
mpentity "info_player_deathmatch"
gamedll "dlls/hl.dll"
gamedll_linux "dlls/hl.so"
type "singleplayer_only"
cldll "1"
LIBLIST

msg "Copying FreeCS repo data..."
for item in cfg data decls fonts gfx maps particles progs resource scripts \
            progs.dat csprogs.dat hud.dat quake.rc icon.tga \
            default_aliases.cfg default_cstrike.cfg default_cvar.cfg; do
    if [ -e "$SCRIPT_DIR/freecs-data/$item" ]; then
        cp -a "$SCRIPT_DIR/freecs-data/$item" "$HLDIR/cstrike/"
    fi
done

msg "Creating client config..."
cat > "$HLDIR/cstrike/autoexec.cfg" <<'CFG'
set net_master1 "ms.cs16.net:27950"
set net_masterextra1 ""
set net_masterextra2 ""
set net_masterextra3 ""
set com_protocolname "FTE-Quake"
CFG

msg "Creating launch script..."
cat > "$HLDIR/Play FreeCS.bat" <<'BAT'
@echo off
start "" "%~dp0fteqw64.exe" -game cstrike +sv_master1 "ms.cs16.net:27950"
BAT

cat > "$HLDIR/Play FreeCS (Windowed).bat" <<'BAT'
@echo off
start "" "%~dp0fteqw64.exe" -game cstrike -window +sv_master1 "ms.cs16.net:27950"
BAT

msg "Creating freecs-client-win64.zip..."
(cd "$PKG_DIR" && zip -qr "$SCRIPT_DIR/freecs-client-win64.zip" Half-Life/)

SIZE=$(du -sh "$SCRIPT_DIR/freecs-client-win64.zip" | cut -f1)
msg "Done! Package: freecs-client-win64.zip ($SIZE)"
msg ""
msg "Extract and run 'Play FreeCS.bat' to play."
