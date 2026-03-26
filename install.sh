#!/bin/bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/freecs}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

err() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo "==> $*"; }

[ "$(id -u)" -eq 0 ] || err "Must be run as root"
[ -d "$SCRIPT_DIR/Half-Life" ] || err "Half-Life/ directory not found — run from extracted package"

if [ -d "$INSTALL_DIR" ]; then
    err "$INSTALL_DIR already exists. Uninstall first or set INSTALL_DIR to a different path."
fi

for port in 27500; do
    if ss -tlnp | grep -q ":${port} " || ss -ulnp | grep -q ":${port} "; then
        err "Port $port is already in use"
    fi
done

msg "Installing runtime dependencies..."
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y --no-install-recommends lib32gcc-s1 lib32stdc++6 pax-utils || true

msg "Creating freecs user..."
if ! id freecs >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" freecs
fi

msg "Installing files to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -a "$SCRIPT_DIR/Half-Life" "$INSTALL_DIR/"

if command -v scanelf >/dev/null 2>&1; then
    msg "Clearing executable stack flags..."
    find "$INSTALL_DIR/Half-Life" -name "*.so" -exec scanelf -Xe {} \; 2>/dev/null || true
fi

chmod +x "$INSTALL_DIR/Half-Life/fteqw-sv64"
chown -R freecs:freecs "$INSTALL_DIR"

msg "Creating systemd service..."
cat > /etc/systemd/system/freecs.service <<EOF
[Unit]
Description=FreeCS (Tactical-Retreat) Dedicated Server
After=network.target

[Service]
Type=simple
User=freecs
Environment=HOME=$INSTALL_DIR/Half-Life
WorkingDirectory=$INSTALL_DIR/Half-Life
ExecStart=$INSTALL_DIR/Half-Life/fteqw-sv64 -game cstrike +pr_ssqc_memsize 32m +pr_maxedicts 2048 +sv_master1 "ms.cs16.net:27950" +map de_dust2 +exec server.cfg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

msg "Writing manifest..."
MANIFEST="$INSTALL_DIR/.manifest"
{
    echo "# freecs-server install manifest"
    echo "# Generated: $(date -Iseconds)"
    echo "user:freecs"
    echo "service:/etc/systemd/system/freecs.service"
    echo "dir:$INSTALL_DIR"
} > "$MANIFEST"

msg "Configuring firewall..."
add_iptables_rule() {
    if ! iptables -C INPUT $* 2>/dev/null; then
        local drop_pos
        drop_pos=$(iptables -L INPUT --line-numbers -n | grep -i "drop" | tail -1 | awk '{print $1}')
        if [ -n "$drop_pos" ]; then
            iptables -I INPUT "$drop_pos" $*
        else
            iptables -A INPUT $*
        fi
    fi
}

add_iptables_rule -p udp --dport 27500 -j ACCEPT
add_iptables_rule -p tcp --dport 27500 -j ACCEPT

if command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

cp -f "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/uninstall.sh"

msg "Starting service..."
systemctl daemon-reload
systemctl enable --now freecs

msg ""
msg "Installation complete!"
msg "  Install dir:  $INSTALL_DIR"
msg "  Game server:  port 27500 (UDP/TCP)"
msg ""
msg "Commands:"
msg "  systemctl status freecs"
msg "  journalctl -u freecs -f"
msg "  $INSTALL_DIR/uninstall.sh"
