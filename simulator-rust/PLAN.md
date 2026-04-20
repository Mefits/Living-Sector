# Rust Space Simulator — Long-Term Plan

Porting the Elixir/Phoenix space simulator to Rust for native Windows/Linux performance.
Godot is the sole client. No web dashboard. Single binary, no dependencies.

## Why Rust

The Elixir BEAM is outstanding on macOS/Linux but BEAM processes under Windows' thread
scheduler become the bottleneck at 800+ agents. Cross-platform game distribution (Windows
gaming PCs) requires a native binary that maps well to the OS. Rust + Tokio (I/O) + Rayon
(CPU parallelism) is the right fit: we get near-zero overhead agent logic with genuine
hardware-level parallelism.

## Project Structure

```
simulator-rust/
├── Cargo.toml                 — workspace (sim_core + sim_server)
├── PLAN.md                    — this file
├── crates/
│   ├── sim_core/              — pure simulation logic (no async, fully testable)
│   │   └── src/
│   │       ├── ai/            — behavior_tree, utility, considerations, personality
│   │       ├── agents/        — ship, market, facility, population, faction, celestial_body
│   │       ├── economy/       — commodities, order_book, contracts, recipes, reputation
│   │       ├── spatial/       — chunk_manager, position_tracker, quadtree
│   │       ├── world/         — body, travel, registry
│   │       └── simulation/    — config, spawner, tick
│   └── sim_server/            — tokio runtime, axum HTTP/WS, sqlx
│       └── src/
│           ├── ws/            — WebSocket handler + Godot JSON protocol
│           ├── http/          — /api/health, /api/report, /api/agent/:id
│           ├── db/            — pool, persistence worker, seeder
│           └── engine.rs      — bridges sim_core tick ↔ async I/O
└── priv/
    ├── data/worlds/           — same JSON world files as Elixir version
    └── migrations/            — sqlx migration SQL
```

## Architecture Principles

- **hecs ECS** for entity/component storage — archetype-based, cache-friendly at 100k+ scale.
  Each agent type is spawned with a bundle of small components (ship = 9 components: Identity,
  Position, Transit, Cargo, Fuel, Economy, AI, Memory, Lifecycle). Ticks query only the
  components they need — position updates don't pull cargo into cache.
- **Unified command buffer** for cross-phase effects. Phases read world state, write
  `SimCommand`s to a buffer, and never mutate mid-phase. Next phase drains and applies. Gives
  deterministic replay, no parallel-write conflicts, clean debug audit trail.
- `sim_core` owns all agent state (the `hecs::World` inside `AgentStore`). Tick loop has
  exclusive access — no locks during tick.
- Rayon `par_iter_mut()` for CPU parallelism within each tick phase (where hecs allows).
- `DashMap` snapshot caches for concurrent reads from HTTP/WS handlers.
- Tokio only for I/O: WebSocket connections, SQLite writes, HTTP.
- No per-agent Tokio tasks — agent logic is CPU work, not async I/O.
- SQLite pool size = 1 (WAL mode; one writer, dedup before flushing).
- Bundled SQLite (`libsqlite3-sys` `bundled` feature) — no DLL on Windows.

## Key Crates

| Crate | Purpose |
|---|---|
| tokio (rt-multi-thread) | Async runtime for I/O |
| axum 0.8 | HTTP + WebSocket |
| sqlx 0.8 (sqlite, json, migrate) | Async SQLite |
| serde + serde_json | JSON serialization |
| dashmap 6 | Concurrent hashmap (ETS replacement) |
| rayon 1 | CPU parallelism over agent slices |
| flume 0.11 | Channels engine→WS, engine→DB |
| tracing | Structured logging |
| arc-swap | Hot-swappable world registry |
| hecs 0.10 | ECS entity/component storage |

## Tick Phase Ordering (125ms per tick, 8 tps)

1. Commands — drain pause/resume/speed/observer channel
2. Bodies — advance orbital angles
3. Ships (rayon) — crew, utility scoring, BT step, position; outputs pending_orders
4. Apply effects — drain pending_orders into market queues
5. Markets (rayon) — produce → consume → match → price update → snapshot
6. Facilities (rayon) — recipes, crew missions, docking
7. Populations (rayon, every Nth tick) — food, sentiment, contracts
8. Spatial LOD (every Nth tick) — recalculate chunk divisors
9. Snapshot write — each agent → DashMap SnapshotCache
10. Dirty marking — build DbWrites → send to persistence channel

