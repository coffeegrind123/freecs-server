#!/bin/bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/freecs}"

err() { echo "ERROR: $*" >&2; exit 1; }
msg() { echo "==> $*"; }

[ "$(id -u)" -eq 0 ] || err "Must be run as root"

msg "Stopping services..."
systemctl stop freecs 2>/dev/null || true
systemctl disable freecs 2>/dev/null || true

msg "Killing any lingering processes..."
pkill -u freecs 2>/dev/null || true
sleep 1
pkill -9 -u freecs 2>/dev/null || true

msg "Removing systemd service..."
rm -f /etc/systemd/system/freecs.service
systemctl daemon-reload

msg "Removing firewall rules..."
iptables -D INPUT -p udp --dport 27500 -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport 27500 -j ACCEPT 2>/dev/null || true

if command -v iptables-save >/dev/null 2>&1; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

msg "Removing install directory..."
rm -rf "$INSTALL_DIR"

msg "Removing freecs user..."
userdel freecs 2>/dev/null || true

msg "Uninstall complete."
