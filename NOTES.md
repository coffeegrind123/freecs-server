## Session Summary

### What We Built
A complete FreeCS (Counter-Strike 1.5) dedicated server and client distribution, from scratch.

---

### Repositories Created

**[coffeegrind123/freecs-server](https://github.com/coffeegrind123/freecs-server)** — Dedicated server deployment
- `package.sh` builds a patched FTEQW server from source, downloads all game data, compiles QC rules, packages as tarball
- `install.sh` / `uninstall.sh` for systemd deployment
- Server config, mapcycle (26 maps), MOTD
- Auto-restart every 3 hours via `RuntimeMaxSec`

**[coffeegrind123/freecs-client](https://github.com/coffeegrind123/freecs-client)** — Fork of eukara/freecs with CI
- GitHub Actions builds patched FTEQW client (win64 + linux64), packages with all game data
- Automatic GitHub releases on every push
- Download page at `http://freecs.cs16.net:27500` with live server list

---

### FTEQW Engine Bugs Found & Fixed (5 patches in `scripts/patch-fteqw.sh`)

1. **Empty `infoResponse`** (`sv_main.c`) — `SV_GeneratePublicServerinfo` wrote data but `resp` pointer was never advanced. All dpmaster queries got a 17-byte empty response instead of 836 bytes of serverinfo. One-line fix: `resp += strlen(resp)`.

2. **`getserversResponse` parsing** (`net_master.c`) — Bit-position math had wrong operator precedence: `(c+18-1)<<3` instead of `c+((18-1)<<3)`. Parser read byte 49 instead of byte 21, silently dropping all servers from small master responses. Worked by accident with large server lists (4+ servers).

3. **QW master flooding** (`net_master.c`) — `net_qwmasterextra4/5` are `CVAR_NOSAVE` (can't override at runtime) and returned hundreds of unrelated QW servers, drowning the server browser probe queue.

4. **dpmaster extras + LAN broadcasts + ice broker** (`net_master.c`, `net_wins.c`) — `master.frag-net.com`, `dpmaster.deathmask.net`, `dpmaster.tchr.no` returned servers for all games. 6 broadcast masters waited for network timeouts. `net_ice_broker` made a TLS connection to frag-net on every refresh. All blanked — refresh went from ~20s to ~2s.

5. **Update dialog** (`m_download.c`, `fs.c`) — `pkg_autoupdate` default changed from `-1` (prompt) to `0` (off). Manifest URL blanked to prevent `SRCFL_MANIFEST` flag from bypassing the setting.

---

### FreeCS QuakeC Fix

**Map rotation** (`counterstrike.qc`) — Upstream FreeCS sets `STATE_OVER` when timelimit/winlimit expires but never triggers a map change. Added `g_cs_gameOverTime` timer that waits 5 seconds then calls `localcmd("nextmap\n")`, using Nuclide's built-in mapcycle alias chain.

---

### Key Discoveries & Debugging

**Server not appearing in master** — The master server (hlmaster-bun) received the heartbeat but FTEQW's `infoResponse` was empty. Master-side workaround: QW status fallback probe. Engine-side fix: the `resp` pointer bug above.

**Client couldn't find server** — The `getserversResponse` parsing bug dropped our server because the response was only 36 bytes (1 server). The parser started reading at byte 49 (past end of packet).

**Nuclide API version mismatch** — Compiling full QC against current Nuclide broke weapon animations, movement physics, slope handling, and team selection. The pre-compiled progs.dat (March 2024) was built against an older Nuclide with different animation and physics APIs. Final solution: compile only `progs/counterstrike.dat` (rules) for our timelimit fix, keep pre-compiled `progs.dat`/`csprogs.dat` from the official pk3.

**Deathmatch mode** — Nuclide's `Game_DefaultRules()` returns `"deathmatch"` when `g_gametype` isn't set. Fixed with `set g_gametype counterstrike` in server.cfg.

**Missing game assets** — CS 1.5 data (maps/models/sounds) + HL1 valve data (sprites/gibs/debris/wads from GoldSrc Package on mega.nz) + Rad-Therapy (open-source HL base) all needed for complete gameplay.

**Missing key bindings** — `default_controls.cfg`, `default_video.cfg`, `default_valve.cfg` come from the Nuclide SDK `base/` dir and valve game respectively, not from FreeCS. CI clones both to include them.

---

### What's Deployed on VPS (88.218.206.151)

| Service | Port | Description |
|---------|------|-------------|
| FreeCS server | 27500 UDP | FTEQW dedicated, counterstrike mode, 16 slots |
| Download page | 27500 TCP | Caddy serving static HTML with GitHub API releases + server list |
| Master server | 27950 UDP | dpmaster heartbeat (hlmaster-bun) |

### Final Architecture

```
Client (fteqw64.exe, patched)
  → queries ms.cs16.net:27950 (dpmaster)
  → gets server list
  → probes 88.218.206.151:27500
  → connects and plays

Server (fteqw-sv64, patched)
  → sends heartbeat to ms.cs16.net:27950
  → runs counterstrike rules with mapcycle
  → auto-restarts every 3 hours
```
