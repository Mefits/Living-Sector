# Godot Client Reference — Space Simulator

## Connection

- **REST API**: `http://localhost:<PORT>/api/*`
- **WebSocket**: `ws://localhost:<PORT>/simulation/websocket`
- **Port discovery**: the sim binds an OS-assigned free port by default
  (no collisions with your dev 4000/3000/etc.) and writes it to
  `<saves_dir>/port.txt` once the endpoint is listening. Godot reads
  that file on startup — see the `_wait_for_port` example below. Pin a
  specific port with the `PORT` env var if you want to curl from a
  terminal.
- No authentication (POC phase)

## Embedding the Sim in the Godot App

The sim ships as a self-contained Elixir release (`_build/prod/rel/simulator/`,
~40 MB, ERTS bundled — no host Elixir or Erlang needed on the user's
machine). The packaging model: Godot is the parent process, spawns the
release as a child, waits for it to be ready, connects over localhost.

### Layout

A packaged desktop app looks like:

```
SpaceSim.app/                       # (or .exe folder on Windows)
├── Godot binary + PCK
└── sim/                            # the release, copied whole
    ├── bin/simulator               # shell script entry point
    ├── erts-<ver>/
    ├── lib/
    ├── priv/                       # JSON world data, static assets
    └── releases/
```

The release is platform-specific (macOS build runs on macOS, etc.), so
the CI matrix builds one per target.

### Building on Windows

`mix release` must be run **on the target platform** — BEAM's ERTS
is platform-specific and can't cross-compile. On a Windows dev box:

```powershell
# Prereqs: Elixir + Erlang installed (chocolatey or Scoop both work)
mix deps.get --only prod
$env:MIX_ENV="prod"; mix release --overwrite
```

Output: `_build\prod\rel\simulator\bin\simulator.bat`. Godot's
[server_manager.gd](../client/scripts/autoload/server_manager.gd)
already branches on `OS.get_name() == "Windows"` to launch the
`.bat` variant without a shell wrapper.

All simulator code is cross-platform: `vm.args` flags work on
Windows (`-noinput`, `+S 16:16`), the sidecar `port.txt` / `beam.pid`
files land in the DB directory as on macOS, the file-based Logger
works identically. `Simulator.ParentWatcher` detects the platform
at runtime and uses `tasklist /FI "PID eq N"` on Windows instead of
`kill -0`.

### Launching the Sim from Godot

On app startup, before showing the main menu:

```gdscript
var sim_pid: int = -1
var sim_port: int = -1

func _ready():
    sim_pid = _spawn_sim()
    sim_port = await _wait_for_port()
    await _wait_for_health(sim_port)

func _spawn_sim() -> int:
    # Path relative to the Godot executable directory.
    var sim_binary = OS.get_executable_path().get_base_dir().path_join("sim/bin/simulator")

    var db_path = OS.get_user_data_dir().path_join("sim.db")
    DirAccess.make_dir_recursive_absolute(db_path.get_base_dir())

    # Pass config via env; no argv needed. We deliberately DO NOT set
    # PORT — leaving it unset tells the sim to ask the OS for any free
    # port, which removes any chance of colliding with the user's
    # other dev services (Phoenix apps on 4000, Rails on 3000, etc.).
    # The sim writes the actual bound port to <saves_dir>/port.txt.
    var env = {
        "DATABASE_PATH": db_path,
        "PHX_HOST": "localhost",
        "BIND_IP": "127.0.0.1",
        # Hooks up Simulator.ParentWatcher so the sim shuts itself down
        # when Godot dies (via stdin-EOF and/or PID-poll).
        "PARENT_PID": str(OS.get_process_id())
    }

    # OS.create_process inherits the current env, so prepend ours.
    var cmd = sim_binary
    var args = ["start"]
    return OS.create_process(cmd, args)

# Poll for the port.txt sidecar the sim writes once its endpoint is
# listening. Takes ~1s on a warm boot, a few seconds on cold first-
# boot migration.
func _wait_for_port() -> int:
    var port_file = OS.get_user_data_dir().path_join("port.txt")

    for i in 120:  # ~30s budget
        if FileAccess.file_exists(port_file):
            var raw = FileAccess.get_file_as_string(port_file).strip_edges()
            if raw.is_valid_int():
                return raw.to_int()
        await get_tree().create_timer(0.25).timeout

    push_error("Sim never wrote port.txt")
    return -1

func _wait_for_health(port: int) -> void:
    for i in 60:
        var req = HTTPRequest.new()
        add_child(req)
        req.request("http://localhost:%d/api/health" % port)
        var res = await req.request_completed
        if res[1] == 200:
            return
        await get_tree().create_timer(0.25).timeout
    push_error("Sim failed to boot within 15s")
```

The first-boot hook inside the release takes care of migrations + seed
from the bundled JSON — no setup scripts needed. Subsequent launches
boot against the existing DB in ~1s.

**Override if you need a fixed port** (e.g., curling from a terminal
for debugging): set `PORT=4000` (or any number) in the env dictionary.
The sim honors it and still writes `port.txt` with that same number so
the Godot read path doesn't need to branch.

### Automatic Shutdown if Godot Dies

The sim has a built-in `Simulator.ParentWatcher` that activates only
when you pass `PARENT_PID`. It runs **two parallel death signals** so
you never leak an orphaned BEAM:

1. **stdin-EOF** — when Godot's stdout pipe closes (because Godot
   exited, crashed, or was force-killed), our fd 0 sees EOF
   immediately. The sim logs "stdin EOF — parent closed its pipe"
   and calls `System.stop(0)`.
2. **PID-alive poll** — every second the sim checks `kill -0 <PARENT_PID>`.
   If the PID is gone, it logs "parent PID X is gone" and shuts
   down. Catches scenarios where stdin isn't piped (rare, but not
   impossible across platforms).

Either path triggers a graceful shutdown: the `PersistenceManager`
flushes, SQLite WAL closes cleanly, Endpoint stops listening, and the
release exits with code 0.

You don't have to do anything on the client side beyond setting
`PARENT_PID` in the env. It's the belt; the explicit `SIGTERM` below
is the braces.

### Shutting Down

