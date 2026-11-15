# Living Sector — N18 station administrators joined to actual paid N39 production (14 Nov 2026)

PR #249 / `integration/godot-phase2-unified-20261113`. All work is **SOURCE-INTEGRATED, NOT GODOT-RUNTIME-VERIFIED**, as explicitly required by the user until ALL Rust and other source parts have been transferred.

## Why this source block was needed
- Frozen Rust `native/crates/sim_core/src/strategy/station.rs::plan` runs after actual facility repairs/restock and before production, using a single per-(faction, location) administrator. It allocates full native crews based on owned source markets, source recipes/mining richness, current shortage history, actual household workforce, station payroll budgets, head priority and retained previous assignments.
- The Phase2 N39 facility worker/payroll loops existed, but its clean seed had `station_executing=false`, and the ported `station_administrator.gd` never assigned the `assigned_workers` that N39/N6 checks. This meant the existing production could not be called a faithful integration of Rust station-wide workforce decisions.

## Actual code connected
1. New `unified_native_station_administration_phase.gd` builds a deterministic source N18 station view FROM the one living N39 World and N9 balances. Distinct source stations are ordered, all existing facilities and their real native body resources are recorded; local market shortage history is read, not invented; existing N143/N155 recorded strategic commodity priority is optional. N39 paid worker receipts from that tick are counted as already occupied before assignment.
2. Real workforce cap is the sum of **floor(population_count×3/5) per cohort**, matching Rust `station.rs` (the N18 standalone port gains optional `workforce_limit` to receive that exact source capacity rather than rounding after summing cohorts).
3. Calls the already ported `station_administrator.gd::plan(..., executing=true)`, **not** `dispatch` or its detached `PaidProduction` wallet. Returns a pure assignment of zero/full required crew per active facility; never increases the available household population, warehouse stock or any account.
4. N39 `run_tick` invokes native N18 staffing only on the source 5×tick_multiplier work cadence, **after** actual N156 repair/N130 stock restock and **before** N39 source N6 recipe/mining payroll. Full assigned staff appear on the same real N39 facilities and are gated again by the original `Payroll.pay_shift`, which owns all wages and physical goods.
5. Source station memory `retained[facility_id]=previous assigned_workers>0` is reconstructed from the actual last N18 decision (matching Rust's preceding `StationView`); there is no second N18 production executor. N38 persists the entire original N18 planning memory in `station_administration`, its `station_administration_last_tick` cursor, plus `station_executing=true` on NEW seed only. Old saves without N18 remain in prior nonexecuting state; no labor or credit migration is invented.
6. N39 Schema validates owner/location/faction/cursors and actual station memory; restore forbids a cursor beyond real saved world tick. N158 N38 JSON loader normalizes the new legitimate numeric planning fields. One summary field exposes active N18 staffing observations and last original source interval.

## Still outstanding
- The source N100 HybridPlanner remains an already ported forecast/validation component. **It must not directly produce resources, grant money or dispatch a plan.** The next block should integrate N100's selected world-valid actions into existing N121/N134/N143/N153/native command pathways with proper native authorization, rather than invent its own executor.
- Full N155 Head/mandates and native autonomous retrofit goal selection, N147 passenger movement, colony navigation, dynamic colonization and other remaining Rust ECS are not yet fully attached.
- No one can yet claim the whole Rust engine has been transferred. User specifically requested **NO intermediate playtests, CI or balance changes**.

## Verification performed
Lightweight static source delimiter/string/import/indent inspection only; no GitHub Actions and no Godot runtime, per user. No authored test case claimed as proof of functioning game. Preserve existing N39/N9/N38 authorities and do NOT create alternative World/ledger/tick.
