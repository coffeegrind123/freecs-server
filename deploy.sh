#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
else
    echo "ERROR: .env not found. Copy .env.example to .env and fill in values." >&2
    exit 1
fi

HOST="${DEPLOY_HOST:?Set DEPLOY_HOST in .env}"
SSH_USER="${DEPLOY_USER:-root}"
SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/vps_nopw}"
INSTALL_DIR="${DEPLOY_INSTALL_DIR:-/opt/freecs}"
SERVICE="freecs"

ssh_cmd() { ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "${SSH_USER}@${HOST}" "$@"; }
scp_cmd() { scp -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$@"; }

err() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo "==> $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build, package, and deploy FreeCS server to VPS.

Options:
  --full        Full setup: build + package + upload + install
  --update      Quick update: build QC only, deploy progs.dat (default)
  --package     Build full server tarball (no deploy)
  --qc          Compile QC only, deploy progs.dat
  --restart     Just restart the remote service
  --status      Show remote service status
  --logs        Tail remote service logs
  --help        Show this help

Environment is loaded from .env (see .env.example).
EOF
    exit 0
}

health_check() {
    msg "Waiting for service..."
    for i in 1 2 3 4 5; do
        sleep 2
        if ssh_cmd "systemctl is-active --quiet $SERVICE" 2>/dev/null; then
            msg "Service healthy"
            return 0
        fi
        echo "  Attempt $i/5..."
    done
    echo "WARN: Service may not have started cleanly"
    ssh_cmd "journalctl -u $SERVICE --no-pager -n 10"
}

build_qc() {
    msg "Building QuakeC..."
    bash "$SCRIPT_DIR/package.sh" 2>&1 | grep "^==>"
    msg "Build complete"
}

deploy_progs() {
    msg "Deploying progs.dat..."
    local nuclide_dir="$SCRIPT_DIR/build/nuclide"
    local progs="$nuclide_dir/cstrike/progs.dat"

    [ -f "$progs" ] || err "progs.dat not found — run build first"

    scp_cmd "$progs" "${SSH_USER}@${HOST}:${INSTALL_DIR}/Half-Life/cstrike/progs.dat"
    ssh_cmd "chown freecs:freecs ${INSTALL_DIR}/Half-Life/cstrike/progs.dat"
    msg "progs.dat deployed"
}

deploy_configs() {
    msg "Deploying configs..."
    for cfg in server.cfg mapcycle.txt motd.txt; do
        if [ -f "$SCRIPT_DIR/config/$cfg" ]; then
            scp_cmd "$SCRIPT_DIR/config/$cfg" "${SSH_USER}@${HOST}:${INSTALL_DIR}/Half-Life/cstrike/$cfg"
        fi
    done
    ssh_cmd "chown -R freecs:freecs ${INSTALL_DIR}/Half-Life/cstrike/"
    msg "Configs deployed"
}

deploy_web() {
    if [ -d "$SCRIPT_DIR/web" ]; then
        msg "Deploying web page..."
        ssh_cmd "mkdir -p ${INSTALL_DIR}/web"
        scp_cmd "$SCRIPT_DIR/web/index.html" "${SSH_USER}@${HOST}:${INSTALL_DIR}/web/index.html"
        ssh_cmd "chown -R freecs:freecs ${INSTALL_DIR}/web"
    fi
}

do_update() {
    build_qc
    deploy_progs
    deploy_configs
    deploy_web
    msg "Restarting ${SERVICE}..."
    ssh_cmd "systemctl restart ${SERVICE}"
    health_check
}

do_full() {
    msg "Full build + deploy..."

    msg "Building server package..."
    bash "$SCRIPT_DIR/package.sh"

    local tarball="$SCRIPT_DIR/freecs-server.tar.gz"
    [ -f "$tarball" ] || err "freecs-server.tar.gz not found"

    msg "Uploading package to ${HOST}..."
    scp_cmd "$tarball" "${SSH_USER}@${HOST}:/root/freecs-server.tar.gz"

    msg "Installing on remote..."
    ssh_cmd "cd /root && tar xzf freecs-server.tar.gz && cd freecs-server && bash install.sh 2>&1 | tail -15"

    deploy_web

    msg "Cleaning up remote tarball..."
    ssh_cmd "rm -f /root/freecs-server.tar.gz"

    health_check
    msg "Full deploy complete"
}

do_package() {
    msg "Building server package..."
    bash "$SCRIPT_DIR/package.sh"
    msg "Package ready: $SCRIPT_DIR/freecs-server.tar.gz"
}

do_qc() {
    msg "Quick QC compile + deploy..."

    # Use client repo's build script if available
    local client_dir="$SCRIPT_DIR/build/freecs-client"
    if [ -d "$client_dir" ] && [ -f "$client_dir/scripts/build-client.sh" ]; then
        bash "$client_dir/scripts/build-client.sh" --qc-only
        local progs="$client_dir/progs.dat"
    else
        build_qc
        local progs="$SCRIPT_DIR/build/nuclide/cstrike/progs.dat"
    fi

    [ -f "$progs" ] || err "progs.dat not found"
    scp_cmd "$progs" "${SSH_USER}@${HOST}:${INSTALL_DIR}/Half-Life/cstrike/progs.dat"
    ssh_cmd "chown freecs:freecs ${INSTALL_DIR}/Half-Life/cstrike/progs.dat"

    deploy_configs
    deploy_web

    msg "Restarting ${SERVICE}..."
    ssh_cmd "systemctl restart ${SERVICE}"
    health_check
}

# --- Main ---
MODE="--update"

for arg in "$@"; do
    case "$arg" in
        --full)    MODE="--full" ;;
        --update)  MODE="--update" ;;
        --package) MODE="--package" ;;
        --qc)      MODE="--qc" ;;
        --restart)  MODE="--restart" ;;
        --status)  MODE="--status" ;;
        --logs)    MODE="--logs" ;;
        --help|-h) usage ;;
        *) err "Unknown option: $arg" ;;
    esac
done

msg "Deploying to ${HOST} (${MODE})"

case "$MODE" in
    --full)    do_full ;;
    --update)  do_update ;;
    --package) do_package ;;
    --qc)      do_qc ;;
    --restart)
        ssh_cmd "systemctl restart ${SERVICE}"
        health_check
        ;;
    --status)
        ssh_cmd "systemctl status ${SERVICE} --no-pager | head -15; echo '---'; free -h"
        ;;
    --logs)
        ssh_cmd "journalctl -u ${SERVICE} --no-pager -n 30"
        ;;
esac
