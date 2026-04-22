# CLAUDE.md

Context for Claude Code (claude.ai/code) when working in the `simulator-rust/` project.

## What this is

Rust port of an Elixir/Phoenix space-economy simulator. Drives a Godot client.
Replaces the Elixir original because BEAM's process scheduler performs poorly
on Windows gaming PCs. Ships at ~227 agents today, designed to scale to 100k+.
Single native binary, no runtime dependencies. See [`SESSION-HANDOFF.md`](./SESSION-HANDOFF.md)
for a fresh-session orientation and recent activity.

## Status

Phases 1–18L complete. Phase 18 is a long arc on **subsystems +
economy self-regulation**: ships got a 5-slot fitting (engine / cargo
bay / sensors / reactor / comms) via 18a, refit mechanics via 18b,
shipyards as module producers via 18c, agent-driven retrofit behaviour
via 18d, ship size tiers (Tiny..Massive) + cross-system contract gate
via 18f, size-driven speed penalty via 18g, facility subsystems
(production/automation) via 18e, personality-weighted plan_goal via
18i, contract payment age-escalation via 18j, a morale-zero death
spiral fix via 18k (multi-facility dock fallback, Rest timeout,
non-docked recovery bump), and dock-queue awareness + congestion-aware
rest planning via 18L. 155 tests passing, strict verify clean,
runtime p50 ≈ 1 ms / p99 ≈ 3 ms at 227 agents.

Earlier (Phases 1–17): spatial LOD for ships (observer-driven tick
gating), inter-system jump gates, full Elixir-parity behaviour:
populations post food + passenger contracts under stress, ships fulfill
them (docking with a fee, multi-tick unloading + refuel, shore-leave
for morale), facilities run recipes, degrade + self-repair, level up,
abandon when chronically broke. Factions tax + subsidise. Crew have
current_task + skills + hunger + morale. Bodies regen resources + biome
multipliers. State persists across restarts. See the **Systems wired**
table below.

## Architecture

