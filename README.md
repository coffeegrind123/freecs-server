# FreeCS Dedicated Server

Deployment scripts for hosting a [FreeCS](https://github.com/eukara/freecs) dedicated server on Linux. FreeCS is an open-source reimplementation of Counter-Strike 1.5 running on the [FTEQW](https://www.fteqw.org) engine.

For the **game client**, see [coffeegrind123/freecs-client](https://github.com/coffeegrind123/freecs-client).

## Prerequisites

- Debian/Ubuntu Linux (x86_64)
- Root access
- ~500MB disk space (includes CS 1.5 data + HL1 base assets)
- ~256MB RAM minimum (QC VM tuned for low-memory servers)
- `megatools` and `p7zip-full` (for downloading HL1 valve data)

## Quick Start

```bash
git clone https://github.com/coffeegrind123/freecs-server.git
cd freecs-server

# Clone FreeCS game data
git clone https://github.com/eukara/freecs.git freecs-data

# Build the deployment package (downloads ~1GB of game data on first run)
./package.sh

# Deploy to your server
scp freecs-server.tar.gz root@your-server:/root/
ssh root@your-server 'cd /root && tar xzf freecs-server.tar.gz && cd freecs-server && ./install.sh'
```

## What package.sh does

1. Downloads [FTEQW](https://github.com/fte-team/fteqw) dedicated server binary (`fteqw-sv64`)
2. Downloads [Rad-Therapy](https://www.frag-net.com/pkgs/package_valve.pk3) (open-source Half-Life base data)
3. Downloads [FreeCS release pk3](https://www.frag-net.com/pkgs/package_cstrike.pk3) (compiled game logic)
4. Downloads CS 1.5 data from archive.org (maps, models, sounds, sprites, textures)
5. Downloads GoldSrc Package from mega.nz and extracts HL1 valve data (models, sounds, sprites, WADs) as `valve-data.pk3`
6. Extracts Rad-Therapy pk3s flat to avoid nested-archive OOM on low-RAM servers
7. Copies FreeCS repo data (progs, configs, bot waypoints, entity patches, etc.)
8. Copies server config, mapcycle, and MOTD
9. Creates a deployable tarball

## What install.sh does

- Creates a `freecs` system user
- Installs files to `/opt/freecs/` (override with `INSTALL_DIR`)
- Creates a systemd service (`freecs.service`)
- Opens port 27500 UDP/TCP in iptables (inserted before any DROP rule)
- Starts the server on `de_dust2`

## Server Configuration

### config/server.cfg

All settings verified against FreeCS source code. Only includes cvars that are actually enforced by the game.

| Setting | Value | Description |
|---------|-------|-------------|
| `maxplayers` / `maxclients` | 16 | Player slots |
| `mp_startmoney` | 800 | Starting money per player |
| `mp_roundtime` | 2.5 | Round duration (minutes) |
| `mp_freezetime` | 3 | Freeze time at round start (seconds) |
| `mp_timelimit` | 30 | Map time limit (minutes) |
| `mp_winlimit` | 0 | Rounds to win (0 = disabled) |
| `mp_flashlight` | 1 | Allow flashlight |
| `sv_friendlyFire` | 0 | Team damage off |
| `fcs_maxmoney` | 16000 | Money cap |
| `fcs_reward_kill` | 300 | Kill reward |
| `bot_minClients` | 0 | Auto-fill bots (0 = none, set higher to populate empty server) |

**Note:** `mp_buytime` and `mp_c4timer` are declared in FreeCS but not enforced in the game code (c4 timer is hardcoded at 45s). `mp_autoteambalance`, `mp_limitteams`, `mp_maxrounds`, `mp_hostagepenalty`, and `mp_tkpunish` are not implemented.

### config/mapcycle.txt

All 26 CS 1.5 maps, sorted with popular maps first.

### config/motd.txt

Message of the day shown to connecting players.

### Master Server

The server reports to `ms.cs16.net:27950` using the DarkPlaces master protocol (`heartbeat DarkPlaces\n`). The `sv_master1` cvar is set on the command line (not in server.cfg) because FTEQW's master cvar initialization happens before config exec.

### Memory Tuning

The systemd service runs with `+pr_ssqc_memsize 32m +pr_maxedicts 4096` to fit on servers with limited RAM (~256MB). For servers with more memory, increase these values or remove them.

## Management

```bash
systemctl status freecs        # Check status
journalctl -u freecs -f        # Follow logs
systemctl restart freecs       # Restart
/opt/freecs/uninstall.sh       # Uninstall
```

## Repository Structure

```
freecs-server/
├── config/
│   ├── server.cfg             # Server configuration
│   ├── mapcycle.txt           # Map rotation (26 CS 1.5 maps)
│   └── motd.txt               # Message of the day
├── freecs-data/               # Clone of eukara/freecs (not tracked)
├── package.sh                 # Downloads dependencies, builds tarball
├── install.sh                 # Installs on target server
├── uninstall.sh               # Removes installation
└── .gitignore
```

## Related Repositories

- [coffeegrind123/freecs-client](https://github.com/coffeegrind123/freecs-client) — Windows/Linux client with patched FTEQW, CI builds, and GitHub releases
- [eukara/freecs](https://github.com/eukara/freecs) — FreeCS game source (QuakeC)
- [fte-team/fteqw](https://github.com/fte-team/fteqw) — FTEQW engine

## FTEQW Engine Patches

The dedicated server binary shipped by `package.sh` is stock FTEQW. For a patched server binary with the `infoResponse` fix (sends full serverinfo instead of empty 17-byte header), build from source with the patch at [coffeegrind123/freecs-client/scripts/patch-fteqw.sh](https://github.com/coffeegrind123/freecs-client/blob/master/scripts/patch-fteqw.sh).

## License

Deployment scripts are provided as-is. FreeCS is ISC licensed by Marco "eukara" Cawthorne. CS 1.5 data and Half-Life base assets are copyrighted by Valve.
