# Rust Space Simulator — Long-Term Plan

Porting the Elixir/Phoenix space simulator to Rust for native Windows/Linux performance.
Godot is the sole client. No web dashboard. Single binary, no dependencies.

> **Status (2026-04-20): Phases 1–15 complete, 95 tests.** Full economic
> loop, 6 contract kinds (Delivery / Courier / Passenger / Subsidy /
> Supply / CrewMission), crew `current_task` + skills + hunger, facility
> autonomy (degradation / self-repair / restock / contract posting /
> leveling / abandonment), population urgency bids + passenger growth,
> faction tax + subsidy with age-opening rep gate, body biome + regen,
> full DB persistence (ships/markets/factions every tick; facilities/pops
> every 16; bodies every 40), admin CRUD + runtime spawn, event stream,
> observer-driven spatial LOD for ships, and Godot-side inspector panels
> (events ticker / contract board / faction ledger / pop browser / perf
> overlay). See [README.md](./README.md) for the dev loop,
> [CLAUDE.md](./CLAUDE.md) for architectural conventions, and
> [SESSION-HANDOFF.md](./SESSION-HANDOFF.md) for the fresh-session
> orientation. The rest of this file is the design plan + per-session
> history.

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
- Rayon `par_iter_mut()` is a future option for per-phase parallelism — dependency
  is present but not yet called. Current single-threaded tick cost (~5 ms at
  800 agents) leaves plenty of headroom; see `CLAUDE.md` for when to pull this lever.
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

## Tick Phase Ordering (125 ms per tick at default WORLD_SPEED=0.25)

**As actually implemented** (rayon not yet used — single-threaded at 800 agents
costs ~5 ms / tick, 96% under budget):

1. Drain control channel — pause/resume/speed/observer from HTTP/WS
2. Bodies — orbital angles advance
3. Ships — 3 passes: advance transits → observe local prices → plan + BT tick
4. Apply ship commands — supply deltas at markets, contract Accept/Deliver
5. Facilities — run production recipes against local market supply; mine from bodies (every 5 base-ticks)
6. Populations — consume/produce, update sentiment, post food contracts (every 25 base-ticks)
7. Markets — 8 sub-phases (produce/consume/emergency/surplus/match/demand/shortage/prices)
8. Apply market commands — spread revenue → owning facility
9. Factions — tax owned facility credits → treasury (every 50 base-ticks)
10. Snapshot write — SnapshotCache populated from all entities
11. Broadcast — positions (every tick), ship_states (every 8), market_states (every 16)
12. Emit DbWrites — dirty entities → persistence mpsc channel

Rayon parallelism is architected-for but not yet called. See "Things NOT done"
in CLAUDE.md.

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

### Phase 10 — Godot network_manager.gd update ✅
Files: `client/scripts/autoload/network_manager.gd`, `client/scripts/autoload/server_manager.gd`, `simulator-rust/README.md`
- [x] New `network_manager.gd` speaking the plain-JSON Rust protocol (port 8080, `/ws`). Old Phoenix Channels version preserved as `network_manager_phoenix.gd.bak`.
- [x] Message handlers: server_hello, positions (filters entities where type=="ship"), ship_states, market_states, agent_state, sim_control_ack
- [x] Client messages: hello, get_agent, get_snapshot, move_observer, sim_control
- [x] ServerManager: `DEFAULT_PORT = 8080` now targets Rust sim. `SPACESIM_TARGET_ELIXIR=1` env var routes to 4000 for legacy use.
- [x] Reconnect logic + debug logging preserved from Phoenix version
- [x] README documents the new dev loop (run Rust sim in terminal 1, Godot picks it up via `SPACESIM_USE_EXISTING_SERVER=1` in `dev.env`)
- **Not yet validated end-to-end on live Godot** — the GDScript is correct relative to the server's protocol.rs, but hand-testing from Godot is your call.