Clean death coupling so the user never has an orphaned BEAM:

```gdscript
func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _shutdown_sim()
        get_tree().quit()

func _shutdown_sim():
    if sim_pid > 0:
        # SIGTERM lets the release flush persistence + close SQLite WAL.
        OS.kill(sim_pid, 15)
        # 2s grace, then SIGKILL if it's still alive.
        for i in 40:
            if not OS.is_process_running(sim_pid):
                return
            await get_tree().create_timer(0.05).timeout
        OS.kill(sim_pid, 9)
```

### User Data

By default the sim writes to `OS.get_user_data_dir()/sim.db` (via
`DATABASE_PATH` in the env above). On:

- **macOS**: `~/Library/Application Support/<game-name>/sim.db`
- **Windows**: `%APPDATA%/<game-name>/sim.db`
- **Linux**: `~/.local/share/<game-name>/sim.db`

Alongside the DB, the sim stores `secret_key_base` (auto-generated on
first run) and SQLite's `sim.db-wal` / `sim.db-shm` companion files.
To reset the simulation ("new game"), delete the whole directory.

### Logs

Prod builds log to **`<saves_dir>/simulator.log`** — not stdout.
Reason: when a parent process (Godot) spawns the sim via
`OS.create_process` and doesn't drain the child's stdout pipe, that
pipe fills in seconds under normal sim output; any subsequent
`Logger.*` call then blocks, cascading into ~half the ship agents
stalling on their tick handlers. File-based logging sidesteps this
entirely.

Rotation: 10 MB per file, 5 files kept (50 MB ceiling). Follow with
`tail -f <saves_dir>/simulator.log` for live output.

Default log level is `:warning`. Flip to `:info` or `:debug` for
diagnosis by setting `LOG_LEVEL=info` in the sim's env before launch.

Dev (`mix phx.server`) and tests still log to stdout as before.

### Scheduler / CPU visibility

The release's [rel/vm.args.eex](rel/vm.args.eex) forces `+S 16:16` —
16 BEAM schedulers, 16 online. This is critical: if the sim is
spawned from a sandboxed macOS `.app` bundle, BEAM's default
auto-detection can report only **1 logical processor online**, in
which case 250+ concurrent GenServers stampede a single thread and
the sim stalls within seconds.

Why 16 and not the auto-detected count? 16 covers every realistic
modern desktop (Apple Silicon M1–M4 are 8–12 cores, gaming PCs are
8–16). On machines with fewer physical cores, BEAM still spawns 16
scheduler threads but only the available CPUs get real time — the
extras are ~1 MB stack each and sit idle, essentially free. On
machines with MORE than 16 cores (32-core Threadrippers), we'd
leave some on the table. Override via `ERL_FLAGS="+S 32:32"` in the
spawn env if that applies — `ERL_FLAGS` wins over `vm.args`.

First log line of `simulator.log` after boot shows what the BEAM
actually picked up:

```
BEAM: schedulers=16 online=16 logical_cpus=... online=... otp=28 wordsize=64bit
```

If you see `schedulers_online=1` in that log even after the vm.args
fix, it means the sandbox is overriding our flags — add
`ERL_FLAGS=+S 16:16` to the Godot spawn env as a belt-and-suspenders
reinforcement, and double-check your `.app` entitlements.

### Release Size + Performance

- Release tarball: ~40 MB (includes Erlang runtime, BEAM files,
  bundled SQLite, priv data)
- Cold start to `/api/health` 200: **~5s** on first run (migrations +
  seed), **~1s** on subsequent runs
- RAM at steady state with 223 ships + 56 facilities + 23 markets:
  ~80 MB resident
- Tick load at 1× speed: p99 ~270 µs, 0 stalled agents

## Bootstrap Sequence

1. `GET /api/report` — full world snapshot (systems, ships, markets, facilities, populations, metrics)
2. Connect WebSocket to `ws://localhost:4000/simulation/websocket`
3. Join `simulation:tick` — receive `{"tick": N}` every simulation tick (4/sec at 1x speed)
4. Join `simulation:positions` — receive all ship positions every tick (**new, see below**)
5. Optionally join specific topics for detailed events

## REST API

### World Snapshot
```
GET /api/report
```
Returns everything at once — systems with body positions and orbital data, all agents, metrics:
```json
{
  "tick": 4585,
  "running": true,
  "health": "ok",
  "config": {
    "ticks_per_second": 8,
    "world_speed": 0.25,
    "tick_scale": 0.03125,
    "tick_interval_ms": 125
  },
  "systems": [
    {
      "id": "system-sol",
      "offset_x": 0.0,
      "offset_y": 0.0,
      "bodies": [
        {
          "id": "earth",
          "name": "Earth",
          "type": "planet",
          "biome": "terrestrial",
          "orbit_radius": 1.0,
          "orbit_period": 365,
          "current_angle": 45.2,
          "x": 0.707,
          "y": 0.707,
          "resources": {"ice": 0.3, "gas": 0.1}
        }
      ]
    },
    {
      "id": "system-alpha-centauri",
      "offset_x": 20.0,
      "offset_y": 5.0,
      "bodies": [...]
    }
  ],
  "ships": [{ "id": "ship-artemis-7", "name": "Artemis-7", "position": {"x": 1.2, "y": -3.4}, ... }],
  "markets": [{ "id": "market-earth-station", "prices": {"ore": 42.5}, "supply": {"ore": 1000}, ... }],
  "facilities": [{ "id": "facility-earth-station", "name": "Terra Prime", "position": {"x": 1.1, "y": 0.05}, "condition": 0.95, ... }],
  "populations": [{ "id": "pop-earth-workers", "population_count": 50000, ... }],
  "observers": [
    {"id": "default", "x": 0.0, "y": 0.0, "radius": 20.0, "owner": "dashboard", "label": null}
  ],
  "metrics": { "tick_avg_us": 45000, "ticks_per_second": 4.0 }
}
```

### Individual Queries
```
GET /api/ships          — all ships
GET /api/markets        — all markets
GET /api/facilities     — all facilities
GET /api/populations    — all populations
GET /api/factions       — all factions (treasury, subsidies, shortages)
GET /api/agent/:id      — single agent by ID (e.g., ship-artemis-7, faction-terran-authority)
GET /api/health         — quick health check
```

