# Space Simulator Client

Godot 4.6 / GDScript client for a Rust space-economy simulation. Top-down
3D visualisation of autonomous ships, orbiting bodies, trade + contracts
+ markets. The Rust sim lives at `../simulator-rust/` and owns all
simulation truth — this client renders, interpolates the tick stream,
runs inspector panels, and sends an observer position so the sim can
apply spatial LOD around the viewport.

> **Where we are**: Rust sim is Phases 1–15 complete (ship LOD, full
> inspector panels, admin CRUD, persistence round-trip, crew
> missions). See `../simulator-rust/SESSION-HANDOFF.md` for the
> scannable orientation and `../simulator-rust/CLAUDE.md` for the
> server's architecture. This doc covers the client only.

## Running

- Rust sim must be up on `localhost:8080`. If `HTTP errors` appear in
  the console on boot, check the server terminal first.
  ```bash
  cd ../simulator-rust
  WORLD_SPEED=4.0 cargo run --bin simulator
  ```
- `dev.env` already sets `SPACESIM_USE_EXISTING_SERVER=1`, so the
  editor won't try to spawn its own backend — it just connects.
- Open the project in the Godot 4.6 editor and run `scenes/main.tscn`.

For legacy fallback to the old Elixir sim (not used in normal dev):
set `SPACESIM_TARGET_ELIXIR=1` in `dev.env` and swap `network_manager.gd`
for `network_manager_phoenix.gd.bak`. Kept for reference only — most
features have moved past the Elixir API and won't work on it.

## Architecture

- **`scripts/main.gd`** — bootstraps: HTTP `/api/report` → build world →
  open WebSocket → per-frame observer send for spatial LOD.
- **`scripts/autoload/game_state.gd`** — central singleton. Caches all
  server state keyed by id: ships, facilities, markets, populations,
  factions, systems, contracts, event ring buffer (cap 400), perf
  stats (p50/p99 + LOD tier distribution). Signals on every update.
- **`scripts/autoload/network_manager.gd`** — native `WebSocketPeer`
  + `HTTPRequest` speaking the Rust sim's plain-JSON protocol. No
  Phoenix wrapper. ~400 lines.
- **`scripts/world/`** — 3D scene graph: star systems, orbital bodies,
  ships, facilities, transit lines, starfield, selection ring,
  observer puck.
- **`scripts/ui/`** — HUD + the 13 inspector panels (see below).
- **`scripts/camera/game_camera.gd`** — isometric camera at −70° tilt.
  Zoom moves along the view axis; the zoom value drives the observer
  radius sent to the sim.

## Server connection

### HTTP (port 8080)

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Live status + `perf.tick_compute_{p50,p99}_us` + `perf.lod.{d1,d2,d5,d10,d20,d50}` |
| GET | `/api/report` | Full world snapshot (systems / ships / facilities / markets / pops / factions + config + perf). The main bootstrap source. |
| GET | `/api/ships` / `/api/markets` / `/api/facilities` / `/api/populations` / `/api/factions` / `/api/positions` / `/api/contracts` / `/api/observers` | Per-type snapshot lists |
| GET | `/api/agent/:id` | Single agent by agent-id |
| POST | `/api/sim/pause` / `/api/sim/resume` | Flip the running flag |
| POST | `/api/sim/speed` | Body `{world_speed: f32, ticks_per_second: u32}` — either or both. Independent knobs. |
| POST | `/api/sim/step` | Body `{ticks: u32}` — advance N ticks even while paused. Perf HUD's ▸1 / ▸8 buttons use this. |
| POST | `/api/admin/ships` | Body `{class, faction_id, location, name?, credits?}` → 201 with `{id, db_id, position}`. Spawns a live ship, persists + registers in ECS. |
| DELETE | `/api/admin/ships/:id` | Remove ship by agent-id. |
| POST | `/api/admin/facilities` | Body `{name, facility_type, body_id, faction_id, location?, docking_capacity?, credits?}` → 201. |
| DELETE | `/api/admin/facilities/:id` | Remove facility. |
| POST | `/api/admin/markets/:loc/supply` | Body `{deltas: {commodity: delta}}` or `{commodity, delta}` — adjust a market's supply for debug. |
| POST | `/api/admin/save` | No-op ack (persistence worker is already flushing every 5 s). |
| POST | `/api/admin/save-as` | Body `{name}` → creates `name.db` alongside the active DB via `VACUUM INTO`. |

