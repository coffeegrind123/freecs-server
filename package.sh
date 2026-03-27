#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PKG_DIR="$BUILD_DIR/freecs-server"
HLDIR="$PKG_DIR/Half-Life"

FTEQW_URL="https://github.com/fte-team/fteqw/releases/download/2025-09-27/fteqw-linux64-c781d13.zip"
VALVE_PK3_URL="https://www.frag-net.com/pkgs/package_valve.pk3"
CSTRIKE_PK3_URL="https://www.frag-net.com/pkgs/package_cstrike.pk3"
CS15_URL="https://archive.org/download/counter-strike-1.5/csv15full_cstrike.zip"
GOLDSRC_URL="https://mega.nz/file/sVwBhZKK#4WfFaQUi3gSFfK0ltdqgzT36gPbUtou3tb3GUWUSSio"

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

download "$FTEQW_URL" "$DL_DIR/fteqw-linux64.zip"
download "$VALVE_PK3_URL" "$DL_DIR/package_valve.pk3"
download "$CSTRIKE_PK3_URL" "$DL_DIR/package_cstrike.pk3"
download "$CS15_URL" "$DL_DIR/cs15data.zip"

if [ ! -f "$DL_DIR/valve-data.pk3" ]; then
    msg "Downloading HL1 valve data (GoldSrc Package)..."
    megadl "$GOLDSRC_URL" --path "$DL_DIR/"
    GSRC_7Z=$(find "$DL_DIR" -name "GoldSrc*" -print -quit)
    [ -n "$GSRC_7Z" ] || err "GoldSrc download failed"
    7z x -o"$BUILD_DIR/tmp/goldsrc" "$GSRC_7Z" "Half-Life WON/valve/models/" "Half-Life WON/valve/sound/" "Half-Life WON/valve/sprites/" "Half-Life WON/valve/*.wad" -y
    (cd "$BUILD_DIR/tmp/goldsrc/Half-Life WON/valve" && zip -qr "$DL_DIR/valve-data.pk3" models/ sound/ sprites/ *.wad)
    rm -rf "$BUILD_DIR/tmp/goldsrc" "$GSRC_7Z"
fi

msg "Setting up directory structure..."
mkdir -p "$HLDIR/valve" "$HLDIR/cstrike"

msg "Extracting FTEQW dedicated server..."
TMPEXT="$BUILD_DIR/tmp/fteqw_extract"
mkdir -p "$TMPEXT"
unzip -qo "$DL_DIR/fteqw-linux64.zip" -d "$TMPEXT"
SVBIN=$(find "$TMPEXT" -name "fteqw-sv64" -print -quit)
[ -n "$SVBIN" ] || err "fteqw-sv64 not found in zip"
cp -f "$SVBIN" "$HLDIR/fteqw-sv64"
chmod +x "$HLDIR/fteqw-sv64"
rm -rf "$TMPEXT"

msg "Extracting valve pk3 (flat, avoids nested pk3 OOM on low-RAM servers)..."
TMPEXT="$BUILD_DIR/tmp/valve_extract"
mkdir -p "$TMPEXT"
unzip -qo "$DL_DIR/package_valve.pk3" -d "$TMPEXT"
mv "$TMPEXT"/*.pk3 "$TMPEXT"/*.dat "$HLDIR/valve/"
rm -rf "$TMPEXT"

msg "Copying HL1 valve data..."
cp -f "$DL_DIR/valve-data.pk3" "$HLDIR/valve/valve-data.pk3"

cat > "$HLDIR/valve/liblist.gam" <<'LIBLIST'
game "Half-Life"
startmap "c0a0"
trainmap "t0a0"
mpentity "info_player_deathmatch"
gamedll "dlls/hl.so"
gamedll_linux "dlls/hl.so"
type "singleplayer_only"
cldll "1"
LIBLIST

msg "Extracting cstrike pk3 (flat)..."
TMPEXT="$BUILD_DIR/tmp/cstrike_extract"
mkdir -p "$TMPEXT"
unzip -qo "$DL_DIR/package_cstrike.pk3" -d "$TMPEXT"
mv "$TMPEXT"/*.pk3 "$TMPEXT"/*.dat "$HLDIR/cstrike/" 2>/dev/null || true
rm -rf "$TMPEXT"

msg "Extracting CS 1.5 data from archive..."
cp -f "$DL_DIR/cs15data.zip" "$HLDIR/cstrike/pak0.pk3"

msg "Copying FreeCS repo data..."
for item in cfg data decls fonts gfx maps particles progs resource scripts \
            progs.dat csprogs.dat hud.dat quake.rc icon.tga \
            default_aliases.cfg default_cstrike.cfg default_cvar.cfg; do
    if [ -e "$SCRIPT_DIR/freecs-data/$item" ]; then
        cp -a "$SCRIPT_DIR/freecs-data/$item" "$HLDIR/cstrike/"
    fi
done

msg "Copying server config..."
cp -f "$SCRIPT_DIR/config/server.cfg" "$HLDIR/cstrike/server.cfg"
cp -f "$SCRIPT_DIR/config/mapcycle.txt" "$HLDIR/cstrike/mapcycle.txt"
cp -f "$SCRIPT_DIR/config/motd.txt" "$HLDIR/cstrike/motd.txt"

msg "Copying scripts..."
cp -f "$SCRIPT_DIR/install.sh" "$PKG_DIR/install.sh"
cp -f "$SCRIPT_DIR/uninstall.sh" "$PKG_DIR/uninstall.sh"
chmod +x "$PKG_DIR/install.sh" "$PKG_DIR/uninstall.sh"

msg "Creating freecs-server.tar.gz..."
tar czf "$SCRIPT_DIR/freecs-server.tar.gz" -C "$BUILD_DIR" freecs-server/

SIZE=$(du -sh "$SCRIPT_DIR/freecs-server.tar.gz" | cut -f1)
msg "Done! Package: freecs-server.tar.gz ($SIZE)"
msg ""
msg "Deploy:"
msg "  scp freecs-server.tar.gz root@your-vps:/tmp/"
msg "  ssh root@your-vps 'cd /tmp && tar xzf freecs-server.tar.gz && cd freecs-server && ./install.sh'"
