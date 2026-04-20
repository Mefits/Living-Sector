# CLAUDE.md

Context for Claude Code (claude.ai/code) when working in the `simulator-rust/` project.

## What this is

Rust port of an Elixir/Phoenix space-economy simulator. Drives a Godot client.
Replaces the Elixir original because BEAM's process scheduler performs poorly
on Windows gaming PCs. Ships at 800 agents today, designed to scale to 100k+.
Single native binary, no runtime dependencies. See [`PLAN.md`](./PLAN.md) for
the session log.

## Status

Phases 1–10 complete. The sim has full economy behavior:
populations post food contracts when stressed, ships fulfill them, facilities
run production recipes, factions collect tax revenue, crew get tired and take
shore leave, and state persists across restarts. See the **Systems wired** table
below for what's actually running.

## Architecture

```
Godot ⇄ WebSocket/HTTP (axum) ─┐
                                ├── sim_server (tokio, sqlx, axum)
                                │     ├── engine: tick loop driver + command apply
                                │     ├── ws/handler: per-client select loop
                                │     ├── http/api: inspection + sim control endpoints
                                │     ├── snapshot: DashMap lock-free read cache
                                │     └── db: pool + seeder + ECS loader + persistence worker
                                │
                                └── sim_core (pure, no async)
                                      ├── agents/*: components + tick fns (hecs::World)
                                      │   ship, market, facility, population, celestial_body, faction
                                      ├── ai/*: BT<A> generic engine, utility scoring, considerations, personality
                                      ├── economy/*: commodities, order_book, price_engine, recipes, contracts
                                      ├── simulation/*: config, spawner (AgentStore), commands (SimCommand)
                                      └── world/*: registry, travel, body
```

### Golden rules

1. **sim_core never imports tokio, sqlx, or axum.** Pure logic only.
   Trivially testable in `#[test]` blocks, reasoned about without async.
2. **hecs is the source of truth during a tick.** `AgentStore` wraps
   `hecs::World` + the `ContractBoard`. The tick loop holds exclusive
   mutable access — no locks. After the tick, `SnapshotCache` is updated
   for HTTP/WS readers.
3. **Cross-phase effects go through `SimCommand`.** A phase reads world
   state, writes commands to a buffer, and never mutates *other* entities
   mid-phase. The next phase drains and applies. Deterministic replay,
   no write conflicts.
4. **Tick phase order is fixed** in `engine::run_tick_loop`:
   ```
   drain-control → bodies → ships → apply-ship-commands →
   facilities → populations → markets → apply-market-commands →
   factions → snapshot → broadcast → emit-persist-writes
   ```

## Crate layout

| Crate | Depends on | Purpose |
|---|---|---|
| `sim_core` | `hecs`, `serde`, `rand`, `rayon` | All simulation logic, pure |
| `sim_server` | `sim_core` + `tokio`, `axum`, `sqlx`, `dashmap`, `flume` | Runtime binary |

## Systems wired

| System | Where | Behavior |
|---|---|---|
| Ship BT planner | `agents/ship::plan_goal` | Picks goal + builds `BtNode<ShipAction>`: rest_crew → refuel → sell_cargo → fulfill_delivery → trade_run → idle |
| Ship BT execution | `agents/ship::execute_ship_action` | Dispatch closure for ShipAction variants (Travel/Dock/Refuel/Buy/Sell/SellAll/AcceptContract/DeliverCargo/Rest/Idle) |
| Market tick | `agents/market::tick_markets` | 8 phases: produce → consume → emergency orders → surplus orders → match → update-demand → track-shortage → update-prices |
| Price engine | `economy/price_engine` | Coverage model (supply as buffer, not ratio) + shortage urgency multiplier |
| Facility recipes | `agents/facility::tick_facilities` | 10 recipes, limiting-factor scaling, runs against local market supply every 5 base-ticks |
| Mining | same | `mining_rig` facilities extract commodities from their body's resources |
| Population | `agents/population::tick_populations` | Consume food/fuel from local market, produce labor commodity, update sentiment, **post food-delivery contracts when satisfaction < 40** |
| Contracts | `economy/contracts::ContractBoard` | Posted → Accepted → Paid lifecycle, `posted_with_destination` lookup, expiry sweep |
| Factions | `agents/faction::tick_factions` | Every 50 base-ticks, 5% tax on each owned facility's credits → faction treasury |
| Crew morale | `agents/ship::tick_crew` | Fatigue rises in transit (0.05/tick); morale drops when fatigue > 60; rest recovers both; efficiency = 0.5 + morale/200 |
| Persistence | `db/persistence::PersistenceWorker` | mpsc buffer + dedup + 5s batch flush; ships / markets / factions / tick counter. Load tick counter on startup → sim resumes. |

## Common tasks

| Task | Command |
|---|---|
| Compile + test + clippy | `scripts/verify.sh [--strict]` |
| Boot sim, inspect DB | `scripts/smoke.sh [secs]` |
| Boot + exercise HTTP | `scripts/ws-test.sh [secs]` |
| Verify persistence round-trip | `scripts/persist-test.sh` |
| Faster game-time for demos | `WORLD_SPEED=4.0 scripts/smoke.sh 30` |
| Trace sqlx queries | `RUST_LOG=trace scripts/smoke.sh` |

Default `WORLD_SPEED=0.25` (chill play). Earth-Mars ≈ 4 min. Good for
interactive Godot play. For smoke tests / validation use `WORLD_SPEED=4`
or higher to see economic convergence in tens of seconds.

World speed is runtime-adjustable via `POST /api/sim/speed
{world_speed: N}` or the HUD 1×/2×/5×/10× buttons (0.25 / 0.5 / 1.25 / 2.5).
Tick resolution (client smoothness) is a separate knob:
`{ticks_per_second: 16}`.