### WebSocket (`ws://localhost:8080/ws`)

Plain JSON, `type` field discriminates. Full definitions live in
`../simulator-rust/crates/sim_server/src/ws/protocol.rs` — that's
canonical.

**Server → client** (pushed automatically):

| Type | Cadence | Payload |
|---|---|---|
| `server_hello` | On connect | `{tick, running, agent_count, interval_ms, world_speed}` |
| `positions` | Every tick (~125 ms) | `{tick, interval_ms, entities:[{id, x, y, type: "ship"|"body"|"facility"}]}` |
| `ship_states` | Every 8 ticks (~1 s) | Partial deltas per ship — only keys that changed. `crew.current_task` / `crew.skills` / `crew.hunger` land here. |
| `market_states` | Every 16 ticks (~2 s) | Full per-market snapshot: `prices`, `supply`, `demand`, `shortage_ticks` |
| `facility_states` | Every 16 ticks | Full per-facility: `docked_ships` (array of ship-ids), `reserves`, `condition`, `credits`, `level`, `xp`, `abandoned` |
| `population_states` | Every 16 ticks | Pop count, `overall_sentiment`, `food_satisfaction`, `total_wealth` |
| `faction_states` | Every 32 ticks (~4 s) | Treasury + `active_subsidies` + member counts |
| `contract_states` | Every 32 ticks | Full contract board: 6 kinds with `status`, `faction_id`, `min_reputation`, `mission_category` for crew missions |
| `events` | Every tick when non-empty | Mixed stream: `ship_spawned`, `ship_docked`, `ship_decommissioned`, `facility_spawned`, `facility_removed`, `facility_abandoned`, `contract_delivered`, `crew_mission_completed`, `passengers_arrived`, `market_supply_adjusted`. Fires `event_received` signal per event + appends to ring buffer. |
| `agent_state` | On request | Reply to client `get_agent` / `get_snapshot` |
| `sim_control_ack` | On control command | `{action, tick, running, world_speed, interval_ms}` |

**Client → server**:

- `hello {client_id}` — on connect
- `move_observer {id, x, y, radius}` — sent every 50 ms from `main.gd`
  using camera position + zoom-scaled radius so the sim can LOD
  distant agents
- `get_agent {id}` / `get_snapshot {agent_type}`
- `sim_control {action, ...}` — pause / resume / set_world_speed /
  set_ticks_per_second / get_tick

## Coordinate system

- Server universe = 2D `(x, y)` in `f32` universe units.
- Godot renders in 3D on the XZ plane with Y=0 (camera looks down).
  `Y` is up.
- `GameState.SCALE_FACTOR = 10.0`. Convert via `GameState.server_to_world(x, y)` → `Vector3(x*10, 0, y*10)`.
- System layout from `/api/report`: Sol (0,0), Alpha Centauri (20,5),
  Tau Ceti (40,−10). Hardcoded defaults in `game_state.gd` are
  fallback only.
- Bodies orbit within their system at radius ~0.5–3.0 from the
  system centre. Facilities orbit with their parent body at a fixed
  0.15-universe-unit offset, placed by `facility_offset_position`
  (same function used server-side in `ship::advance_transits` so ship
  approach arcs land on the station, not the planet).
- ID prefixes: `ship-*`, `facility-*`, `market-*`, `pop-*`,
  `contract-*`, `system-*`. Bodies have bare slugs ("earth", "mars")
  — no prefix. Positions routing in `universe.gd` relies on this.

## Tick timing

- Default `world_speed = 0.25`, `ticks_per_second = 8`, `tick_interval_ms = 125`.
  Earth↔Mars ≈ 4 min. For smoke runs the dev script sets `WORLD_SPEED=4.0`
  which compresses that to ≈ 25 s.