### Simulation Control
```
POST /api/sim/pause     — pause tick loop
POST /api/sim/resume    — resume tick loop
POST /api/sim/speed     — body: {"interval_ms": 250}  (250=1x, 125=2x, 50=5x, 25=10x)
```

### God-Mode Admin API

Mutation endpoints for the Godot client to add/destroy agents and poke
at market state. Loopback-only by default (BIND_IP=127.0.0.1), no auth.
Confirm dialogs live on the client side — the server just accepts the
mutation.

#### Create a ship
```
POST /api/admin/ships
Content-Type: application/json

{
  "name": "Void Star",
  "class": "courier",
  "faction_id": "the-doughtys",
  "location": "earth-station",
  "credits": 5000
}
```

Returns `201 Created` with `{id, name, class, faction_id, location, credits}`.
The `id` is derived from the name (`ship-void-star`); duplicates get
`-2`, `-3`, etc. suffixes. `class` must be one of the `ship_classes`
keys: `courier`, `freighter`, `hauler`, `tanker`, `miner`. Crew is
auto-assigned from the class definition.

#### Destroy a ship
```
DELETE /api/admin/ships/ship-void-star
```

Returns `204 No Content`. The agent is terminated (cargo, credits,
crew, passengers all lost), the DB row is deleted, and a
`:ship_decommissioned` event fires on `simulation:ship_events` with
`reason: "admin_destroyed"`.

#### Create a facility
```
POST /api/admin/facilities
Content-Type: application/json

{
  "name": "Proxima Research Post",
  "type": "station",
  "faction_id": "frontier-ventures",
  "body_id": "proxima",
  "location_name": "proxima-research",
  "credits": 20000
}
```

Returns `201 Created` with `{facility_id, market_id, location, type, faction_id, body_id, credits}`.
`type` must be one of `station`, `outpost`, `mining_rig`, `refinery`,
`factory`, `farm`, `hub`. `body_id` must match an existing celestial
body (look up via `/api/report` → `systems[].bodies[].id`). Starter
reserves are auto-assigned per type. A co-located `MarketAgent` is
also created.

#### Destroy a facility
```
DELETE /api/admin/facilities/facility-proxima-research
```

Returns `204 No Content`. Cascade:
1. Any ships currently docked are force-undocked (cargo/goal retained)
2. All contracts the facility was the requestor for are dropped
3. Co-located `PopAgent`s are terminated (populations cascade-delete in DB)
4. Co-located `MarketAgent` is terminated
5. Facility agent is terminated
6. DB row deleted (cascading markets + populations)
7. `:facility_destroyed` event fires on `simulation:facility_events`

#### Adjust market supply
```
POST /api/admin/markets/earth-station/supply
Content-Type: application/json

{
  "commodity": "fuel",
  "delta": 500
}
```

Returns `204 No Content`. Positive delta adds, negative subtracts
(floored at 0). Single-commodity per request — call multiple times for
multiple commodities.

#### Error responses

`400 Bad Request` with `{"error": "missing param: name"}` /
`"unknown ship class: \"warpcruiser\""` / `"unknown body: \"nowhere\""`
style messages on validation failures.

`404 Not Found` when the target ship/facility/market doesn't exist.

### Save-Game System

The sim is one SQLite file; a save is a named copy of that file.
Loading a save means launching the sim with `DATABASE_PATH` pointing
at that copy — the runtime auto-migrates + seeds on first boot, then
picks up from wherever the snapshot left off.

#### Force-flush current state

```
POST /api/admin/save
```

Flushes the dirty-agent set, walks every live agent and calls
`persist_state/1`, snapshots the contract board, then issues
`PRAGMA wal_checkpoint(TRUNCATE)` so the `.db` file is in a
copy-safe state. Returns 200:

```json
{"status": "saved", "tick": 12345, "flushed": 247, "contracts": 1840, "duration_ms": 183}
```

Use this before quitting, or periodically for autosave.

#### Save to a named slot

```
POST /api/admin/save-as
Content-Type: application/json

{"name": "save_game1"}
```

Runs `save/0`, then copies the active `.db` (plus any `-wal`/`-shm`
sidecars) to `<saves_dir>/<sanitized_name>.db`. Returns 201:

```json
{
  "name": "save_game1",
  "filename": "save_game1.db",
  "path": "/var/folders/.../simulator/save_game1.db",
  "size_bytes": 524288
}
```

Names are sanitized: lowercased, non-`[a-z0-9_-]` collapsed to `_`,
truncated to 64 chars. Cannot overwrite the active save
(returns 400 `cannot overwrite the active save`).

#### List saves

```
GET /api/admin/saves
```

Scans `<saves_dir>` for `*.db` files. Returns:

```json
{
  "saves": [
    {
      "name": "save_game1",
      "filename": "save_game1.db",
      "path": "/.../simulator/save_game1.db",
      "size_bytes": 524288,
      "modified_at": "2026-04-18T14:22:31Z",
      "active": false
    },
    {
      "name": "sim",
      "filename": "sim.db",
      "path": "/.../simulator/sim.db",
      "size_bytes": 1048576,
      "modified_at": "2026-04-18T14:22:02Z",
      "active": true
    }
  ]
}
```

The entry with `"active": true` is the currently-running DB; it can't
be chosen as a save-as target, but otherwise behaves like any other.

Godot can also just `readdir` the saves directory directly; the
endpoint is a convenience wrapper.

#### Loading a save

No endpoint — it's a process restart:

1. (Optional) `POST /api/admin/save` on the current session for a
   clean shutdown.
2. `SIGTERM` the sim (or disconnect stdin if you're using
   `PARENT_PID`-based lifecycle).
3. Relaunch with `DATABASE_PATH=<saves_dir>/save_game1.db` in the env.

The sim auto-migrates the chosen DB on first boot, so switching to an
older save schema is handled.

#### What's persisted

- Ships: credits, fuel, cargo (+ ages), location, transit, crew
  (skills/morale/hunger/fatigue/current_task), personality, memory,
  broke & hoard strikes, idle ticks, active-contract pointer.
