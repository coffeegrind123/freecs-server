# FreeCS Dedicated Server

Deployment scripts for hosting a [FreeCS (Tactical-Retreat)](https://github.com/eukara/freecs) dedicated server on Linux. FreeCS is an open-source reimplementation of Counter-Strike 1.5 running on the [FTEQW](https://www.fteqw.org) engine.

## Prerequisites

- Debian/Ubuntu Linux (x86_64)
- Root access
- ~200MB disk space
- ~256MB RAM minimum (QC VM tuned for low-memory servers)

## Quick Start

```bash
git clone https://github.com/coffeegrind123/freecs-server.git
cd freecs-server

# 1. Clone FreeCS game data
git clone https://github.com/eukara/freecs.git freecs-data

# 2. Build the deployment package
./package.sh

# 3. Copy to your server and install
scp freecs-server.tar.gz root@your-server:/root/
ssh root@your-server 'cd /root && tar xzf freecs-server.tar.gz && cd freecs-server && ./install.sh'
```

## What package.sh does

1. Downloads [FTEQW](https://github.com/fte-team/fteqw) dedicated server binary (`fteqw-sv64`)
2. Downloads [Rad-Therapy](https://www.frag-net.com/pkgs/package_valve.pk3) (open-source Half-Life base data)
3. Downloads [FreeCS release pk3](https://www.frag-net.com/pkgs/package_cstrike.pk3) (game logic, assets)
4. Downloads CS 1.5 map data from archive.org (BSP files only)
5. Extracts pk3s flat to avoid nested-archive memory issues on low-RAM servers
6. Copies FreeCS repo data (progs, configs, bot waypoints, etc.)
7. Creates a deployable tarball

## What install.sh does

- Creates a `freecs` system user
- Installs files to `/opt/freecs/` (override with `INSTALL_DIR`)
- Creates a systemd service (`freecs.service`)
- Opens port 27500 UDP/TCP in iptables (inserted before any DROP rule)
- Starts the server on `de_dust2`

## Configuration

Edit `config/server.cfg` before packaging:

```
set hostname "FreeCS Server"
set maxplayers 32
set sv_public 1
set sv_master1 "ms.cs16.net:27950"
set com_protocolname "FTE-Quake"
set sv_port 27500
```

Game-specific cvars (mp_startmoney, mp_freezetime, etc.) are set in FreeCS's own `default_cstrike.cfg`.

### Master Server

The server reports to dpmaster-compatible master servers using the DarkPlaces master protocol (`heartbeat DarkPlaces\n`). The default master is `ms.cs16.net:27950`. Add additional masters with `sv_master2`, `sv_master3`, etc.

### Memory Tuning

The systemd service runs with `+pr_ssqc_memsize 32m +pr_maxedicts 2048` to fit on servers with limited RAM. For servers with more memory, increase these values or remove them to use defaults.

## Management

```bash
systemctl status freecs
journalctl -u freecs -f
systemctl restart freecs
```

## Uninstall

```bash
/opt/freecs/uninstall.sh
```

This stops the service, removes the systemd unit, cleans up firewall rules, and deletes `/opt/freecs/`.

## Structure

```
freecs-server/
├── config/
│   └── server.cfg          # Server configuration
├── freecs-data/            # Clone of github.com/eukara/freecs (not included)
├── package.sh              # Builds deployment tarball
├── install.sh              # Installs on target server
└── uninstall.sh            # Removes installation
```

## License

Deployment scripts are provided as-is. FreeCS itself is ISC licensed by Marco "eukara" Cawthorne. CS 1.5 map data is copyrighted by Valve.