- `world_speed` and `ticks_per_second` are **independent knobs** —
  speed changes game-time pace, tps changes client smoothness. HUD
  speed buttons drive only `world_speed`; the `sim_control_ack`
  echoes both on every command so the HUD stays in sync.
- `GameState.tick_scale = world_speed / ticks_per_second`. Ships use
  this server-side; client uses it to advance body orbits between
  ticks.
- Positions are interpolated between ticks via
  `(prev → next) * smoothstep(t)` where `t = elapsed / observed_interval_ms`.
  We use the **observed** interval (EMA of wall-clock gaps between
  `positions` broadcasts) rather than the server-reported one — this
  survives mid-run speed changes without snapping.

## Inspector panels

13 toggle-able from the top HUD bar. All share `theme_palette.gd`
colours. All show via `toggle()` methods and close via an X button.

| Panel | Script | Trigger | Role |
|---|---|---|---|
| Ship list | `ship_list.gd` | HUD: Ships | Sortable 6-col table (name/class/location/goal/fuel/warn). Click row → camera follows. Strike warnings colour-coded. |
| Market overlay | `market_overlay.gd` | HUD: Market | One row per market location, commodity cells with sparkline history (~3 min window, sampled every 16 ticks). Price colour = red/green ramp across locations. |
| Contract board | `contract_board.gd` | HUD: Contracts | 9-col sortable (kind/status/commodity/qty/source→dest/pay/age/faction/rep). Kind + status filter chips. Click → selects fulfilling ship if any. |
| Faction ledger | `faction_ledger.gd` | HUD: Factions | Treasury / active subsidies / ship count / facility count. Colour by treasury health. |
| Population browser | `population_browser.gd` | HUD: Pops | Count / sentiment / food_sat sortable. Sentiment green ≥70 / amber ≥40 / red <40. |
| Events ticker | `events_ticker.gd` | HUD: Events | RichTextLabel rolling feed with kind filter. Click an event → emits `focus_requested` → main.gd points camera. |
| Perf overlay | `perf_overlay.gd` | HUD: Perf | Tick p50/p99, FPS, ticks/broadcast, observed interval ms, LOD tier breakdown (`d1:215 d2:3 …`), 60-sample sparkline of p99 with 125 ms budget line. Polls `/api/health` every 1 s while visible. |
| Details panel | `details_panel.gd` | Click ship / facility / body | Live inspector + "Recent activity" section pulled from `GameState.events_for_agent(id)`. |
| Minimap | `minimap.gd` | Always on | 3 system dots + camera viewport rectangle. Clickable to jump. |
| God toolbar | `god_toolbar.gd` | Always on (bottom-left) | Destroy toggle + `+Ship` + `+Facility` buttons. |
| Add ship panel | `add_ship_panel.gd` | God toolbar | Class / faction / location / credits → `POST /api/admin/ships`. |
| Add facility panel | `add_facility_panel.gd` | God toolbar | Name / type / body / faction → `POST /api/admin/facilities`. |
| Facility reserves editor | `facility_reserves_panel.gd` | Context menu → Edit Supply | Per-commodity supply delta → `POST /api/admin/markets/:loc/supply`. |

Plus the always-on HUD strip: tick, FPS, ship count, speed label
(`%d×` / `%.1f×` / `%.2f×` — reads `GameState.world_speed`, not
`tick_interval_ms`), pause button, 1× / 2× / 5× / 10× speed buttons,
observer toggle, ▸1 / ▸8 step-debug buttons (pause + step works for
slow-mo debugging), save / save-as.

## Data flow

- Initial snapshot (`/api/report`) populates `GameState.ships`,
  `.facilities`, `.markets`, `.populations`, `.factions`, `.systems`
  and `config` (tick interval, world_speed, tick_scale).
- 30 s HTTP re-fetch (`network_manager._refresh_report`) reconciles
  metadata. Explicitly skips `position` to avoid fighting the WS
  stream.
- Per-tick `positions` WS event owns `ship.position` / `facility.position`
  / body position. Universe routes by id prefix; bodies (no prefix)
  go to `_body_nodes[id].update_position`.
- `ship_states` deltas own everything else that changes during play
  (fuel, cargo, credits, location, goal, crew, etc.).