## WebSocket Protocol (Godot ↔ Simulator)

Plain JSON. No Phoenix channel format.

**Server → Godot** (pushed automatically):
- `positions` — every tick: `{type, tick, interval_ms, entities:[{id,x,y,type}]}`
- `ship_states` — every 8 ticks: `{type, tick, ships:[{...}]}`
- `market_states` — every 16 ticks: `{type, tick, markets:[{...}]}`
- `server_hello` — on connect + every 30s

**Godot → Server** (commands):
- `move_observer` — move the spatial LOD viewport
- `sim_control` — pause / resume / set_speed
- `get_agent` — request single agent snapshot
- `get_snapshot` — request all agents of a type

Simulator prints `sim:ready ws=ws://127.0.0.1:8080/ws` to stdout on boot.
Godot waits for that line before connecting.

## Database Schema (Redesigned for Rust)

The Elixir schema stored volatile state in a single JSONB `state` column per agent.
This version expands most scalars into typed columns. Only truly schema-less data
(cargo maps, price_knowledge) remains as JSON.

Key changes from Elixir:
- `ships.cargo` → JSON column (commodity → quantity map)
- `ships.price_knowledge` → JSON column (location → commodity → {price, tick})
- `ships.credits`, `fuel`, `position_x/y` → typed REAL/INTEGER columns
- `markets` → separate `market_prices` table (market_id, commodity, price, supply, demand)
- `market_price_history` → append-only table for price charts
- `populations` → all scalar fields as typed columns, no JSON blobs

World JSON files (`sol.json`, `alpha_centauri.json`, `tau_ceti.json`, `factions.json`)
are unchanged — the seeder maps them to the new schema on first boot.

## Implementation Progress

### Phase 1 — Pure Logic ✅ (completed)
- [x] Commodity enums, base prices, tier definitions
- [x] Personality axes, archetypes, variation
- [x] Behavior tree engine (4 node types, tick, sequence resume)
- [x] Utility AI (score_action, best_action, rank_actions)
- [x] Order book match algorithm
- [x] Simulation config (tick params, ship classes)
- [x] World data JSON files copied
- **35 tests passing**

### Phase 2 — State Structs + DB + Spawner ✅ (completed)
Files: `sim_core/src/agents/`, `sim_core/src/simulation/`, `sim_server/src/db/`
- [x] Agent components (ship: 9; market: 5; facility: 4; pop: 4; body: 3; faction: 1)
- [x] `SimCommand` + `CommandBuffer` for deterministic cross-phase effects
- [x] SQLite schema (typed columns, minimal JSON for cargo/price-maps)
- [x] Seeder: JSON world files → SQLite (idempotent upserts)
- [x] Spawner: SQLite → hecs::World + string-id lookup HashMaps
- [x] Engine tick loop: orbital body advancement, tick counter
- [x] Smoke scripts: `scripts/verify.sh`, `scripts/smoke.sh`, `scripts/check-api.sh`
- **Verified**: binary loads 223 ships + 56 facilities + 23 markets + 19 pops + 6 factions + 23 bodies, logs `sim:ready`, tick advances at 8 tps.

### Phase 3 — Market Logic ✅ (completed)
Files: `sim_core/src/agents/market.rs`, `sim_core/src/economy/price_engine.rs`
- [x] `price_engine` with coverage-model pressure + shortage urgency multiplier (9 tests)
- [x] `market::tick_markets` over hecs::World — 8 phases: produce→consume→emergency→surplus→match→update-demand→track-shortage→update-prices
- [x] Emergency orders (market-emergency) restock critical commodities at premium
- [x] Surplus orders (market-surplus) offload oversupply at discount
- [x] Rolling consumption window with warmup floor
- [x] Spread revenue → facility via `SimCommand::TransferCredits`
- [x] Engine tick loop wired; commands drained per tick
- **Verified**: 20s smoke shows earth-station prices move naturally (abundant fuel 22→8, tight ore 45→76, surplus food 8→3). 47 tests passing.

Deferred: contract board lifecycle (Phase 4 alongside ship goal execution), market state persistence (Phase 7 dirty-flush worker), per-ship order settlement (Phase 4).

