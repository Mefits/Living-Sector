# Space Simulator Client

Godot 4.6 / GDScript client for an Elixir/Phoenix space simulation. Top-down
3D visualization of autonomous ships, orbiting bodies, trading, and markets.
The server lives in a sibling project and owns simulation truth — this client
renders, interpolates, and sends observer position.

## Running

- Server must be up on `localhost:4000`. If the client prints HTTP errors,
  check the server process first.
- Open the project in the Godot 4.6 editor and run `scenes/main.tscn`.

## Architecture

- `scripts/main.gd` — bootstraps: HTTP `/api/report` → build world → open WebSocket.
- `scripts/autoload/game_state.gd` — central singleton. Holds ships / facilities /
  markets / populations / systems, all keyed by id. Emits signals on update.
- `scripts/autoload/network_manager.gd` — HTTP + native `WebSocketPeer` speaking
  Phoenix Channels v2 JSON directly. ~200 lines, no addon.
- `scripts/world/` — the 3D scene graph: systems, orbital bodies, ships,
  facilities, transit lines, starfield, selection ring, observer puck.
- `scripts/ui/` — HUD: details panel, ship list, market overlay, toasts, minimap.
- `scripts/camera/game_camera.gd` — isometric camera at -70° tilt. Zooming moves
  along the view axis (Y + Z together), not just Y.

## Server connection

- REST: `http://localhost:4000/api/*`. Key endpoint: `GET /api/report` —
  full world snapshot (systems, ships, facilities, markets, populations, config).
- Sim control: `POST /api/sim/{pause,resume,speed}`. `speed` body:
  `{"interval_ms": N}` (250=1x, 125=2x, 50=5x, 25=10x).
- WebSocket: `ws://localhost:4000/simulation/websocket?vsn=2.0.0` (Phoenix v2).
- Heartbeat every 25s, format `[null, ref, "phoenix", "heartbeat", {}]`.
- Phoenix message shape: `[join_ref, ref, topic, event, payload]`.

Four topics are joined on connect:

| Topic | Cadence | Contents |
|---|---|---|
| `simulation:tick` | every tick | `{tick: N}`. Also the topic we push `move_observer` on. |
| `simulation:positions` | every tick (~125ms) | `{tick, interval_ms, ships: [{id, x, y}], observers: [...]}`. `ships` includes **facilities too** — distinguish by ID prefix. |
| `simulation:ship_states` | ~1s, deltas | Only ships whose metadata changed. Carries the full inspector view: `location`, `transit`, `docked_at`, `goal`, `bt`, `cargo`, `cargo_capacity`, `cargo_age`, `fuel`, `fuel_capacity`, `credits`, `crew`, `broke_strikes`, `hoard_strikes`, `idle_ticks`, `name`, `class`, `faction_id`. Partial shapes — client merges only keys present, preserves the rest. Empty broadcasts are skipped server-side. |
| `simulation:ship_events` | episodic | `ship_departed`, `ship_arrived`, `ship_decommissioned`, `goal_changed`, `docked`, `undocked`. Decommission removes from state; others mainly drive toasts. |

Not currently subscribed but available per the reference doc: `simulation:market:<facility_id>` (includes `prices`, `supply`, `demand`, `shortage_ticks` — useful for scarcity overlays), `simulation:facility:<facility_id>`, `simulation:system:<system_id>`, `simulation:ship:<ship_id>`.

## Coordinate system

- Server is 2D universe coordinates (Vector2, continuous).
- Godot is 3D; we use the XZ plane with Y=0. Y is up (camera looks down).
- `GameState.SCALE_FACTOR = 10.0`. Convert via `GameState.server_to_world(x, y)`.
- System layout: Sol (0,0), Alpha Centauri (20,5), Tau Ceti (40,-10). Pulled
  from `/api/report` at runtime — hardcoded in `game_state.gd` only as fallback.
- Bodies orbit within systems at radius ~0.5–3.0 from the system center.
- Facilities orbit with their parent body, offset in a ring so they don't overlap.

ID prefixes: `ship-*`, `facility-*`, `system-*`, `market-*`, `pop-*`. The
positions channel and some event payloads rely on these for routing.

## Tick timing

- 1x speed = 8 ticks/sec = 125 ms/tick. Client reads `tick_interval_ms` from
  server on each positions broadcast; don't assume a constant.
- `GameState.tick_scale = world_speed / ticks_per_second = 0.03125`. Used by
  body orbit prediction so the client advances bodies at the same rate as server.
- Positions are interpolated between ticks via `(prev → next) * smoothstep(t)`
  where `t = elapsed / tick_interval`. See `ship.gd` for the reference impl.
- Body positions are deterministic; predicted client-side from
  `orbit_radius`, `orbit_period`, `current_angle` + tick count. No server round-trip.

## Data flow

- Initial snapshot (`/api/report`) populates everything.
- 30s HTTP re-fetch (`network_manager._refresh_report`) reconciles metadata.
  It explicitly skips `position` to avoid fighting the WS stream.
- `positions` WS event owns `ship.position` and `facility.position` live.
- `ship_states` deltas own everything else that changes during play
  (fuel, cargo, credits, location, goal, crew, etc.).
- UI re-reads from `GameState.ships` on every `tick_updated` signal, so once
  GameState is fresh, the panels are fresh.

## Gotchas

- **Field name mismatches**: on `ship_states` WS payloads the server uses
  `goal` and `bt`; the `/api/report` snapshot uses `current_goal` and
  `current_bt`. `GameState.update_ship_states` normalizes at ingest so
  UI code only sees the `current_*` names.
- **WebSocketPeer buffer size**: default 64 KB is too small for bulk broadcasts;
  we set `inbound_buffer_size = 4 MB` before `connect_to_url`. Smaller values
  cause close code 1009 "Message too big" and a reconnect loop.
- **ship_states is a delta, not a snapshot**: only ships with changed metadata
  appear in each payload, and only changed fields per ship. Don't assume a
  missing field means null — it means unchanged.
- **Docked ships**: server broadcasts authoritative positions. Do NOT snap
  ships to facility positions client-side — the server handles it, and any
  client-side snap fights its interpolation during undock.
- **Selection follows entities**: `GameState.selected_entity_id` is just an
  id; the camera follow logic in `main.gd` looks up the 3D node each tick.
  On `ship_removed`, main detaches the selection ring before the node is freed.

## Debugging

- `network_manager.gd` has two debug flags:
  - `DEBUG_WS = true` — lifecycle (connect, join, disconnect w/ close code).
  - `DEBUG_WS_TRAFFIC = false` — every inbound/outbound message. Very noisy;
    flip on only when hunting a protocol-level bug.
- Close codes: 1000 = normal, 1006 = network drop, 1008 = policy, 1009 = msg
  too big (usually our buffer), 1011 = server error.
- `/tmp/phx_ping.py` is a small script that sanity-checks all four channels
  accept `phx_join`. Useful for isolating client bugs from server bugs.