- Facilities: credits, condition, reputation, reserves, docked ships,
  pending deliveries, level/xp, crew.
- Populations: count, sentiment, unrest, wealth, food satisfaction,
  migration pressure, body-food multiplier, secondary satisfactions.
- Markets: prices, supply, demand, production/consumption, pending
  orders, price history, trade volume, reserved goods,
  elasticity/spread.
- Bodies: current resource richness (depletion from mining).
- Factions: treasury. `active_subsidies` is rebuilt from the
  ContractBoard on init.
- Contracts: every field, every status transition. ETS is the
  authoritative store during play. `POST /api/admin/save` atomically
  snapshots the entire board to the `contracts` table (DELETE all +
  INSERT all in one transaction). Boot rebuilds ETS from
  `Repo.all(Contract)` before any agent queries the board. At 20K
  contracts a snapshot takes a few hundred ms — cheap for an
  on-demand save, but not something you'd run per-tick.
- Current tick.

#### What is NOT (yet) persisted

- Volatile rolling windows (market consumption window + shortage
  ticks, body food output window) — these rebuild from tick activity
  within ~100 ticks by design.
- Ships' current BehaviorTree / plan — regenerates from goal scoring
  in one tick after restart, not worth storing.

## WebSocket Channel Protocol

Uses the Phoenix Channel protocol (JSON over WebSocket). Every message has this shape:

```json
{
  "topic": "simulation:tick",
  "event": "phx_join",
  "ref": "1",
  "payload": {}
}
```

### Join a Topic
```json
{"topic": "simulation:tick", "event": "phx_join", "ref": "1", "payload": {}}
```
Server replies:
```json
{"topic": "simulation:tick", "event": "phx_reply", "ref": "1", "payload": {"status": "ok", "response": {}}}
```

### Heartbeat (required every 30s)
```json
{"topic": "phoenix", "event": "heartbeat", "ref": "99", "payload": {}}
```

### Available Topics

| Topic | Events Pushed | Use Case |
|-------|--------------|----------|
| `simulation:tick` | `tick` `{tick: N}` | Sync clock |
| `simulation:positions` | `positions` `{tick, interval_ms, ships: [{id, x, y}], observers: [{id, x, y, radius}]}` | High-frequency positions (every tick) |
| `simulation:ship_states` | `ship_states` `{tick, ships: [{id, location, transit, docked_at, goal, bt, cargo, fuel, credits, crew, ...}]}` | Delta-only state updates (~1/sec, only changed ships) |
| `simulation:markets` | `market_states` `{tick, markets: [{id, facility_id, prices, supply, demand, shortage_ticks}]}` | Full market snapshot (~2/sec, all markets every broadcast) |
| `simulation:body:<body_id>` | `food_availability` `{body_id, multiplier, tick}` | Per-body food-production multiplier used by pop growth (fires every production tick) |
| `simulation:faction:<faction_id>` | `subsidy_posted` `{faction_id, contract_id, commodity, destination, payment, multiplier, tick}` | Fires when a faction posts a subsidy contract to address a chronic shortage |
| `simulation:ship_events` | `ship_departed`, `ship_arrived`, `ship_decommissioned`, `goal_changed`, `docked`, `undocked` | Episodic global events |
| `simulation:market:<facility_id>` | `price_update`, `trade_executed`, `reserve_expired` | Market detail |
| `simulation:ship:<ship_id>` | `ship_arrived`, `ship_departed`, `ship_decommissioned` | Ship detail |
| `simulation:facility:<facility_id>` | `docking_event`, `mining_output`, `population_update` | Facility detail |
| `simulation:system:<system_id>` | `orbital_update` | Body positions |

### Channel Queries (request/response over WebSocket)

**Get agent state:**
```json
{"topic": "simulation:tick", "event": "get_state", "ref": "2", "payload": {"id": "ship-artemis-7"}}
```

**Get all agents of type:**
```json
{"topic": "simulation:tick", "event": "get_snapshot", "ref": "3", "payload": {"type": "ships"}}
```

**Simulation control:**
```json
{"topic": "simulation:tick", "event": "sim_control", "ref": "4", "payload": {"action": "pause"}}
{"topic": "simulation:tick", "event": "sim_control", "ref": "5", "payload": {"action": "resume"}}
{"topic": "simulation:tick", "event": "sim_control", "ref": "6", "payload": {"action": "set_speed", "interval_ms": 50}}
{"topic": "simulation:tick", "event": "sim_control", "ref": "7", "payload": {"action": "get_tick"}}
```

## Ship Data Structure

```json
{
  "id": "ship-artemis-7",
  "name": "Artemis-7",
  "class": "freighter",
  "system_id": "system-sol",
  "location": "earth-station",
  "position": {"x": 1.2345, "y": -3.4567},
  "transit": null,
  "cargo": {"ore": 250, "fuel": 50},
  "cargo_capacity": 500,
  "fuel": 85.5,
  "fuel_capacity": 100.0,
  "credits": 10000,
  "efficiency": 0.92,
  "faction_id": "terran-authority",
  "current_goal": "trade_run",
  "current_bt": "travel",
  "docked_at": null,
  "personality": {"profit": 0.7, "safety": 0.5, "exploration": 0.3},
  "crew": {
    "size": 5,
    "roles": ["pilot", "engineer", "trader", "medic", "general"],
    "hunger": 30,
    "fatigue": 45,
    "morale": 72,
    "health": 100,
    "current_task": "piloting"
  }
}
```

When in transit, `location` is `null` and `transit` has:
```json
{
  "transit": {
    "from": "earth-station",
    "to": "mars-station",
    "departure_tick": 100,
    "arrival_tick": 180
  }
}
```

## Facility Data Structure

Facilities are static structures attached to orbiting bodies. They have positions that move with their parent body.