```
Godot ⇄ WebSocket/HTTP (axum) ─┐
                                ├── sim_server (tokio, sqlx, axum)
                                │     ├── engine: tick loop driver + command apply +
                                │     │           LOD recompute + admin-spawn dispatch
                                │     ├── ws/handler: per-client select loop
                                │     ├── ws/protocol: ServerMsg / ClientMsg enums (wire truth)
                                │     ├── http/api: inspection + sim control + perf + observers
                                │     ├── http/admin: runtime ship/facility CRUD, supply delta, save-as
                                │     ├── snapshot: DashMap lock-free read cache
                                │     │             (ships, markets, facilities, pops, factions, contracts)
                                │     └── db: pool + seeder + ECS loader + persistence worker
                                │           (ships, markets, factions every tick;
                                │            facilities + pops every 16; bodies every 40)
                                │
                                └── sim_core (pure, no async)
                                      ├── agents/*: components + tick fns (hecs::World)
                                      │   ship, market, facility, population, celestial_body, faction
                                      ├── ai/*: BT<A> generic engine, utility scoring, considerations, personality
                                      ├── economy/*: commodities, order_book, price_engine,
                                      │              recipes, contracts, missions,
                                      │              module_production (Phase 18c)
                                      ├── modules/*: ship subsystem catalog (Phase 18a)
                                      ├── facility_modules/*: facility subsystem catalog (Phase 18e)
                                      ├── simulation/*: config (ShipClass, ShipSize),
                                      │                 spawner (AgentStore), commands (SimCommand),
                                      │                 lod (AgentLod tier table)
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
| Ship BT planner | `agents/ship::plan_goal` | Picks goal + builds `BtNode<ShipAction>`: rest_crew → refuel → sell_cargo → fulfill_delivery / passenger / courier → trade_run → idle |
| Ship BT execution | `agents/ship::execute_ship_action` | Dispatch closure for ShipAction variants. Dock emits `RequestDock`; Refuel is multi-tick (drains facility fuel reserves); SellAll unloads one commodity per tick |
| Dock dwell | `engine::apply_request_dock` / `apply_facility_refuel` | Docking fee = base × occupancy × (2 − condition). Refuel: 5 units/tick × 2 cr/unit from `FacilityStorage.reserves[Fuel]` |
| Market tick | `agents/market::tick_markets` | 8 phases: produce → consume → emergency orders → surplus orders → match → update-demand → track-shortage → update-prices |
| Price engine | `economy/price_engine` | Coverage model (supply as buffer, not ratio) + shortage urgency multiplier |
| Facility recipes | `agents/facility::tick_recipes_and_mining` | 10 recipes, limiting-factor scaling, `max_batches` scales with facility level. XP grants per recipe executed |
| Mining | same | `mining_rig` facilities extract commodities from their body's resources |
| Facility condition | `agents/facility::tick_degrade_condition` | Condition drops 0.0002/tick × tick_scale; self-repair uses 1 Tool for +0.01 condition when <0.8 |
| Facility restock | `agents/facility::tick_restock` | Buys fuel/food/tools/water from local market when reserves < 100, targets 500 |
| Facility autonomy | `agents/facility::tick_post_contracts` | Posts delivery contract when reserves low AND local market short 30+ ticks |
| Facility abandonment | `agents/facility::tick_abandonment` | 200-tick countdown when condition<0.1 + no tools + credits<100. Abandoned → tick phases skip, services cleared in snapshot |
| Facility leveling | `agents/facility::grant_facility_xp` | Level 1–10, threshold = level×100. Higher level scales recipe max_batches |
| Population | `agents/population::tick_populations` | Consume food/fuel, produce labor, sentiment inertia (0.9^tick_scale), urgency-scaled food bid (1×→3× at sat=0), emergency water <30, post passenger contracts when pop≥5000 + sentiment≥50 |
| Contracts | `economy/contracts::ContractBoard` | 6 kinds: Delivery / Courier / Passenger / Subsidy / Supply / CrewMission. Posted → Accepted → Paid lifecycle, `faction_id` tag for rep routing, expiry sweep |
| Factions — tax | `agents/faction::run_tax_cycle` | Every 200 base-ticks, 0.5% tax on facility credits above 1000-credit buffer |
| Factions — subsidy | `agents/faction::run_subsidy_cycle` | Every 30 base-ticks, posts subsidy contracts for chronic member-market shortages. Multiplier 1.25×–3.0× ramps with shortage age. Max 3 active per faction |
| Crew | `agents/ship::tick_crew` | Hunger / fatigue / morale f32; `current_task` derived (Piloting/Engineering/Trading/Eating/Resting/Idle); eats food from cargo when hungry; wages paid every 50 base-ticks or morale drops |
| Crew skills | `agents/ship::ShipCrewSkills` | nav/eng/trade/combat u8 capped 100; grants +1 on Buy, +1 nav/trade on Deliver, cumulative toward a skill XP ceiling |
| Reputation | `ShipEconomy.faction_reputation` | +1 per contract delivered to tagged faction (0–100) |
| Body regen | `agents/celestial_body::tick_bodies_regen` | Mined resources regrow toward `max_resources` at 0.0005 × tick_scale per regen-cycle |
| Body biome | `BodyBiome.food_multiplier` | Maps biome name → 0.1..=1.5 food-availability multiplier; consumed by growth logic |
| Persistence | `db/persistence::PersistenceWorker` | mpsc buffer + dedup + 5s batch flush. Ships every tick, markets every tick, factions on change, facilities/populations every 16 ticks, bodies every 40 ticks, tick counter every 8. Load tick counter on startup → sim resumes from the right tick. |
| Crew missions | `economy/missions` + `facility::tick_post_crew_missions` | 9 mission templates (port of Elixir `mission_catalog.ex`). Facility posts CrewMission kind (25% chance / cycle, 1 active max). Ship BT: `Dock → Refuel → Rest → Deliver → Undock`. Completion grants skill XP via `ShipCrewSkills::grant` |
| Contract rep gating | `ContractBoard::posted_for_ship` | Subsidy contracts start `min_reputation = 70` (faction-only), CrewMission starts 50 (allied), others 0 (public). Age-open decays 10 rep per 100 ticks → public after ~1000 ticks. Ship planner filters by `faction_reputation[fac] >= min_reputation` |
| Admin endpoints | `http::admin` | Full CRUD: **POST spawn** ships + facilities (INSERT + dispatch to engine), DELETE by id, market supply delta, save / save-as (VACUUM INTO) |
| Events broadcast | `engine` events Vec + `ws::protocol::Events` | ship_spawned, ship_docked, ship_decommissioned, facility_spawned, facility_removed, facility_abandoned, contract_delivered, crew_mission_completed, passengers_arrived, market_supply_adjusted — per-tick drain |
| Spatial LOD | `simulation::lod::AgentLod` + `engine::recompute_lod` | Observer-driven tiers 1/2/5/10/20/50. Ship tick phases gate on `active` map; fuel burn + crew hunger/fatigue scale by `skipped_ticks` so total state change over wall-clock matches. Recompute every 50 base-ticks. Markets never LOD'd. |
| Ship subsystems (18a) | `modules::CATALOG` + `ShipFitting` | 5 slots × 3 tiers (engine/cargo/sensors/reactor/comms). Tier-1 neutral. `ShipFitting::new_for_size` seeds size-aware defaults (size≥5 gets tier-2 sensors always; size=4 rolls 50% deterministic on ship id hash). Derived multipliers bake into `ShipCargo.capacity` + `ShipFuel.speed_modifier` at spawn/refit. |
| Ship refit (18b) | `http::admin::refit_ship` + `engine::admin_refit_ship` | `POST /api/admin/ships/:id/refit {slot, slug}` (admin override, no cost). Migration 003 persists `ships.fitting` as JSON; loader hydrates with fallback to tier-1 default. |
| Shipyards + module production (18c) | `economy::module_production` + `facility::tick_produce_modules` + `ModuleStock` | `facility_type = "shipyard"` mints modules from local market supply on a 15×mult cadence. 10 recipes (every non-tier-1 slug). Stock target 2/slug. Migration 004 persists `facilities.module_stock`. Admin refit with `via_shipyard: true` debits ship / credits yard / decrements stock. |
| Agent retrofit (18d) | `ShipProgression` + `find_retrofit_opportunity` + `SimCommand::RequestRefit` | Ships earn XP on delivery (15 xp each), level at `level × 100` threshold (cap 10), bank 1 retrofit point per level. Planner emits `seek_retrofit` when points>0 + credits>reserve + reachable shipyard with matching upgrade. BT: `DockAtShipyard → Dwell → Refit → Undock`. One point spent per install. Migration 005 persists progression. |
| Ship size (18f) | `simulation::config::ShipSize` + `ShipIdentity.size` | 6 tiers Tiny..Massive, orthogonal to class. Drives default sensor tier + sets up future speed/cargo differentiation. Class→default_size (courier=Small, freighter=Medium, tanker=Large, hauler=Huge, miner=Small). Migration 007. |
| Cross-system contract gate (18f) | `try_plan_contract` | Contracts spanning systems hidden from ships whose `sensor_range_au < 2.0`. Tier-1 sensors = intra-system only. Natural niche separation: big hulls with tier-2 default sensors see interstellar contracts day one. |
| Comms payment bump (18f) | engine `SimCommand::DeliverContract` apply | Delivered payment multiplied by `1.0 + ship.fitting.derived.comms_bonus`. Tier-2 comms = +5%, tier-3 = +10%. |
| Size speed penalty (18g) | `ShipSize::speed_multiplier` | Applied on top of `ShipClass.speed_modifier` + fitting at spawn. Tiny 1.15× → Massive 0.70×. Bigger = slower; amortises over larger cargo on long runs. |
| Facility subsystems (18e) | `facility_modules::FACILITY_CATALOG` + `FacilityFitting` | 2 slots × 3 tiers (production / automation). Production multiplies recipe output 1.0/1.15/1.30×; automation adds 0/1/2 flat batches to `level_scaled_max_batches`. Migration 006 persists. `POST /api/admin/facilities/:id/refit` (admin override only). |
| Personality planner (18i) | `plan_goal` + `score_goal` | Elective goal band (contract vs trade_run) scored by `ln(profit) × (1.0 + personality.prefer_goals[goal])`. Archetype `prefer_goals` entries (cautious_trader likes fulfill_delivery, aggressive_trader likes trade_run, courier likes passenger) now actually tilt the pick. Class→personality default via `Personality::for_class`. |
| Contract payment escalation (18j) | `ContractBoard::age_escalate_payment` | Posted contracts accrue +5% payment / 50 ticks, capped at +100%. Idempotent — recomputes from `initial_payment` each call. Hooked into population tick alongside `expire` + `age_open_reputation`. `FACILITY_DELIVERY_LIFESPAN_BASE` trimmed 500→300 so stale contracts churn + re-post at a fresh premium. |
| Rest timeout + non-docked recovery (18k) | `ShipAction::Rest` + `tick_crew` | `rest_start_tick: Option<u64>` on `ShipEconomy`. Rest succeeds on morale ≥ target OR after `MAX_REST_TICKS_BASE × mult = 300×` ticks. Non-docked `Resting` morale recovery bumped from 0.5× to 1.0× docked-baseline. Breaks the pin-at-zero death spiral when ships can't actually dock. |
| Multi-facility dock fallback (18k) | `apply_request_dock_typed` via `dockable_candidates_ordered` | When the primary (highest-cap) facility at a location is full, fall through to secondary / tertiary candidates. Haven-station's 5 facilities × 19 slots all get used now instead of 111 ships piling on the 8-slot station. |
| Dock queue awareness (18L) | `ShipAction::Dock` + `dock_attempt_start_tick` | Multi-tick: emit `RequestDock`, return Running until `docked_at` is set OR the context-dependent budget elapses. Has-contract = 150 base ticks (patient). Low morale + no contract = 30. Default = 60. On timeout, Failure → BT unwinds → planner replans. |
| Congestion-aware rest (18L) | `plan_goal` rest_crew branch + `pick_rest_destination` | `decide_and_act` builds per-tick `dock_congestion: HashMap<loc, (cap, docked)>` snapshot. When a ship's current location is saturated, `rest_crew` routes to the least-saturated same-system station instead of stampeding the current dock. |

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
  without a clear justification documented in the commit message.
- **Don't call `query_mut` while holding a `query_one` result** on
  another entity — hecs only allows one mutable iterator at a time.
- **Don't write directly to a component across entities** mid-phase. Use
  a `SimCommand` so the apply phase does it after the iteration.

## Protocol quick ref (Godot ↔ sim_server)

Plain JSON over WebSocket on port 8080. See
`crates/sim_server/src/ws/protocol.rs` — that's the canonical reference.

**Server → Godot** (pushed):
- `server_hello` — on connect, reports tick + running + `world_speed` + interval
- `positions` — every tick (125 ms). Entities include `type: "ship" | "body" | "facility"`
- `ship_states` — every 8 ticks (~1 s). Full ship snapshots (now include `crew.current_task`, `crew.skills`, `crew.hunger`)
- `market_states` — every 16 ticks (~2 s)
- `facility_states` — every 16 ticks. Carries `docked_ships`, reserves, `level`, `xp`, `abandoned`
- `population_states` — every 16 ticks. Pop count, sentiment, food satisfaction
- `faction_states` — every 32 ticks. Treasury + active subsidy count
- `contract_states` — every 32 ticks. Full contract board (6 kinds, status, min_reputation, faction_id, mission_category).
- `events` — every tick when non-empty. Mixed event stream (`ship_docked`, `contract_delivered`, `passengers_arrived`, `market_supply_adjusted`, `ship_spawned`, `facility_spawned`, `crew_mission_completed`, `ship_leveled_up` (18d), `ship_refitted` (18b/d), `facility_refitted` (18e), etc.)
- `agent_state` — reply to `get_agent` / `get_snapshot`
- `sim_control_ack` — reply to pause/resume/speed (echoes current `world_speed` + interval)

**Godot → Server**:
- `hello`, `get_agent`, `get_snapshot`, `move_observer`, `sim_control`

HTTP (same port, `/api/*`):
- Read: `/api/health` (+ `perf.tick_compute_p50_us` / `p99_us`), `/api/report`, `/api/{ships,markets,facilities,populations,factions,positions,contracts,observers}`, `/api/agent/:id`
- Control: `POST /api/sim/{pause,resume,speed,step}` — step takes `{ticks: u32}` and forces N ticks through even when paused
- Admin: `POST /api/admin/ships {class, faction_id, location, name?, credits?}`, `DELETE /api/admin/ships/:id`, `POST /api/admin/ships/:id/refit {slot, slug, via_shipyard?}` (18b/c), `POST /api/admin/ships/:id/grant-xp {amount}` (18d debug), `POST /api/admin/facilities {name, facility_type, body_id, faction_id, location?, docking_capacity?, credits?}`, `DELETE /api/admin/facilities/:id`, `POST /api/admin/facilities/:id/refit {slot, slug}` (18e), `POST /api/admin/markets/:loc/supply {deltas: {commodity: delta}}`, `POST /api/admin/save`, `POST /api/admin/save-as {name}`.

## Binary invocation (Godot subprocess scenario)

1. Godot runs `./simulator[.exe]` as a subprocess
2. Sim prints `sim:ready ws=ws://127.0.0.1:8080/ws http=http://127.0.0.1:8080/api tick=0` on stdout
3. Godot waits for that line, then connects
4. On SIGTERM / SIGINT, sim flips the running flag, persistence worker has up to
   1000 ms grace to flush the final batch, then process exits cleanly

For dev runs: `client/dev.env` has `SPACESIM_USE_EXISTING_SERVER=1` so the
Godot editor expects the Rust sim to already be running on port 8080. Just
`cargo run --bin simulator` in one terminal and open Godot in another.

## Godot inspector panels (client/scripts/ui/)

13 toggle-able panels, reachable from HUD buttons along the top:

| Panel | Script | Opens with | Role |
|---|---|---|---|
| Ship list | `ship_list.gd` | Ships button | Sortable table, click row → camera follows ship |
| Market overlay | `market_overlay.gd` | Market button | One row per market location, commodity cells + sparklines |
| Contract board | `contract_board.gd` | Contracts button | All 6 kinds filterable, sortable by age/payment |
| Faction ledger | `faction_ledger.gd` | Factions button | Treasury, active subsidies, ship/fac counts |
| Population browser | `population_browser.gd` | Pops button | Count / sentiment / food_sat sortable |
| Events ticker | `events_ticker.gd` | Events button | Rolling stream with kind filter, click → focus |
| Perf overlay | `perf_overlay.gd` | Perf button | p50/p99 tick µs, FPS, observed interval, LOD tier breakdown, 60-sample sparkline |
| Details panel | `details_panel.gd` | Click any ship/facility/body | Live state + "Recent activity" trail pulled from events ring |
| Minimap | `minimap.gd` | Always on | 3 systems + camera viewport indicator |
| God toolbar | `god_toolbar.gd` | Always on | Destroy toggle, +Ship, +Facility |
| Add ship panel | `add_ship_panel.gd` | God toolbar | Class / faction / location / credits → POST `/api/admin/ships` |
| Add facility panel | `add_facility_panel.gd` | God toolbar | Name / type / body / faction → POST `/api/admin/facilities` |
| Facility reserves editor | `facility_reserves_panel.gd` | Context menu → Edit Supply | Delta supply per commodity → POST `/api/admin/markets/:loc/supply` |

Plus the always-on HUD: tick / FPS / speed / ship count / observer /
save / save-as / step-debug (▸1, ▸8) buttons.

Theme palette in `client/scripts/ui/theme_palette.gd` — `PRIMARY` cyan
for info, `SUCCESS` green for good, `WARN` amber for caution, `DANGER`
red for crisis. Every panel should pull colours from there.

## Things intentionally left out (not critical)

- **Facility + population LOD rate-scaling** — Phase 15 wired ship LOD
  (where 75% of tick cost lives). Facilities + pops carry `AgentLod` so
  the perf HUD sees them, but their per-tick phases don't gate on it
  yet. Phase 16 candidate if a 10k-agent push shows them as a
  bottleneck. Recipe `max_batches` and sentiment-inertia math would
  need careful scaling.
- **Command trace / replay** — design idea: server keeps a ring buffer
  of every `SimCommand` per tick, `/api/debug/ship/:id/trace` returns
  the recent causal chain for that agent ("why did ship X go broke?"
  → see exactly which dock fees / buy costs / unpaid wages fired).
  Architecture already supports it — commands are plain data. Not
  built until we hit a specific "I wish I could rewind this" bug.
- **Rayon parallelism** — dependency is in, never called. Architecture
  is designed for it (no cross-ship writes within a phase). Skip until
  10k+ agents. Current 800-agent tick is ~0.5–2 ms.
- **Windows native build validation** — cross-compile setup exists
  (`rustup target add x86_64-pc-windows-gnu` + bundled SQLite so no
  DLL). User will test on their Windows box.
- **Per-crew-member simulation** — crew is aggregated on the ship.
  800 ships × avg 4 crew = 3200 individual entities we're NOT spawning,
  which was an explicit call. Individual variation is in the SQLite
  `crew_members` table for future richer missions. Skills + tasks live
  at aggregate level via `ShipCrew` + `ShipCrewSkills`.