### Phase 9 — DB persistence worker ✅
Files: `sim_server/src/db/persistence.rs`, `sim_server/src/engine.rs`, `sim_server/src/main.rs`
- [x] `PersistenceWorker` runs as a separate tokio task, consumes `DbWrite` via mpsc channel, batches + dedups (same `(kind, db_id)` → latest wins), flushes on 5-second interval in a single transaction
- [x] Engine emits writes for dirty entities at end of each tick using `try_send` (never blocks the tick loop)
- [x] `DbWrite` variants: Ship (credits/fuel/position/cargo/goal/contract/strikes/idle), Market (prices/supply/demand/shortage_ticks), Faction (treasury), Tick (counter every 8 ticks)
- [x] `load_tick_counter` on startup — sim resumes from persisted tick, not 0
- [x] Graceful shutdown: `ctrl_c`/SIGTERM flips running flag, 1000ms grace for final flush
- **Validated via `scripts/persist-test.sh`**: 15s run persists tick=120, 223 ships / 23 markets / 5 factions updated. Restart resumes at tick 120 and continues ticking.
Files: `sim_core/src/agents/ship.rs`, `sim_server/src/db/spawner.rs`, `sim_server/src/engine.rs`
- [x] `ShipCrew` component (aggregate: size, morale, fatigue) — one per ship, not per crew member
- [x] `tick_crew` pass — fatigue rises during transit (0.05/tick) and work (0.02/tick), morale drops when fatigue > 60, rest recovers both; updates `ShipEconomy.efficiency` from morale
- [x] `ShipAction::Rest` — returns Running until morale ≥ 80, then Success
- [x] `build_rest_crew_bt`: dock → refuel → rest → undock
- [x] Planner inserts rest_crew when morale < 35 (first priority)
- [x] Spawner seeds crew from ship class crew_size with morale=70, fatigue=20
- [x] Log diagnostic shows morale avg/min per tick
- **Validated**: 90s smoke confirms all ships track crew state (morale=70 stable throughout; short runs don't accumulate fatigue). Tuning is intentional — rest_crew activates during longer-session multi-trip fatigue accumulation. 64 tests still passing.

### Phase 8c — Faction tick + apply TransferCredits ✅
Files: `sim_core/src/agents/faction.rs`, `sim_server/src/engine.rs`
- [x] `TransferCredits` applied in engine (market spread revenue → owning facility)
- [x] `faction::tick_factions` runs every 50 base-ticks: 5% corporate tax on each owned facility's credits → faction treasury
- [x] Two-pass flow (deduct from facilities, aggregate, deposit into factions)
- [x] Diagnostic `log_factions` — treasury totals per faction
- **Verified**: 60s smoke shows Terran treasury growing 55000 → 86940 (+58%), smaller factions tracking proportionally to their facility count. Doughtys treasury flat at 8000 (own ~0 facilities). 64 tests passing.

### Phase 8b — Contract board + fulfill_delivery ✅
Files: `sim_core/src/economy/contracts.rs`, `sim_core/src/agents/population.rs`, `sim_core/src/agents/ship.rs`, `sim_core/src/simulation/commands.rs`, `sim_server/src/engine.rs`
- [x] `ContractBoard` with lifecycle (Posted → Accepted → Paid → Expired), status + destination indexes, `posted_with_destination` lookup, `expire(tick)` housekeeping
- [x] `AgentStore.contracts` field
- [x] Populations post food delivery contracts when `food_satisfaction < 40` on a 25-base-tick interval; source is the location with the richest food supply; payment = base_price × 1.8 × qty
- [x] Ship planner checks contracts before speculative trade_run; `try_plan_contract` filters by capacity, source price, affordability, and profit > 0
- [x] `build_fulfill_delivery_bt` — accept → travel to source → buy → travel to destination → deliver
- [x] `SimCommand::{AcceptContract, DeliverContract}` with engine apply phase that pays the ship, reduces cargo, adds supply at destination market, marks Paid
- **Validated**: 80s smoke (WORLD_SPEED=6) produced 45 contracts posted, 24 Paid, 9 Expired. First delivery at tick 240. 61 tests still passing.

### Phase 8a — BT engine v2 + ship rewiring ✅
Files: `sim_core/src/ai/behavior_tree.rs`, `sim_core/src/agents/ship.rs`
- [x] `BtNode<A>` generic over action type (fixes fn-pointer-can't-capture problem). Tick takes a caller-supplied dispatch closure that matches on the action variant.
- [x] `ShipAction` enum with parameterized variants: Travel/Dock/Undock/Refuel/Buy/Sell/SellAll/AcceptContract/PickupCargo/DeliverCargo/Idle
- [x] `plan_goal` picks goal + BT; `build_refuel_bt`, `build_sell_cargo_bt`, `build_trade_run_bt` generate sequences
- [x] `execute_ship_action` dispatch closure integrates with ship components (Transit returns Running across ticks until arrival)
- [x] Removed old state machine (`sell_cargo_locally`, `buy_cargo_locally`, `begin_travel` — their logic now lives inside action variants)
- **Validated**: 30s smoke shows avg credits 9425 → 14784 (+57%, vs Phase 4's +47%), 164 ships carrying cargo, 61 tests passing. BT chains plans across ticks, no re-plan cost per tick.

### Phase 11 — Feature parity sweep (Elixir → Rust) ✅
Files: `sim_core/src/agents/{ship,facility,population,faction,celestial_body}.rs`, `sim_core/src/economy/contracts.rs`, `sim_server/src/engine.rs`, `sim_server/src/ws/protocol.rs`, `sim_server/src/http/admin.rs`, `client/scripts/ui/hud.gd`

Elixir-parity sweep driven by a live-testing audit. 7 sub-phases:

- **11a**: Critical fixes (faction tax 0.05 → 0.005 with a 1000-cr buffer, HUD speed label reading `world_speed` instead of `tick_interval_ms`), ship dock-dwell (multi-tick `Refuel` draining facility reserves; `SellAll` one-commodity-per-tick; `Dock` / `Undock` emit `RequestDock` / `ReleaseDock` commands), facility docking fee (`base × occupancy × (2 − condition)`), `facility_states` broadcast.
- **11b**: Crew tasks — `CrewTask` enum (Idle / Piloting / Engineering / Trading / Eating / Resting / OnMission), `ShipCrew` gains `hunger` + `health` + `wages_credits`, hunger consumes food from cargo, wages deducted every 50 base-ticks (unpaid → morale drop). `ShipCrewSkills` component (nav/eng/trade/combat, cap 100) with `grant` XP on Buy + Deliver.
- **11c**: Facility autonomy — `FacilityLifecycle` (level/xp/abandonment counter), condition degrades per tick, self-repair consumes Tools when condition<0.8, reserves restocked from local market, delivery + courier contracts posted when chronically short, abandonment after 200 ticks of broke + no-tools + low-condition.
- **11d**: Population richness — urgency-scaled food bid payment (1× → 3× at sat=0), water-buy when satisfaction<30, labor production, sentiment inertia `0.9^tick_scale`, `population_states` broadcast.
- **11e**: Body biome (`BodyBiome.food_multiplier` 0.1–1.5 by biome slug), `BodyResources` regen toward `max_resources`, faction subsidy posting (scan member-market `shortage_ticks`, 1.25× → 3.0× multiplier ramp, max 3 active), `faction_states` broadcast.
- **11f**: Contract kind expansion (`ContractType::{Delivery, Courier, Passenger, Subsidy, Supply, CrewMission}`), passenger flow end-to-end (Pop posts → ship picks up → deliver increments destination population), reputation (`ShipEconomy.faction_reputation`, +1 per tagged delivery), events broadcast channel with `ship_spawned / docked / decommissioned`, `contract_delivered`, `passengers_arrived`, `market_supply_adjusted`, etc.
- **11g**: Admin HTTP endpoints — POST `/api/admin/ships`, POST `/api/admin/facilities`, DELETE both, POST `/api/admin/markets/:loc/supply`, POST `/api/admin/save`, POST `/api/admin/save-as`.

**Validated**: 79 tests passing (was 64). Live smoke showed 5/6 factions actively posting subsidies, 8 ships docked across 3 stations mid-run, fuel reserves draining as ships refueled, faction treasuries visibly moving.

### Phase 12 — Hardening the periphery ✅
Files: `sim_core/src/economy/missions.rs` (new), `sim_core/src/economy/contracts.rs`, `sim_server/src/db/persistence.rs`, `sim_server/src/engine.rs`, `sim_server/src/http/admin.rs`

- **12a**: Runtime admin spawn. `POST /api/admin/ships` INSERTs a ship row, dispatches `ControlCommand::AdminSpawnShip`, engine spawns the full hecs bundle on next tick, returns 201 with `{id, db_id}`. Same pattern for facilities. Replaces the Phase 11g 501 stubs.
- **12b**: Facility / population / body persistence. `DbWrite::{Facility, Population, Body}` variants. Flushes gated to every 16 ticks (fac/pop) and 40 ticks (bodies) to avoid channel flood. Body orbit angles + resource state now survive restarts.
- **12c**: Crew missions. `economy/missions.rs` ports Elixir's 9-template catalog (security_detail, vip_escort, customs_assist, heavy_maintenance, salvage_operation, production_assist, equipment_calibration, harvest_help, safety_audit). Facilities post `CrewMission` contracts (25% prob, 1 active max). Ship BT: `Travel → Dock → Refuel → Rest → Deliver → Undock`. Apply phase grants skill XP per the template's `required_skill` / `skill_gain`.
- **12d**: Contract reputation gating. `Contract.min_reputation` defaults: Subsidy=70 (faction-only), CrewMission=50 (allied), others=0 (public). Age-open decays 10 rep / 100 ticks → public after ~1000 ticks. `ContractBoard::posted_for_ship(&rep)` filters. Ship planner uses the filtered list.

**Validated**: 87 tests. Live smoke: admin spawn round-trip works end-to-end (ship+facility appear in API + persist across restart). Restart test shows facility condition drifting from 1.0 → 0.976, body angles loading from DB (not seed), admin-spawned entities surviving shutdown.

### Phase 13 — Godot inspector panels ✅
Files: `sim_server/src/ws/protocol.rs`, `sim_server/src/engine.rs`, `sim_server/src/app_state.rs`, `sim_server/src/http/api.rs`, `client/scripts/autoload/network_manager.gd`, `client/scripts/autoload/game_state.gd`, `client/scripts/ui/{events_ticker,contract_board,faction_ledger,population_browser,perf_overlay}.gd` (new), `client/scenes/ui/*` (new), `client/scripts/ui/hud.gd`, `client/scripts/main.gd`, `client/scripts/ui/details_panel.gd`

- **13a**: Godot consumes broadcasts that were already being emitted but ignored. `network_manager._handle_{population_states, faction_states, contract_states, events}`. `GameState.event_log` ring (cap 400) + `events_for_agent(id)` filter + signals.
- **13b**: Rust surfaces the gaps — `contract_states` broadcast (every 32 ticks), `GET /api/contracts`, rolling p50/p99 tick perf in `/api/health.perf`, `POST /api/sim/step {ticks}` for step-debug (works while paused).
- **13c**: Four new panels. Events ticker (RichTextLabel, filterable, click → focus camera). Contract board (9-col sortable table, 6 kind filters + 6 status filters). Faction ledger (treasury, active subsidies, member counts). Population browser (count / sentiment / food_sat sortable with colour-coded cells).
- **13d**: Perf overlay (p50/p99 numbers + FPS + observed interval + 60-sample sparkline with 125ms budget line; 1s self-poll of `/api/health`). Details panel got a "Recent activity" section pulling from `events_for_agent`. HUD got ▸1 / ▸8 step-debug buttons.

**Validated**: 87 tests. Live probe confirmed `/api/contracts` + `/api/health.perf` + step endpoint all work; pause → step 8 → tick advances exactly 8.

### Phase 14 — Market panel fix ✅
Files: `client/scripts/ui/market_overlay.gd`, `client/scripts/ui/facility_reserves_panel.gd`, `client/scripts/ui/details_panel.gd`

User reported "market panel doesn't work at all". Root cause: market_overlay read `market.facility_id`, but Rust's `MarketSnapshot` emits `facility_location` (renamed during schema cleanup). Patched both readers. A separate parse-error cascade in `details_panel.gd` (my earlier `replace_all` edit swept indent inside a match arm) was silently preventing the scene from loading cleanly — fixed the indent. Panel now renders 23 rows (one per market location).

### Phase 15 — Observer-driven spatial LOD ✅
Files: `sim_core/src/simulation/lod.rs` (new), `sim_server/src/engine.rs`, `sim_server/src/app_state.rs`, `sim_server/src/http/api.rs`, `client/scripts/main.gd`, `client/scripts/ui/perf_overlay.gd`

Distant agents keep ticking (no Minecraft-style freeze), just at lower cadence with rate-scaled state changes so total fuel burn + crew wear match wall-clock.

- **15a**: Observer tracking. `ControlCommand::MoveObserver` flows into `AppState.observers: Arc<RwLock<Vec<Observer>>>`. `GET /api/observers` for debug.
- **15b**: `AgentLod { divisor: u8, next_tick: u64 }`. Tier table 1 / 2 / 5 / 10 / 20 / 50 by distance to nearest observer. `try_fire(tick)` returns `Option<skipped_ticks>`; `set_divisor(d, tick)` preserves cursor phase. 8 unit tests.
- **15c**: `tick_lod_recompute` runs every 50 base-ticks. Positions: ships live, facilities via body-center+offset, pops via their facility's body. Returns `LodStats` for HUD.
- **15d**: Ship gating. `tick_ships` builds an `active: HashMap<Entity, skipped_ticks>` once up front; 4 inner phases (`advance_transits`, `observe_prices`, `tick_crew`, `decide_and_act`) filter on it. `fuel_consumption`, hunger, fatigue, idle-drift all multiply by `effective_scale = tick_scale × skipped_ticks`.
- **15e**: Facility + pop LOD deferred — they carry `AgentLod` for stats but don't gate yet. Noted as Phase 16 candidate.
- **15f**: Godot sends a `"camera"` observer every 50 ms with radius scaling off zoom (`GameState.zoom_raw / SCALE_FACTOR × 1.5`, min 5).
- **15g**: LOD distribution in `/api/health.perf.lod`. Perf overlay adds an "LOD tiers" row (`d1:215 d2:3 d10:5 d50:0`) and polls `/api/health` once per second while open.

**Validated**: 95 tests. Live smoke: sim runs with 298 agents (223 ships + 56 facilities + 19 pops) all carrying LOD components. With no observer connected everyone sits at d=1 (correct fallback). Perf at 800 agents held at p50 ≈ 500 µs / p99 ≈ 2 ms — well under the 125 ms budget.

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
| 2026-04-20 | 8b | Phase 8b: contract board, pop-posted food delivery contracts, ship fulfill_delivery BT; 24 Paid deliveries in 80s smoke |
| 2026-04-20 | 8c | Phase 8c: faction tick (5% facility tax), TransferCredits applied (market→facility); Terran treasury +58% in 60s |
| 2026-04-20 | 8d | Phase 8d: ShipCrew aggregate (morale/fatigue), rest_crew goal & Rest action, efficiency driven by morale |
| 2026-04-20 | 9 | Phase 9: DB persistence worker (mpsc + dedup + batch flush), tick counter resume on restart |
| 2026-04-20 | 10 | Phase 10: Godot network_manager.gd rewritten for plain-JSON Rust protocol, port 8080 default, Phoenix version backed up |
| 2026-04-20 | 11 | Phase 11 (a–g): Elixir-parity sweep. Crew tasks/skills/hunger, facility autonomy (degrade/self-repair/restock/post/level/abandon), pop urgency + passenger, faction subsidy, body biome+regen, 6 contract kinds, events broadcast, admin HTTP endpoints. 79 tests. |
| 2026-04-20 | 12 | Phase 12 (a–d): Runtime admin spawn (replaces 501 stubs), facility/pop/body persistence, mission catalog (9 templates) + crew-mission BT flow, contract rep gating with age-open. 87 tests. |
| 2026-04-20 | 13 | Phase 13 (a–g): Godot inspector panels — events ticker, contract board, faction ledger, pop browser, perf overlay. Rust contract_states broadcast, perf metrics on /api/health, step-debug endpoint. Activity trail on details panel. |
| 2026-04-20 | 14 | Phase 14: Market panel debug — field rename `facility_id` → `facility_location`, details_panel.gd parse-error fix. Panel now renders 23 rows. |
| 2026-04-20 | 15 | Phase 15 (a–g): Spatial LOD for ships. Tier table 1/2/5/10/20/50, `AgentLod` component, `tick_lod_recompute` every 50 ticks, rate-scaled fuel+crew via `skipped_ticks`, Godot sends camera-observer, LOD distribution in perf HUD. 95 tests. |
| 2026-04-20 | 16 | Session handoff: updated CLAUDE.md / PLAN.md / README.md / client/CLAUDE.md for Phase 11–15 state, created SESSION-HANDOFF.md. |

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