```json
{
  "id": "facility-earth-station",
  "name": "Terra Prime Station",
  "type": "station",
  "location": "earth-station",
  "body_id": "earth",
  "position": {"x": 0.1234, "y": -0.0567},
  "condition": 0.95,
  "docking_capacity": 10,
  "docked_ships": ["ship-artemis-7", "ship-sol-trader"],
  "services": ["refuel", "repair", "medical", "market", "passenger_terminal"],
  "credits": 15000,
  "faction_id": "terran-authority",
  "reserves": {"fuel": 5000, "food": 3000, "water": 2000},
  "crew": {
    "size": 6,
    "roles": ["engineer", "engineer", "medic", "trader", "general", "general"],
    "hunger": 25,
    "fatigue": 30,
    "morale": 75,
    "health": 100,
    "current_task": "engineering"
  }
}
```

Facility types: `station`, `outpost`, `mining_rig`, `refinery`, `factory`, `farm`

### Facility Positions

Facilities orbit with their parent body. Multiple facilities at the same body (e.g., Earth has station + farm + factory) are offset in a small ring (0.15 radius) around the body position so they don't overlap. Positions are included in the `simulation:positions` broadcast alongside ships.

To distinguish ships from facilities in the positions stream, check the ID prefix: `ship-*` vs `facility-*`.

## Three-Tier Update Model

A game client should join these topics on connect, after fetching the initial `/api/report`:

1. **`simulation:positions`** — every tick (8/sec at 1x). Just `{id, x, y}`. Use for smooth movement interpolation.
2. **`simulation:ship_states`** — every ~1 second, **deltas only**. Server only includes ships whose state changed since the last broadcast. Most updates are small. Use to keep inspector panels and HUD elements in sync without polling.
3. **`simulation:markets`** — every ~2 seconds, **full snapshot**. Every broadcast contains all markets. Overwrite your market map wholesale — markets change too continuously for deltas to be worth the complexity. See the "Market Snapshot" section below.
4. **`simulation:ship_events`** — fired as events happen. `ship_departed`, `ship_arrived`, `ship_decommissioned`, `goal_changed`, `docked`, `undocked`. Use for sound effects, notifications, transit line updates.

`ship_states` payload includes everything the inspector needs:
```json
{
  "tick": 5000,
  "ships": [
    {
      "id": "ship-artemis-7",
      "name": "Artemis-7",
      "class": "freighter",
      "faction_id": "terran-authority",
      "location": null,
      "docked_at": null,
      "transit": {"from": "earth-station", "to": "mars-station", "departure_tick": 4980, "arrival_tick": 5060},
      "goal": "trade_run",
      "bt": "travel",
      "cargo": {"ore": 250},
      "cargo_capacity": 500,
      "cargo_age": {"ore": 4920},
      "passengers": 3,
      "passenger_capacity": 10,
      "fuel": 85.5,
      "fuel_capacity": 100.0,
      "credits": 10000,
      "broke_strikes": 0,
      "hoard_strikes": 0,
      "idle_ticks": 0,
      "crew": {"size": 5, "morale": 72, "health": 100, "hunger": 30, "fatigue": 45, "current_task": "piloting"}
    }
  ]
}
```

If `ships` is empty (no changes since last broadcast), the server skips the message entirely — your handler won't fire.

### Goal Values

The `goal` field can be any of:

| Goal | Meaning |
|------|---------|
| `trade_run` | Buy at one market, sell at another |
| `fulfill_delivery` | Pick up pre-purchased cargo and deliver for a fee |
| `fulfill_contract` | Buy goods and deliver against an open contract |
| `fulfill_passenger_transport` | Board passengers at one pop, deliver them to another |
| `refuel` | Dock and top up fuel |
| `rest_crew` | Dock and recover crew morale (forced when morale drops) |
| `explore` | Travel to a new location to learn prices |
| `sell_cargo` | Liquidate held cargo (triggered when broke or hoarding) |
| `station_job` | Short paid task at the docked facility (broke lifeline) |
| `do_crew_mission` | Longer themed mission posted by a facility — security detail, maintenance, harvest help, etc. Grows a crew skill on completion. |
| `idle` | No action this tick |

### Hoarding / Broke Tracking

Each ship carries three counters the client can use for inspector overlays or warning icons:

- `broke_strikes` — 0 to 3. Incremented every `broke_check_interval` the ship has ≤0 credits; at 3 the ship is decommissioned and respawned with a new personality
- `hoard_strikes` — 0 to 3. Incremented when the ship holds cargo older than `150 * tick_multiplier` ticks; at 3 the ship is decommissioned (hoarding recycle)
- `idle_ticks` — consecutive ticks the ship has picked the `idle` goal; resets as soon as any other goal wins
- `cargo_age` — map of `commodity → tick_received` for each stack currently in the hold. Subtract from the current tick to get the stack's age; used by the hoard detector

## Celestial Bodies

Bodies now carry a biome and a mutable resource pool. Mining rigs
extract from the pool (depleting richness over time) and bodies with
renewable biomes (terrestrial, gas_giant, ice, etc.) produce commodities
into their co-located markets each production tick.

Each body in `/api/report` includes:

- `biome` — one of: `terrestrial`, `ocean`, `desert`, `ice`, `asteroid`, `gas_giant`, `molten`, `industrial`, `lifeless`, or `null`
- `resources` — seed richness map (static per body)
- `x`, `y`, `current_angle` — orbital position

A separate `BodyAgent` owns the live/mutable state. Query it via
`/api/agent/body-<body_id>` for the full snapshot:

```json
{
  "id": "body-earth",
  "body_id": "earth",
  "biome": "terrestrial",
  "seed_resources": {"ice": 0.3, "gas": 0.1},
  "resources": {"ice": 0.2987, "gas": 0.0995},
  "locations": ["earth-station", "earth-farm"],
  "last_tick": 5000
}
```

Compare `resources[commodity]` to `seed_resources[commodity]` to show a
depletion gauge — e.g. `1.0 - current/seed` = fraction depleted.

### Biome Production

The biome drives what a body produces each production cycle. Common
mappings the client can hint at visually:

| Biome | Produces | Renders as |
|-------|----------|-----------|
| `terrestrial` | food, water, polymers | Blue-green planet |
| `ocean` | water, food | Deep blue world |
| `desert` | minimal food/water | Rust-red planet |
| `ice` | ice, water | White/pale cyan |
| `gas_giant` | gas, fuel | Banded orange |
| `molten` | — (mining only) | Glowing red |
| `asteroid` | — (mining only) | Grey rocks |
| `industrial` | food, polymers | Smoggy planet |
| `lifeless` | — | Grey moon |