- `facility_states` / `population_states` / `faction_states` /
  `contract_states` fire their respective signals on `GameState`,
  and every panel that cares just reads from the singleton and
  rebuilds on the signal.
- `events` fires `GameState.event_received(event, tick)` per event
  AND appends to `event_log` (ring buffer, cap 400).
- UI panels re-read from `GameState` on every `tick_updated` signal,
  so once GameState is fresh, panels are fresh.

## Spatial LOD (observer send)

`main.gd::_process` sends a `"camera"` observer every 50 ms. Position
is `camera.position.xz / SCALE_FACTOR` (back to universe space).
Radius scales with `GameState.zoom_raw` — zoomed out = larger
attention volume, so more of the visible world stays at divisor 1.
Minimum radius 5 universe units. Explicit Observer mode sends a
second entry layered on top.

The sim's tier table (server-side, in `sim_core/src/simulation/lod.rs`):
within radius → divisor 1, within 2× radius → 2, 5× → 5, 10× → 10,
20× → 20, beyond → 50. "Divisor 50" means the agent ticks once per
50 real ticks but burns 50× fuel that tick, so total state change over
wall-clock is preserved.

The perf overlay surfaces the current distribution — `d1:215 d2:3 d10:8 d50:9`
is the at-a-glance health check. If you pan the camera and see
everything stuck at `d1`, the observer isn't landing.

## Gotchas

- **Field name mismatches**: server `ship_states` uses `goal` / `bt`;
  `/api/report` uses `current_goal` / `current_bt`.
  `GameState.update_ship_states` normalises at ingest so UI code
  only sees `current_*`. If you add a new field that has different
  names across endpoints, add the normalisation there.
- **Market snapshot key**: `market.facility_location` (NOT `facility_id`).
  The latter is a stale Elixir-era name — if you see it in code, it's
  a bug. Both `market_overlay.gd` and `facility_reserves_panel.gd`
  read `facility_location` first and fall back, but new code should
  just use the correct name.
- **WebSocketPeer buffer**: default 64 KB is too small for bulk
  broadcasts; we set `inbound_buffer_size = 4 MB` before
  `connect_to_url`. Smaller values trigger close code 1009 and a
  reconnect loop.
- **Docked ships**: server broadcasts authoritative positions. Do
  NOT snap ships to facility positions client-side — the server
  handles it (via `ship::advance_transits` using the same
  `facility_offset_position` we'd compute) and any client snap
  fights its interpolation during undock.
- **Body positions come from the server, not client-side prediction.**
  We previously had `orbital_body.gd` predicting orbit math locally
  — bodies drifted out of sync with server facilities after a
  `world_speed` change and snapped back. The current code uses
  server `positions` broadcasts with a short pre-first-broadcast
  orbit-prediction fallback only.
- **Scene reload after .gd edits.** Godot's scene loader fails hard
  on a parse error in one script and silently wedges unrelated
  panels. After editing GDScript, reload the project in the editor
  (Ctrl+Shift+T or close + reopen) to see the real errors. Phase 14
  spent an hour on this exact trap.
- **Selection follows entities**: `GameState.selected_entity_id` is
  just an id; `main.gd` looks up the 3D node each tick. On
  `ship_removed`, main detaches the selection ring before the node
  is freed.

## Debugging

- `network_manager.gd` has two debug flags:
  - `DEBUG_WS = true` — lifecycle (connect, disconnect + close code).
  - `DEBUG_WS_TRAFFIC = false` — every inbound/outbound message. Very
    noisy; flip on only when hunting a protocol-level bug.
- `market_overlay.gd` has a `DEBUG = false` flag that dumps refresh
  diagnostics (matched-facility count, rows_created, first row's
  children) — useful when a panel renders empty.
- WebSocket close codes: 1000 = normal, 1006 = network drop, 1008 =
  policy, 1009 = message too big (bump buffer), 1011 = server error.
- Client-side live perf: open the Perf overlay (HUD: Perf button).
  Tick p50 / p99, FPS, observed interval, LOD tier breakdown, and
  the rolling p99 sparkline all live there.