### Phase 4 — Ship Logic ✅ (MVP completed; BT/contract integration deferred)
Files: `sim_core/src/agents/ship.rs`, `sim_core/src/ai/considerations.rs`, `sim_core/src/simulation/commands.rs`
- [x] 9 ship components split for cache locality (Identity, Position, Transit, Cargo, Fuel, Economy, AI, Memory, Lifecycle)
- [x] Considerations module: fuel_urgency, trade_opportunity, cargo_opportunity, cargo_to_sell, financial_pressure, exploration_desire, docked_at_facility (6 tests)
- [x] State-machine tick (3 passes): advance_transits → observe_prices → decide_and_act
- [x] `best_trade_route` scans price memory for highest-margin pair
- [x] Ship intent → SimCommand emission (AddSupplyAtShipLocation, RemoveSupplyAtShipLocation)
- [x] Engine command-apply phase resolves ship location → market entity
- [x] Spawner seeds initial price knowledge from all markets (bootstrap: captains know rough prices)
- [x] WORLD_SPEED env override for faster smoke tests
- **Validated**: 40s smoke at WORLD_SPEED=4 → ships trade profitably; avg credits +25% (9423→11815), max ship credits doubled (20k→40k), 70 ships carry cargo mid-trip, fuel supply rising at earth-station. 56 tests passing.

**Deferred to Phase 4.5 / Phase 6:**
- Full BT engine integration (fn-pointer action model — state machine works for MVP)
- Real market order placement (currently direct credits↔cargo transfer at known prices, no order-book round-trip)
- Contract board + fulfill_contract / fulfill_delivery goals (needs contracts table exercised)
- Crew morale, rest_crew goal (needs crew tick loop — Phase 6)
- Spatial LOD chunk divisors (800 agents ticks fine without it; needed at 10k+)
- Ship docking against real facility entities (currently `docked_at = None` always)

### Phase 5 — WebSocket Server + HTTP API ✅ (server side complete; Godot client update queued)
Files: `sim_server/src/snapshot.rs`, `sim_server/src/ws/`, `sim_server/src/http/`, `sim_server/src/app_state.rs`, `sim_server/src/control.rs`
- [x] SnapshotCache (DashMap) — tick loop writes, handlers read lock-free
- [x] axum 0.8 HTTP server on 127.0.0.1:8080 (BIND_ADDR env override)
- [x] HTTP: /api/health, /api/report, /api/ships, /api/markets, /api/facilities, /api/populations, /api/factions, /api/positions, /api/agent/:id
- [x] HTTP sim control: POST /api/sim/{pause,resume,speed}
- [x] WebSocket /ws with broadcast channel + per-client select loop
- [x] ServerMsg enum: server_hello, positions (every tick), ship_states (every 8 ticks), market_states (every 16 ticks), agent_state, sim_control_ack
- [x] ClientMsg: hello, get_agent, get_snapshot, move_observer, sim_control
- [x] Control channel (mpsc): HTTP/WS handlers → tick loop (pause/resume/speed/observer)
- **Verified** via scripts/ws-test.sh: all endpoints return correct JSON; pause/resume affects the running tick loop; market data rich and accurate.

Queued for next session (Godot-side):
- Update `client/scripts/autoload/network_manager.gd` to new plain-JSON protocol (drop Phoenix channel envelope)
- Godot reads `sim:ready` from stdout before connecting
- Test end-to-end connectivity with live game client

### Phase 6 — Facility + Population ✅ (MVP; faction tick deferred)
Files: `sim_core/src/economy/recipes.rs`, `sim_core/src/agents/facility.rs`, `sim_core/src/agents/population.rs`
- [x] 10 production recipes: refinery (smelt_metals, process_ice, crack_fuel, refine_polymers), factory (components/electronics/tools/medical/luxury), farm (food)
- [x] `recipes::execute` — limiting-factor scaling, rounds to viable output, caps at `max_batches`
- [x] `facility::tick_facilities` — runs recipes against local market supply; mining_rigs extract from body resources
- [x] `population::tick_populations` — consumes food/fuel from local market, produces labor commodity, updates food_satisfaction and sentiment
- [x] Engine wired: bodies → ships → supply-apply → facilities → populations → markets
- **Verified**: 40s smoke (WORLD_SPEED=4) shows avg ship credits rising 9427→13866 (+47%), max 20k→40k (doubled), 101 ships carrying cargo, ore price at earth hitting ceiling (ships respond by hauling). Full mining→refining→consumption chain active.
- 60 tests (+4 for recipe execution)

