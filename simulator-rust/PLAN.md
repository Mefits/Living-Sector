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

### Phase 4 — Ship Logic (largest)
Files: `sim_core/src/agents/ship.rs`, `sim_core/src/ai/considerations.rs`, `sim_core/src/spatial/`
- [ ] ShipState + full tick (crew, utility, BT execution)
- [ ] All consideration functions
- [ ] All goal behavior trees (trade_run, refuel, fulfill_contract, explore, rest_crew)
- [ ] All BT action functions
- [ ] Spatial LOD (chunk divisors, should_tick)
- [ ] Position interpolation (transit)
**Done when**: ships complete full trade loops, order books clear, prices move

### Phase 5 — WebSocket Server + Godot Client Update
Files: `sim_server/src/ws/`, `sim_server/src/http/`, `client/scripts/autoload/network_manager.gd`
- [ ] axum WS handler + broadcast channel
- [ ] Full JSON protocol (all message types)
- [ ] HTTP API endpoints
- [ ] Update Godot NetworkManager to new protocol
**Done when**: Godot connects, live positions + ship states stream correctly

### Phase 6 — Facility + Population + Faction
Files: `sim_core/src/agents/facility.rs`, `population.rs`, `faction.rs`
- [ ] Facility tick (recipes, mining, crew missions, docking)
- [ ] Population tick (food, sentiment, labor, contracts)
- [ ] Faction tick (reputation, treasury)
**Done when**: full supply chain loop runs end-to-end

### Phase 7 — Hardening + Windows
- [ ] Cross-compile to Windows (x86_64-pc-windows-gnu)
- [ ] Smoke test on Windows gaming PC
- [ ] Load test: <5ms tick time at 800 agents
- [ ] Graceful shutdown (DB flush, clean WS close)
- [ ] Ship lifecycle (broke strikes, hoard detection, recycling)

## Session Log

| Date | Session | Work Done |
|---|---|---|
| 2026-04-19 | 1 | Architecture designed, workspace scaffolded, Phase 1 complete (35 tests) |
| 2026-04-20 | 2 | Pivoted to hecs ECS + command buffer pattern; Phase 2 complete (38 tests, binary boots and ticks with full world) |
| 2026-04-20 | 3 | Phase 3 complete: price engine, 8-phase market tick, prices move naturally under supply/demand; 47 tests |

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