### Food Availability Topic

`simulation:body:<body_id>` fires a `food_availability` event each
production tick with a multiplier in `[0.5, 2.0]`:

```json
{"body_id": "earth", "multiplier": 1.35, "tick": 5000}
```

1.0 = neutral (producing at expected rate), >1.0 = abundance, <1.0 =
starved. Pop agents on the body subscribe to this and scale their
growth rate; the client can mirror it as a "food surplus" overlay.

## Factions & Subsidies

Each faction now runs a macro-policy agent (`FactionAgent`) that acts
as a government/corporate stimulus layer on top of the per-facility
economy. It watches all its member facilities, aggregates shortage
signals, taxes members periodically to build a treasury, and posts
high-paying "subsidy contracts" when a commodity is chronically scarce
across multiple members. Subsidies flow through the regular
ContractBoard, so ships pick them up via normal goal scoring — they
just pay a lot more.

### Known Factions

As of the current seed there are 5 factions across 3 systems:

| ID | Name | Type | Home System |
|----|------|------|-------------|
| `terran-authority` | Terran Authority | government | `system-sol` |
| `mars-syndicate` | Mars Syndicate | corporation | `system-sol` |
| `belt-coalition` | Belt Coalition | coalition | `system-sol` |
| `frontier-ventures` | Frontier Ventures | corporation | `system-alpha-centauri` |
| `crucible-mining` | Crucible Mining Corp | corporation | `system-tau-ceti` |
| `the-doughtys` | The Doughtys | family | `system-sol` |

Get the full live list (including treasury, active subsidies, etc.) via
`GET /api/factions` — this is also embedded in `/api/report` as the
`factions` key.

### Faction State

```
GET /api/factions              — all factions
GET /api/agent/faction-<id>    — single faction live state
```

Both return the same per-faction shape:

```json
{
  "id": "faction-terran-authority",
  "faction_id": "terran-authority",
  "name": "Terran Authority",
  "personality": {"profit": 0.4, "safety": 0.9, "morale": 0.6, "exploration": 0.2, "loyalty": 0.8, "aggression": 0.1},
  "treasury": 48523,
  "member_facilities": ["earth-station", "mars-station", "luna-base", "kuiper-station"],
  "active_subsidies": ["contract-412", "contract-418"],
  "shortage_cache": {
    "mars-station": {"food": 85, "medical": 12},
    "earth-station": {"food": 42}
  },
  "last_tick": 5000
}
```

Key fields:

- **`treasury`** — credits the faction has available to fund subsidies. Fills
  via tax sweeps every 200 ticks (0.5% of each member facility's credits
  above a 1000-cr operating buffer). Drains as subsidies are posted.
- **`member_facilities`** — location names (not facility IDs) of every
  facility this faction owns. Use these to look up facilities via
  `/api/agent/facility-<location>`.
- **`active_subsidies`** — IDs of subsidy contracts currently on the board.
  Look them up via ContractBoard-backed queries or by listening on
  `simulation:contracts`.
- **`shortage_cache`** — live snapshot of `shortage_ticks` per member
  facility, updated from each market's `price_update` broadcast. A
  non-zero value means that commodity at that facility has been scarce
  for that many consecutive ticks and is a candidate for subsidy.

### Subsidy Dynamics

A commodity becomes a subsidy candidate when it's been short
(`shortage_ticks > 30`) at **≥2 member facilities** at the same time.
Every 30 ticks the faction evaluates candidates and posts at most 3
subsidies at once (within its ContractBoard per-requestor cap).

Payout scales with how chronic the shortage is:

```
multiplier = 1.25 + min((max_shortage_ticks - 30) / 100, 1.75)
payment    = 2000 × multiplier
quantity   = 200 units
```

So a fresh subsidy pays 2500 cr; one that's been pounding on an
unresolved 130-tick shortage pays 6000 cr. This gives ships (and AI
goal scoring) a stronger pull the longer a crisis drags on.

Subsidy contracts land on the regular ContractBoard with:

- `contract_type: "supply"`
- `requestor_type: "faction"`
- `requestor_id` = `faction_id` = the subsidizing faction
- `min_reputation: 20` (open to neutral-and-above ships)
- Reputation bonus on completion (standard contract flow)

They appear in `simulation:contracts` broadcasts and show up normally
in `/api/agent/ship-*`'s `available_contracts` — no special handling
needed client-side to surface them, though you may want to tag them
visually with the faction color for the operator.

### simulation:faction:<faction_id> Topic

The per-faction topic fires `subsidy_posted` events every time the
faction posts a new subsidy. Use this for:

- **Notification pop-ups** — "Terran Authority is paying 6000 cr for food to Mars Station"
- **Map overlays** — draw a colored beacon at the destination until the contract clears
- **Faction activity heatmap** — subsidy frequency per faction indicates how strained its economy is

Payload:

```json
{
  "faction_id": "terran-authority",
  "contract_id": "contract-412",
  "commodity": "food",
  "destination": "mars-station",
  "payment": 4200,
  "multiplier": 2.1,
  "tick": 5000
}
```

Subscribe just like any other channel topic:

```gdscript
socket.send({
  "topic": "simulation:faction:terran-authority",
  "event": "phx_join",
  "ref": "10",
  "payload": {}
})
```

To watch all factions at once, subscribe to each of the five faction
topics on connect. Cheap — at most 3 events per faction per 30 ticks
(~4 seconds at 1×), so way under 1 message/second total.

## Crew Missions

Facilities periodically post themed missions that the ship's *whole
crew* (treated as a unit — no per-crew-member agents) takes on. Think
security detail at a station, heavy maintenance at a mining rig,
harvest help at a farm. The ship stays docked for the mission duration,
and on completion collects the payment, faction rep, and a small
skill-growth bump on the mission's required skill. This is distinct
from the existing `:station_job` broke-lifeline work — crew missions
pay much more (800–2000 cr vs 100–250) but take much longer.

### Mission Contract Shape

Crew missions appear on the regular ContractBoard with `contract_type:
"crew_mission"` and extra fields describing the work:

