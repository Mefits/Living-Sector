# CLAUDE.md

Context for Claude Code (claude.ai/code) when working in the `simulator-rust/` project.

## What this is

Rust port of an Elixir/Phoenix space-economy simulator. Drives a Godot client.
Replaces the Elixir original because BEAM's process scheduler performs poorly
on Windows gaming PCs. Target: 800 agents today, 100k+ eventually. Single
native binary, no runtime dependencies. See [`PLAN.md`](./PLAN.md) for the
full session log.

## Architecture (one-liner per layer)

```
Godot ⇄ WebSocket/HTTP (axum) ─┐
                                ├── sim_server (tokio, sqlx, axum)
                                │     ├── engine: tick loop driver + command apply
                                │     ├── ws/handler: per-client select loop
                                │     ├── http/api: inspection + sim control endpoints
                                │     ├── snapshot: DashMap lock-free read cache
                                │     └── db: pool + seeder + ECS loader
                                │
                                └── sim_core (pure, no async)
                                      ├── agents/*: components + tick fns (hecs::World)
                                      ├── ai/*: BT, utility scoring, considerations, personality
                                      ├── economy/*: commodities, order_book, price_engine, recipes
                                      ├── simulation/*: config, spawner (AgentStore), commands
                                      └── world/*: registry, travel, body
```

**Golden rules:**

1. **sim_core never imports tokio, sqlx, or axum.** Pure logic only. This
   keeps the core trivially testable in `#[test]` blocks and means the ECS
   tick can be reasoned about without async.
2. **hecs is the source of truth during a tick.** `AgentStore` wraps
   `hecs::World`. The tick loop holds exclusive mutable access — no locks.
   After the tick, `SnapshotCache` is updated for readers.
3. **Cross-phase effects go through `SimCommand`.** A phase reads world
   state, writes commands to the buffer, and never mutates other entities
   mid-phase. The next phase drains and applies. Gives deterministic replay
   and prevents write conflicts.
4. **Tick phase order matters** and is fixed in `engine::run_tick_loop`:
   `drain-control → bodies → ships → apply-supply-commands → facilities →
   populations → markets → snapshot-write → publish`.

## Crate layout

| Crate | Depends on | Purpose |
|---|---|---|
| `sim_core` | `hecs`, `serde`, `rand`, `rayon` | All simulation logic, pure |
| `sim_server` | `sim_core` + `tokio`, `axum`, `sqlx`, `dashmap`, `flume` | Runtime binary |

## Common tasks

| Task | Command |
|---|---|
| Compile + test + clippy | `scripts/verify.sh [--strict]` |
| Boot sim, inspect DB | `scripts/smoke.sh [secs]` |
| Boot + exercise HTTP | `scripts/ws-test.sh [secs]` |
| Faster game-time for demos | `WORLD_SPEED=4.0 scripts/smoke.sh 30` |
| Trace sqlx queries | `RUST_LOG=trace scripts/smoke.sh` |

Do NOT run `cargo run` without `WORLD_SPEED` set — the default 0.25 makes
Earth-Mars take 5 minutes, which is fine for gameplay but useless for a
30-second smoke test. Use `WORLD_SPEED=2.0` to `4.0` for validation.

## Conventions

### Module documentation
Every non-trivial file starts with `//!` module-level docs explaining what
the module is responsible for and any non-obvious constraints. Examples:

- `agents/ship.rs`: component splits rationale + tick phase ordering
- `economy/price_engine.rs`: coverage model + urgency multiplier
- `simulation/commands.rs`: why the command buffer exists

If you add a new file, document it the same way.

### hecs borrow patterns
`hecs::World::query_mut::<(&mut A, &mut B)>()` can only hold ONE mutable
iterator at a time. If a tick phase needs to read from markets while
mutating ships, structure it as two passes:
1. Pass 1: snapshot the read-only data into a `HashMap`
2. Pass 2: iterate mutably using the snapshot

See `ship::tick_ships` (3-pass) and `facility::tick_facilities` (index-first)
for the canonical patterns.

### Commands vs direct mutation
Same-entity mutations can go in-place. Cross-entity effects MUST go through
`SimCommand`. Example: a ship selling cargo updates its own credits + cargo
directly, but emits `SimCommand::AddSupplyAtShipLocation` for the market-side
effect, which the engine applies in a separate phase after iterating ships.

### Testing
- Pure logic tests live in `#[cfg(test)] mod` inside the module
- Integration scripts live in `scripts/` (bash; verify.sh, smoke.sh, ws-test.sh)
- No test database is needed — the seeder is deterministic and runs on every
  fresh DB. Use `mktemp` for test DBs.

### Don't do
- Don't add `Mutex<AgentState>` per agent. hecs owns the world; the tick loop
  owns hecs. Readers go through `SnapshotCache`.
- Don't fire async work from inside the tick loop. The tick loop is CPU work.
  If you need async I/O, enqueue a command and handle it in a tokio task.
- Don't serialize whole agent state to JSON per tick. The snapshot types are
  trimmed for a reason — they're what Godot actually renders.
- Don't introduce Actix, bevy_ecs (vs hecs), tracing-core alternatives, or
  other heavy frameworks without a clear justification in PLAN.md.

## Protocol quick ref (Godot ↔ sim_server)

Plain JSON over WebSocket. See `crates/sim_server/src/ws/protocol.rs`.

**Server → Godot** (pushed):
- `server_hello` — on connect, heartbeat
- `positions` — every tick (125ms at default speed)
- `ship_states` — every 8 ticks
- `market_states` — every 16 ticks
- `agent_state` — reply to `get_agent` / `get_snapshot`
- `sim_control_ack` — reply to pause/resume/speed

**Godot → Server**:
- `hello`, `get_agent`, `get_snapshot`, `move_observer`, `sim_control`

HTTP (same port, `/api/*`):
- Read: `/api/health`, `/api/report`, `/api/{ships,markets,facilities,populations,factions,positions}`, `/api/agent/:id`
- Control: `POST /api/sim/{pause,resume,speed}` (speed takes `{interval_ms}`)

## Binary invocation (Godot subprocess scenario)

1. Godot runs `./simulator[.exe]` as a subprocess
2. Sim prints `sim:ready ws=ws://127.0.0.1:8080/ws http=http://127.0.0.1:8080/api tick=0` on stdout
3. Godot waits for that line, then connects
4. On shutdown (Godot exits or SIGTERM), sim gracefully stops within 500ms

## Things intentionally left out (read `PLAN.md` for full list)

- Persistence worker (DB state flush) — sim currently re-seeds on each boot; fine for dev, needs adding for player saves
- Contract board lifecycle (Phase 4.5) — ships trade directly rather than via contracts
- Crew morale / shore leave
- Spatial LOD chunk divisors — not needed until 10k+ agents
- Faction tick (reputation decay, treasury flow)
- Full BT engine wiring for ships (MVP uses state machine instead)
- Windows cross-compile — user will build natively on Windows