## Conventions

### Module documentation

Every non-trivial file starts with `//!` module-level docs explaining what
the module is responsible for and any non-obvious constraints. Examples:

- `agents/ship.rs`: component split rationale + tick phase ordering + ShipAction enum
- `economy/price_engine.rs`: coverage model + urgency multiplier
- `economy/contracts.rs`: lifecycle + index structure
- `simulation/commands.rs`: why the command buffer exists
- `ai/behavior_tree.rs`: why BtNode is generic over A (fn-pointer capture problem)

When you add a file, document it the same way.

### hecs borrow patterns

`hecs::World::query_mut::<(&mut A, &mut B)>()` holds ONE mutable iterator
at a time. If a tick phase needs to read from markets while mutating ships,
structure it as two passes:

1. **Snapshot pass** — read-only query copies the needed data into a
   `HashMap<loc, snapshot>`
2. **Mutating pass** — iterate mutably, closing over the snapshot

Canonical patterns:
- `ship::tick_ships` — 3 passes: `advance_transits` → `observe_prices` → `decide_and_act`
- `facility::tick_facilities` — build location→market index, then iterate facilities
- `market::tick_markets` — collect entity list, then `query_one` per entity (single-entity multi-component mutable borrow)

### Commands vs direct mutation

- **Same-entity mutations** go in-place. A ship selling cargo updates its
  own credits + cargo directly.
- **Cross-entity effects** MUST go through `SimCommand`. Market supply
  deltas from ship trades emit `SimCommand::{Add,Remove}SupplyAtShipLocation`
  which the engine resolves to the destination market entity in a
  dedicated apply phase.
- Contract state transitions (Accept / Deliver) go via commands so the
  apply phase can pay the ship, mutate cargo, update market supply, and
  mark the contract Paid atomically.

### BT engine conventions

`BtNode<A>` is generic over a domain action type. For ships, A is
`ShipAction`. The tick method takes a dispatch closure:

```rust
let mut dispatch = |action: &ShipAction, bb: &mut Blackboard| -> BtStatus {
    execute_ship_action(action, entity, ..., bb)
};
bt.tick(&mut bb, &mut dispatch);
```

The closure owns the mutable borrows of the ship's components for this
ship's tick. When building a BT, bake parameters into the action variant
(e.g. `ShipAction::Travel { destination: "earth-station".into() }`) —
this is why `A` exists instead of plain `fn` pointers.

### Testing

- Pure logic tests live in `#[cfg(test)] mod` inside the module
- Integration smokes live in `scripts/` (bash)
- No test database is needed — the seeder is deterministic. Use `mktemp`
  for ephemeral test DBs.

### Don't do

- **Don't add `Mutex<AgentState>` per agent.** hecs owns the world; the
  tick loop owns hecs. Readers go through `SnapshotCache`.
- **Don't do async work inside the tick loop.** The tick is CPU work.
  For I/O, enqueue a command and handle it in a tokio task (the
  persistence worker is the canonical example).
- **Don't serialize whole agent state to JSON per tick.** Snapshot types
  are trimmed for a reason — they're what Godot actually renders.
- **Don't bring in Actix, bevy_ecs (vs hecs), or other heavy frameworks**
  without a clear justification in PLAN.md.
- **Don't call `query_mut` while holding a `query_one` result** on
  another entity — hecs only allows one mutable iterator at a time.
- **Don't write directly to a component across entities** mid-phase. Use
  a `SimCommand` so the apply phase does it after the iteration.

## Protocol quick ref (Godot ↔ sim_server)

Plain JSON over WebSocket on port 8080. See
`crates/sim_server/src/ws/protocol.rs` — that's the canonical reference.

**Server → Godot** (pushed):
- `server_hello` — on connect, reports current tick + running state
- `positions` — every tick (125 ms @ default speed). Carries `entities`
  with `type: "ship" | "body"` — Godot client filters ships.
- `ship_states` — every 8 ticks (~1 s). Full ship snapshots.
- `market_states` — every 16 ticks (~2 s). Prices/supply/demand/shortage_ticks.
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
4. On SIGTERM / SIGINT, sim flips the running flag, persistence worker has up to
   1000 ms grace to flush the final batch, then process exits cleanly

For dev runs: `client/dev.env` has `SPACESIM_USE_EXISTING_SERVER=1` so the
Godot editor expects the Rust sim to already be running on port 8080. Just
`cargo run --bin simulator` in one terminal and open Godot in another.

## Things intentionally left out (not critical; see `PLAN.md` for rationale)

- **Admin HTTP endpoints** (god-mode ship/facility spawn, save-as, market
  supply delta). Godot client calls these; they 404 gracefully. Port when
  someone needs them.
- **Rayon parallelism** — dependency is in, never called. Architecture is
  designed for it. Skip until 10k+ agents.
- **Facility / population persistence** — only ships, markets, factions,
  and tick counter flush today. Non-persisted agents fall back to seed
  state on restart; sim re-converges within seconds.
- **Contract reputation gating** — all contracts are open to all ships.
  A faction-reputation filter would add texture.
- **Faction spending** — treasuries grow from tax but factions never spend.
  Could post their own contracts or subsidize facilities.
- **Per-crew-member simulation** — crew is aggregated on the ship. 800
  ships × avg 4 crew = 3200 individual entities we're NOT spawning, which
  was an explicit call. Individual variation is in the SQLite `crew_members`
  table for future richer missions.
- **Spatial LOD chunk divisors** — the Elixir sim throttled distant agents
  to tick less often. We haven't needed it; 800 agents tick in ~5 ms.
- **Windows native build** — cross-compile setup exists; user will
  validate on their Windows box.