```json
{
  "id": "contract-981",
  "contract_type": "crew_mission",
  "requestor_type": "facility",
  "requestor_id": "facility-earth-station",
  "source_location": "earth-station",
  "destination_location": "earth-station",
  "mission_category": "security_detail",
  "display_name": "Security Detail",
  "required_skill": "combat",
  "duration_ticks": 30,
  "skill_gain": 3,
  "payment": 1500,
  "faction_id": "terran-authority",
  "min_reputation": 20
}
```

### Mission Catalog

Current catalog (tune freely; subject to change):

| Category | Posted By | Duration (base ticks) | Payment | Skill | Gain |
|---|---|---|---|---|---|
| `security_detail` | station | 30 | 1500 | combat | +3 |
| `vip_escort` | station | 20 | 1200 | navigation | +2 |
| `customs_assist` | station | 15 | 800 | trading | +2 |
| `heavy_maintenance` | mining_rig, refinery | 40 | 2000 | engineering | +3 |
| `salvage_operation` | mining_rig | 35 | 1800 | engineering | +2 |
| `production_assist` | factory | 25 | 1400 | engineering | +2 |
| `equipment_calibration` | factory, refinery | 20 | 1100 | engineering | +2 |
| `harvest_help` | farm | 30 | 1200 | general | +1 |
| `safety_audit` | refinery | 25 | 1500 | engineering | +2 |

Duration in the contract is expressed in *base* ticks — the sim scales
by `tick_multiplier` on the ship side. For client-side ETAs, multiply
the contract's `duration_ticks` by `config.tick_multiplier`
(available in `/api/report`) or use the contract's broadcast timestamp
as the reference.

### Crew Skill Growth

Crew skills were static before this phase. Now they grow on mission
completion — the `skills` map on crew state ticks up 1–3 points per
mission, capped at 100. For UI:

- Bar-style crew skill display (0–100 fill) is now meaningfully
  animated — show a delta flash on completion
- Compare `/api/agent/ship-veteran` vs `/api/agent/ship-rookie` to
  showcase progression

### Mission Completion Event

When a ship completes a crew mission, it broadcasts
`:crew_mission_completed` on `simulation:facility:<source_location>`:

```json
{
  "ship_id": "ship-artemis-7",
  "facility_location": "earth-station",
  "category": "security_detail",
  "payment": 1500,
  "tick": 5000
}
```

Useful for:

