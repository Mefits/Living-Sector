# Session Handoff — Fresh Claude Start Here

A one-pager so a new Claude session can pick up this project without
reading the full history. Read this first, then `CLAUDE.md`, then
anything else as you need it.

## Where we are

**Phases 1–18L shipped + a dock-capacity seed bump on top.** 155 tests
passing. Sim runs 227 agents (seed + 5 Phase-18h veterans) at p50 ≈ 1
ms / p99 ≈ 3 ms per tick. Full economic loop, per-faction rep-gated
contracts, observer-driven spatial LOD for ships, facility autonomy
with abandonment, admin CRUD including runtime spawn + refit, SQLite
persistence that round-trips ships / markets / factions / facilities /
populations / bodies / tick counter / **ship fitting / ship
progression / facility fitting / shipyard module stock** across
restart. Three systems (Sol / Alpha Centauri / Tau Ceti) connected by
6 inter-system gates; three shipyards (earth-station, haven-station,
anvil-depot) actually produce installable modules. Godot client has
the inspector panels plus size/tier labels + Subsystems / Progression /
Module Stock sections in the details panel.

## Phase 18 arc (the recent work)

A long sweep on **subsystems + economy self-regulation**. The shape
to keep in your head:

| Phase | Commit | What it does |
|---|---|---|
| 18a | `cea98a4` | Ship subsystem scaffold: `modules/` catalog (5 slots × 3 tiers), `ShipFitting` component, tier-1 defaults seeded on every ship. Gameplay-neutral at tier 1. |
| 18b | `400291c` | Refit mechanics. `POST /api/admin/ships/:id/refit`. Migration 003 persists `ships.fitting` JSON. |
| 18c | `7498330` | Shipyards + module economy. New `facility_type = "shipyard"`, `ModuleStock` component, 10 production recipes, refit-via-shipyard charges credits + consumes stock. Migration 004. |
| 18d | `97846d2` | Agent-driven retrofit. `ShipProgression { level, xp, retrofit_points }`, XP on delivery, banks 1 retrofit point per level-up, planner preempts `trade_run` with `seek_retrofit` when stocked + credited + reachable shipyard exists. Migration 005. |
| 18e | `63e637f` | Facility subsystems (Production + Automation), `facility_modules/` catalog, wired into `tick_recipes_and_mining`. Migration 006. |
| 18f | `bd32a66` | Ship size tiers (Tiny..Massive), cross-system contract gate via sensor range, comms payment bump. Migration 007. |
| 18g | `942e7f5` | Size-driven speed penalty (Tiny 1.15× → Massive 0.70×). Bigger = slower. |
| 18h | `aefab38` | Beef up seed JSONs: 5 veteran ships with levels + tier-2 fittings, 3 pre-stocked shipyards, advanced factories. |
| 18i | `b2faeee` | Personality-weighted `plan_goal`. `score_goal(profit, goal, personality)` picks between contract vs trade_run by archetype `prefer_goals`. `Personality::for_class` maps class→archetype. |
| 18j | `2ba4976` | Contract payment age-escalation. Stale Posted contracts accrue +5% / 50 ticks, cap +100%. Lifespan trimmed 500→300 for faster churn. |
| 18k | `ee5bf48` | Break the morale-0 death spiral: multi-facility dock fallback (haven-station's 5 facilities all get used), Rest action timeout + non-docked `Resting` recovery bump. |
| 18L | `14bc93c` | Dock-queue awareness. `Dock` is multi-tick with context-dependent wait budget (has-contract 150 / default 60 / low-morale 30 base ticks). Congestion-aware `rest_crew` picks the least-saturated same-system station. |
| chore | `69a6635` | Seed dock capacity bumps: AC 44→70, TC 59→87. `PLAN.md` retired in favour of this handoff. |

**Fleet signal at tick 1833 of an 18L smoke** (before the capacity
bump): 227 ships, 48 docked, 144 in transit, **35 stuck** (down from
130 at 18j), 65 morale-pinned-at-zero (down from 158). Goals
diversified: trade_run 78% / rest_crew 12% / delivery+passenger+
contract+retrofit the rest. Contract throughput 12 paid + 12
accepted + 250 expired. **After the capacity bump** (very early
sample at tick 827), stuck dropped further to 18 and docked rose to
31. A longer-burn review is a good next-session starting point.

## How to run it, today

```bash
# Terminal 1 — Rust sim
cd /Users/dclausen/code/spaceproject/simulator-rust
WORLD_SPEED=4.0 cargo run --bin simulator

# Terminal 2 — Godot (dev.env already has SPACESIM_USE_EXISTING_SERVER=1)
cd /Users/dclausen/code/spaceproject/client
godot project.godot
```

Or for a quick headless check:

```bash
cd simulator-rust
scripts/verify.sh --strict   # cargo check + test + clippy; 155 tests
scripts/smoke.sh 15          # boot 15 s with temp DB, print log tail
scripts/persist-test.sh      # confirm restart resumes from persisted tick
```

Default `WORLD_SPEED=0.25` is "chill play" pace (Earth↔Mars ≈ 4 min).
`4.0` is the smoke-test default — economy converges in tens of
seconds.

## Verification one-liners

```bash
# Full economy + regression sweep against a live sim (calls out
# stuck contracts, pinned prices, stranded ships, etc.)
#   /sim-review    (skill at simulator-rust/.claude/skills/sim-review)

# Direct API pokes
curl -s localhost:8080/api/health | jq '.perf'
curl -s localhost:8080/api/contracts | jq '.data | length'

# Phase-18 specific:
curl -s localhost:8080/api/ships | jq '.data[0].fitting'          # subsystems
curl -s localhost:8080/api/ships | jq '.data[0].progression'      # level/XP/RP
curl -s localhost:8080/api/ships | jq '[.data[].size] | group_by(.) | map({size:.[0], count:length})'
curl -s localhost:8080/api/facilities | jq '.data | map(select(.type == "shipyard")) | map({id, module_stock, credits})'

# Spawn + retrofit smoke:
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"class":"freighter","faction_id":"terran-authority","location":"earth-station","credits":50000}' \
  localhost:8080/api/admin/ships
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"amount":100}' \
  "localhost:8080/api/admin/ships/ship-admin-NN/grant-xp"
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"slot":"engine","slug":"engine_t2","via_shipyard":true}' \
  "localhost:8080/api/admin/ships/ship-admin-NN/refit"
```

## Open candidates (triage to taste)

1. **Longer-burn health check with capacity-bump** — run the sim
   for 5–10 minutes, confirm stuck-count trends toward zero, trade_run
   monoculture keeps breaking up. Then either celebrate or the next
   bottleneck surfaces.
2. **Price-engine upstream** — the 18j review flagged ~45% of price
   cells at ceiling with supply=0 scattered across ore/metals/components/
   polymers/tools/food. 18L's queue-awareness + the capacity bump
   might fix this indirectly (ships can finally dock + execute
   contracts → commodities move), but if not, the damping / coverage
   math might need a look. `economy/price_engine.rs`.
3. **Wire the `mine` goal** for real. Miners have the archetype but
   the mining BT doesn't exist — they fall back to trade/contracts
   like everyone else. Would be a natural extension of the agent
   BT work.
4. **Dock capacity in Sol** — Sol is at 146 slots / ~24% utilisation,
   looks fine, but worth watching as Sol gets busier with the
   retrofit / shipyard flows pulling ships in.
5. **Per-crew individual simulation** — still aggregated on the ship
   (`ShipCrew` + `ShipCrewSkills`). The `crew_members` table in
   SQLite is waiting for this whenever mission richness demands it.
6. **Facility + population LOD rate scaling** — components
   (`AgentLod`) attached but the tick phases don't gate yet. Not
   critical until ship count climbs past ~2k.
7. **Autonomous facility retrofit** — facilities have
   `FacilityLifecycle.level/xp` but no retrofit-point banking +
   spend-credits-on-modules behaviour yet. Mirror of the 18d ship
   retrofit arc.
8. **Windows native build validation** — cross-compile scaffolded
   (`rustup target add x86_64-pc-windows-gnu` + bundled SQLite).
   Waiting on a Windows box.
9. **Rayon parallelism** — dep is in, never called. Skip until 10k+
   agents.

## Watch-outs / gotchas

- **Monitor timeouts**: default 300s is probably too long for
  wait-on-tick loops. Use ~120 000 ms when you re-arm — user called
  this out mid-session.
- **`bash` sessions lose cwd** when you background a process. If you
  `cd` + `&` then the next Bash call, the backgrounded process still
  has the cwd but the SHELL call does not. Safer: `cd X && cargo run
  ... > log 2>&1 &` on one line, then `disown`.
- **Seeder writes empty `{}` defaults** for `fitting` / `progression` /
  `module_stock`. The loader's `parse_*` helpers handle this: empty
  JSON → class/size defaults. New in 18h: seed JSONs may also pass
  explicit values — the seeder stores them, loader parses them. Don't
  drop the fallbacks; they're how existing DB rows migrate forward.
- **`Dock` is multi-tick now** (18L). Returning `Running` is expected.
  Don't assume a single tick resolves a dock request.
- **`ShipEconomy` has ephemeral state**: `dock_dwell_start_tick`,
  `rest_start_tick`, `dock_attempt_start_tick`. Not persisted. Cleared
  by the action that set them on Success/Failure. If you add a
  similar "how long have I been doing X" timer, follow the same
  pattern.
- **The tick loop owns `hecs::World` exclusively.** HTTP / WS handlers
  read from `SnapshotCache` (DashMap), never touch the live world.
  Cross-entity state changes MUST go through `SimCommand` so they
  apply in a dedicated phase. Same-entity mutation is in-place and fine.
- **Ship LOD rate scaling depends on `skipped_ticks`.** If a ship
  hasn't fired for 10 real ticks and fires now, it burns 10× fuel in
  that one tick. If you add a new per-tick ship rate, multiply by
  `effective_scale = tick_scale × skipped_ticks`, not raw `tick_scale`.
- **Ships don't replan every tick.** `plan_goal` only fires when a
  ship's BT completes (`ai.current_bt.is_none()`). A trade_run BT is
  10+ actions long, so between replans a ship ignores newly-posted
  contracts. This is why economic rebalancing takes ~10+ game-minutes
  to settle, not seconds.
- **Recipe inputs come from market.supply, not facility reserves.** A
  refinery's `reserves[Ore]=2000` doesn't feed its recipe; the recipe
  eats from the market at that location. Ships SellAll at earth adds
  to earth market supply, which is what refineries consume.
- **`posted_for_ship` requires ship credits ≥ `buy_cost + gate_fees`.**
  If ships look broke + contracts look rich but acceptance is zero,
  the issue is usually `try_plan_contract` rejecting at the cost
  check. `compute_delivery_payment` scales with live source-market
  price specifically to prevent that.
- **Cross-system contract gate (18f)**: ships with
  `sensor_range_au < 2.0` never see contracts whose source+dest span
  different systems. Size≥5 ships spawn with tier-2 sensors (range
  2.0) by default; size-4 rolls 50% deterministically; smaller
  ships need a sensor retrofit. If you're debugging "why won't
  this ship take this contract?", check the fitting first.
- **Trail teleport detection in `ship.gd` uses a 3-unit threshold.**
  If someone shortens cross-system offsets further, the warp streak
  might not trigger on genuine gate jumps. Raise the threshold or
  check against a different signal (e.g. a `gate_jump` event).
- **Editing a `.gd` file can cascade.** Godot's scene loader fails
  hard on a parse error in one script and silently wedges unrelated
  panels. After editing GDScript, reload the project in the editor
  (Ctrl+Shift+T or restart).

## Critical files to read first

1. **`crates/sim_server/src/engine.rs`** — tick loop, command drain,
   LOD recompute, admin-spawn dispatch, event emit, persistence
   writes. One file to read to understand how everything hangs
   together. Grown a lot with the 18-series but still navigable.
2. **`crates/sim_core/src/agents/ship.rs`** — the biggest single
   file. Components + tick phases + BT actions + planner +
   personality scoring + retrofit opportunity finder + congestion-
   aware rest. Skim top-to-bottom at least once.
3. **`crates/sim_core/src/modules/mod.rs`** — ship subsystem catalog
   (18a). Small, self-contained, shows the `ModuleDef` + `Slot` +
   `combine_effects` pattern that `facility_modules/` mirrors.
4. **`crates/sim_core/src/economy/contracts.rs`** — `Contract` +
   `ContractBoard`, rep gating, age-open decay, and the new 18j
   payment age-escalation. Also the best demonstration of the
   seed-default shape for snake-case enum serialization.
5. **`crates/sim_server/src/ws/protocol.rs`** — wire format truth.
6. **`crates/sim_core/src/simulation/commands.rs`** — every cross-
   entity effect goes through here. Read the variants to know what
   the sim is capable of. Most recent additions: `RequestRefit`.
7. **`crates/sim_server/migrations/`** — seven migrations now. New
   columns: `ships.fitting` (003), `facilities.module_stock` (004),
   `ships.progression` (005), `facilities.fitting` (006),
   `ships.size` (007).
8. **`client/scripts/ui/details_panel.gd`** — how the Godot panel
   renders all the new Phase-18 fields (Progression, Subsystems,
   Module Stock, size tier next to class label).
9. **`client/CLAUDE.md`** — client-side orientation, still accurate
   except the "Rust sim is Phases 1–15" line.

## Next session's first move

Read this doc, then `CLAUDE.md`. If the user is mid-task, pick up
where they are. If not, a long-burn `/sim-review` is the natural
starting point: does the capacity bump + 18L queue-awareness finally
take the stuck-ship count to zero and loosen the trade_run
monoculture further? From there the economy opens up for the next
lever (price engine, `mine` goal, autonomous facility retrofit).