Deferred:
- Faction tick (reputation decay, treasury flow from faction-owned facilities) — small code, not critical for economy demo
- Contract board (pop-posted delivery contracts) — needs Phase 4.5 BT integration

### Phase 7 — Hardening + macOS/Linux validation ✅ (Windows build on Windows native)
- [x] Graceful shutdown: SIGINT/SIGTERM handlers stop the tick loop cleanly with 500ms grace
- [x] Per-tick timing metrics: tick_compute_us + total_us logged every 10s
- [x] Load validation: **~3 ms/tick at 800 agents**, 97% tick-budget headroom at default 125ms
- [x] Module-level docs on every major file (CLAUDE.md conventions enforced)
- [x] CLAUDE.md + README.md at project root for future sessions
- [ ] Windows native build: user will do on Windows when ready (mingw-w64 on Mac skipped)
- [ ] Ship lifecycle (broke strikes, hoard detection, recycling) — counters tracked, decommission logic deferred
- [ ] DB persistence worker — sim re-seeds from JSON on each boot today; needed for player saves

### Phase 8a — BT engine v2 + ship rewiring ✅
Files: `sim_core/src/ai/behavior_tree.rs`, `sim_core/src/agents/ship.rs`
- [x] `BtNode<A>` generic over action type (fixes fn-pointer-can't-capture problem). Tick takes a caller-supplied dispatch closure that matches on the action variant.
- [x] `ShipAction` enum with parameterized variants: Travel/Dock/Undock/Refuel/Buy/Sell/SellAll/AcceptContract/PickupCargo/DeliverCargo/Idle
- [x] `plan_goal` picks goal + BT; `build_refuel_bt`, `build_sell_cargo_bt`, `build_trade_run_bt` generate sequences
- [x] `execute_ship_action` dispatch closure integrates with ship components (Transit returns Running across ticks until arrival)
- [x] Removed old state machine (`sell_cargo_locally`, `buy_cargo_locally`, `begin_travel` — their logic now lives inside action variants)
- **Validated**: 30s smoke shows avg credits 9425 → 14784 (+57%, vs Phase 4's +47%), 164 ships carrying cargo, 61 tests passing. BT chains plans across ticks, no re-plan cost per tick.

## Session Log

| Date | Session | Work Done |
|---|---|---|
| 2026-04-19 | 1 | Architecture designed, workspace scaffolded, Phase 1 complete (35 tests) |
| 2026-04-20 | 2 | Pivoted to hecs ECS + command buffer pattern; Phase 2 complete (38 tests, binary boots and ticks with full world) |
| 2026-04-20 | 3 | Phase 3 complete: price engine, 8-phase market tick, prices move naturally under supply/demand; 47 tests |
| 2026-04-20 | 4 | Phase 4 MVP: ships observe markets, pick trade_run goals, travel & trade; avg credits +25% in 40s smoke; 56 tests |
| 2026-04-20 | 5 | Phase 5 server: axum HTTP + WebSocket, snapshot cache, all CRUD endpoints verified; Godot client update deferred to next session |
| 2026-04-20 | 6 | Phase 6: facility recipes (mining, smelting, manufacturing), population consumption/production, full economic loop — ship credits +47% in 40s smoke |
| 2026-04-20 | 7 | Phase 7: graceful SIGINT/SIGTERM shutdown, tick-time metrics (~3ms/tick at 800 agents), CLAUDE.md + README.md, module-level docs on every major file |
| 2026-04-20 | 8a | Phase 8a: BT engine v2 (generic over action type), ShipAction enum, dispatch closure pattern; avg credits +57% in 30s smoke |

## Cross-Compilation (Windows)

```bash
rustup target add x86_64-pc-windows-gnu
brew install mingw-w64
cargo build --release --target x86_64-pc-windows-gnu
```

Ship as zip: `simulator.exe` + `priv/data/` directory.
DB auto-created on first run next to the binary.

## Debug / Introspection

While running:
```bash
curl localhost:8080/api/health
curl localhost:8080/api/report | jq .
curl localhost:8080/api/agent/ship-artemis-7 | jq .
curl -X POST localhost:8080/api/sim/pause
```

Logging: `RUST_LOG=sim_core=debug,sim_server=info ./simulator`