- Mission-complete notification pops on the facility's station UI
- Faction activity feed ("Terran Authority +1 reputation with
  Artemis-7")
- Highlighting the ship that just finished for a few seconds on the
  map

### Archetype Tip

No new archetype was added for crew missions — existing archetypes
score them via considerations. Expect these archetypes to gravitate
toward crew missions:

- `reliable_trucker` (high loyalty) — matches missions requiring
  trading or general skill
- `cautious_trader` (high safety) — low-risk docked work fits profile
- `courier` (Phase 5) — skill_fit on navigation makes VIP escort a
  natural pull

## Passenger Transport

Ships now have a `passenger_capacity` (separate from `cargo_capacity`)
and a live `passengers` count. Populations with size > 5000 and healthy
sentiment periodically post passenger contracts to reachable
destinations; couriers with the new archetype preferentially pick them
up and disembark at the destination, which **actually bumps the
destination pop's `population_count`** — emergent migration.

### New Ship Fields

Ship state (via `/api/agent/ship-*` or the `simulation:ship_states`
delta broadcast) now includes:

- **`passenger_capacity`** — integer, set by ship class:

  | Class | Cargo | Passengers |
  |-------|-------|-----------|
  | `courier` | 50 | **20** |
  | `explorer` | (uses freighter stats) | — |
  | `freighter` | 500 | 10 |
  | `hauler` | 2000 | 5 |
  | `miner` | 200 | 0 |
  | `tanker` | 1500 | 0 |

- **`passengers`** — live count of passengers aboard (`0` ≤ passengers ≤ passenger_capacity)

### Passenger Contract Shape

Passenger contracts appear on the regular ContractBoard and in ships'
`available_contracts` with `contract_type: "passenger_transport"`:

```json
{
  "id": "contract-8123",
  "contract_type": "passenger_transport",
  "requestor_type": "population",
  "requestor_id": "pop-earth-workers",
  "source_location": "earth-station",
  "destination_location": "mars-station",
  "passenger_count": 12,
  "payment": 1850,
  "urgency": 0.3,
  "status": "posted",
  "posted_at_tick": 5000,
  "deadline_tick": 5500
}
```

Key differences from cargo delivery contracts:

- `passenger_count` replaces `commodity`/`quantity` semantics
- No `reserve_id` (passengers aren't pre-purchased)
- No `cargo_deposit` (no insurance)
- Payment is a single `payment` field (not `delivery_fee + cargo_deposit`)

### Courier Archetype

A new `courier` archetype joined the random pool. Identifiable by its
`prefer_goals`:

```json
{
  "profit": 0.6,
  "safety": 0.8,
  "morale": 0.7,
  "exploration": 0.2,
  "loyalty": 0.8,
  "aggression": 0.0,
  "prefer_goals": {
    "fulfill_passenger_transport": 0.35,
    "fulfill_delivery": 0.25,
    "station_job": 0.15
  }
}
```

If you want to render the ship's archetype in-game, the presence of
`fulfill_passenger_transport` in `prefer_goals` is a reliable
fingerprint.

### Arrival Events

When a ship completes a passenger transport, it broadcasts
`:passengers_arrived` on `simulation:facility:<destination>` with the
count delivered. The destination's pop agent subscribes to this topic
and adds the count to its `population_count` — so you'll see the
destination pop grow in real time.

```json
{"destination": "mars-station", "passenger_count": 12, "tick": 5200}
```

Useful for:

- **Arrival animations** — spawn passenger sprites disembarking
- **Migration flow visualization** — draw arrows between pops with
  arrival traffic
- **Population-change indicators** — flash the destination pop card
  when it grows

### The Doughtys

Added to factions.json as a small family-owned courier fleet —
entirely a flavor/easter-egg faction. Five ships named after a real
family of friends: David, Becca, Everett, Hazel, Tobias Doughty. They
start at different Sol locations with `class: "courier"` and
`faction_id: "the-doughtys"`. Visible in `/api/factions` and
`/api/ships` like any other faction/ship.

## Market Snapshot Stream

`simulation:markets` pushes a `market_states` event every ~2 seconds containing the full current state of every market. Clients overwrite their market map wholesale — no delta tracking, no reconnect resync needed.

```json
{
  "tick": 5000,
  "markets": [
    {
      "id": "market-earth-station",
      "facility_id": "earth-station",
      "prices": {"ore": 42.5, "fuel": 28.3, "food": 18.1},
      "supply": {"ore": 1200, "fuel": 50, "food": 800},
      "demand": {"ore": 20, "fuel": 120, "food": 150},
      "shortage_ticks": {"fuel": 85}
    }
  ]
}
```

At ~25 markets × ~10 commodities × a few fields, each broadcast is ~3–5 KB. Use this for market panels, supply-chain maps, "scarcity flare" overlays (non-zero `shortage_ticks[commodity]` means that commodity has been starved for that many consecutive ticks and prices are climbing under the urgency multiplier).

If you also want per-market trade events (individual buy/sell fills, reserve expirations), subscribe to `simulation:market:<facility_id>` — that topic still fires `price_update`, `trade_executed`, `reserve_expired` every tick.

### Per-Market Price Updates

For tick-resolution market detail (every tick, one topic per facility), subscribe to `simulation:market:<facility_id>`. The `price_update` event fires every tick with the same shape used in the bulk snapshot, plus a `tick` field:

```json
{
  "facility_id": "earth-station",
  "prices": {"ore": 42.5, "fuel": 28.3, "food": 18.1},
  "supply": {"ore": 1200, "fuel": 50, "food": 800},
  "demand": {"ore": 20, "fuel": 120, "food": 150},
  "shortage_ticks": {"ore": 0, "fuel": 85, "food": 0},
  "tick": 5000
}
```

A non-zero `shortage_ticks[commodity]` indicates sustained scarcity — prices are climbing faster than the normal elasticity cap and ships delivering that commodity will cash in. The bulk `simulation:markets` snapshot is enough for most panels; this topic is for when you need per-tick resolution on a single market (e.g., a detailed trader view).

## Position Interpolation

At 1x speed, the server sends 4 position updates per second. For smooth rendering at 60fps, the Godot client should interpolate between the last two known positions:

```gdscript
var prev_pos: Vector2
var next_pos: Vector2
var lerp_t: float = 0.0
var tick_interval: float = 0.25  # updated from positions broadcast interval_ms

func _on_positions_broadcast(data: Dictionary):
    # Server tells us the exact interval — use it for lerp timing
    tick_interval = data["interval_ms"] / 1000.0  # 0.25 at 1x, 0.025 at 10x
    for ship in data["ships"]:
        update_entity(ship["id"], ship["x"], ship["y"])

func update_entity(id: String, x: float, y: float):
    prev_pos = next_pos
    next_pos = Vector2(x, y)
    lerp_t = 0.0

func _process(delta):
    lerp_t = min(lerp_t + delta / tick_interval, 1.0)
    position = prev_pos.lerp(next_pos, lerp_t)
```

For ships in transit, you can also predict position using departure/arrival ticks and linear interpolation without waiting for server updates.

## Body Orbit Prediction

Body positions are deterministic — you can predict them client-side without waiting for server updates:

```gdscript
# Each body has: orbit_radius, orbit_period, current_angle (from /api/report)
# IMPORTANT: The server scales orbit advance by tick_scale (world_speed / ticks_per_second).
# The client must apply the same scale factor to match.
#
# tick_scale = world_speed / ticks_per_second (get from /api/report or hardcode)
# Currently: 0.25 / 8 = 0.03125

var TICK_SCALE: float  # read from /api/report config.tick_scale on connect

func predict_body_position(body: Dictionary, ticks_elapsed: int, system_offset: Vector2) -> Vector2:
    var delta_per_tick = 360.0 / body["orbit_period"] * TICK_SCALE
    var angle_deg = fmod(body["current_angle"] + delta_per_tick * ticks_elapsed, 360.0)
    var angle_rad = deg_to_rad(angle_deg)
    var local_x = body["orbit_radius"] * cos(angle_rad)
    var local_y = body["orbit_radius"] * sin(angle_rad)
    return system_offset + Vector2(local_x, local_y)
```

This means bodies only need to be fetched once on initial load. Track the tick count and predict positions locally. Periodically call `/api/report` to resync if drift accumulates.

## Observers (Chunk System Camera)

Observers control the tick-resolution gradient — entities near an observer tick at full speed, distant ones tick less often. The Godot client's viewport should be an observer.

Included in `/api/report` (full detail) and every `simulation:positions` broadcast (compact):

```json
{
  "id": "default",
  "x": 0.0,
  "y": 0.0,
  "radius": 20.0,
  "owner": "dashboard",
  "label": null
}
```

Observer types: `dashboard` (debug), `player` (game viewport), `system` (always-on)

To move the observer (e.g., when the player pans the camera), send via the channel:
```json
{"topic": "simulation:tick", "event": "move_observer", "ref": "8", "payload": {"x": 15.0, "y": 3.0}}
```

## Coordinate System

- Universe coordinates: continuous 2D space
- Sol at (0, 0), Alpha Centauri at (20, 5), Tau Ceti at (40, -10)
- Body `x`/`y` in the report are already in universe coordinates (offset applied)
- Bodies orbit within their system (radius ~0.5 to ~3.0 from system center)
- Facilities orbit with their parent body, offset 0.15 radius in a ring
- Ships move between body positions along straight lines
- All positions from `simulation:positions` and `/api/positions` are in universe coordinates

## Tick Timing

- 1x speed = 125ms per tick = 8 ticks/sec
- 2x speed = 62ms per tick = 16 ticks/sec
- 5x speed = 25ms per tick = 40 ticks/sec
- 10x speed = 12ms per tick = 80 ticks/sec (max)

World speed is 1/8th the original simulation pace — ships take 30-60 seconds to travel between planets at 1x. The tick rate (8/sec) is independent from world speed — changing one doesn't affect the other.
