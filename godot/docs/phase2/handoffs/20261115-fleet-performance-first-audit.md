# Living Sector P2 — autonomous fleet and phase CPU macroblock

**Date:** 2026-11-15. **PR:** [#249](https://github.com/Mefits/Living-Sector/pull/249). **Lease:** `20261115-fleet-performance-audit.json`.

## User goal and scope

Player/mandates are NOT required. The user on Windows observed no ships moving; planets orbited, FPS decayed from the first few simulation ticks but recovered immediately on Pause. The work here addresses real source autonomous shipment and bad CPU usage, not game balance.

## What was source-confirmed and changed

1. Native seed has **24 actual N39 ship entities** with N14 transit/cargo/credits/BT, but `star_system_view.gd` displays only docked/location triangular markers; `ship_batch_canvas.gd` is not wired to GUI; in-flight world coords are NOT projected. Never pretend the visual layer proves actual flights.
2. `unified_n80_ship_mining_stage.gd`: source N97 ice Mine *strictly* requires a real navigation waypoint `mine-<body_id>`. Old N103 candidate construction incorrectly accepted ordinary facilities/markets on an ice-rich body and looped rejecting `not_a_mining_waypoint`. Only select real mapped source mining waypoints; no synthetic deposits or added route edges.
3. `n39_native_world_production.gd::apply_native_n21_request`: when N21 source proposal returns `ok=false`, return that failure, not `n21_invalid_staged_source_world` from a failed attempt to commit the rejected proposal. No partial World publish.
4. **Critical N9 account parity:** `Schema.facility_account(id)` is `facility/<id>` (slash). Old N21 original dock and N97 refuel instead billed `facility:<id>` (colon). Fixed `unified_n21_dock_queue_stage.gd` and `unified_n97_ship_service_stage.gd`. Newly enabled physical dock advanced to N83 free trade at source tick 63; `unified_n83_free_trade_apply.gd` had the SAME wrong colon account in buy/sell and balance reconciliation. Fixed both source-paid directions. Do not change prices, stock, ship fuel or amounts.
5. **Performance, source behavior unchanged:** `n39_native_world_production.gd::ships_snapshot()` and `n158_production_runtime.gd::fleet_snapshot()` deep-copy only ships for GUI, not the entire large N39 World/ledger history. `main.gd::_on_tick_completed` renders observer/detail/status every 8 ticks rather than on every nonempty N9 receipt (which was effectively EVERY tick), and renders the system orbit on intermediate ticks without duplicating identical fleet snapshot and selection redrawing. Native tick cadence unaffected.
6. `n158_production_runtime.gd` N83/N103/N80 source planning now reuses a single isolated canonical World snapshot for **pure no-change proposal stages**; fetches a fresh snapshot immediately after any successful N39 Apply. The source decision/commit order, actual N146 authority, N9 money and N38 checkpoint remain unchanged. This optimization was authored after the first profiler run, and needs clean-seed CI comparison.
7. `n39_native_production_tick_runner.gd::profile_native_phases` and `n39_native_world_production.gd::world_copy_profile` are **opt-in** via `LS_PROFILE_NATIVE_PHASES=1`, not saved or used by game AI. `n158_production_runtime.gd::native_autonomy_diagnostics` and clean `p2_autonomous_world_observer_check.gd` record EVERY N153 acceptance/block and N84 actual departure rather than missing between sampled checkpoints.
8. New GUT source checks (`testing/gut/specs/test_n80_n21_source_guards.gd.txt`, `test_n21_paid_wallet.gd.txt`) assert real mine waypoint, N21 rejection reason, and paid N21 dock/true N9 ledger with the `facility/` key; no fake bank money.

## Real actual Godot evidence

- [CI 43653017588](https://github.com/Mefits/Living-Sector/actions/runs/43653017588): PASS 420 ticks, zero flights; N84 rejected `n97_service_not_a_mining_waypoint` 210 times; N21 refusal misreported as `n21_invalid_staged_source_world` 178 times. Native `ships` phase ~47.79s, `factions` 23.42s, `markets` 12.41s.
- [CI 43653597544](https://github.com/Mefits/Living-Sector/actions/runs/43653597544): PASS 8/8 GUT and 420 ticks after source N80/N21 fixes; **6 actual N14 departures**, zero confirmed N104 paid delivery. True N21 cause = `n9_original_dock_debit_rejected` ~932 counts, traced to wrong `facility:` account. 7,763 full `world_snapshot()` deep copies across 420 ticks, costing **27.83 seconds** in Linux headless profiling. Native ship phase 66.86s / factions26.43s, ~3.55 observed test TPS, not Windows FPS.
- [CI 43654010070](https://github.com/Mefits/Living-Sector/actions/runs/43654010070): GUT 9/9 PASS including fully paid N21 wallet; clean world then HALT at tick 63 with real N83 `n83_original_n9_invalid_account_or_delta`, due to identical `facility:` spelling in N83. Bug repaired; CI before fix is **FAIL, not a pass**.
- **New after N83 fix:** [CI 43654281125](https://github.com/Mefits/Living-Sector/actions/runs/43654281125) on commit `c4957a7b33a8ce8a1293e5f0e0d63d6b00a2e23b` — **pending outcome at time of draft**. Update result from actual Godot log before marking anything PASS.

## Required next evidence

- Final pinned smoke must pass native 420 without counterfeit money/shortcuts, with N9 N21/N83/N97 ledger parity, or report EXACT first genuine failure; do not claim completed N104 paid transport unless physically observed.
- Measure latest N39 full copy call/cost versus baseline 7763 / 27.83s, recognizing more native flight/trade work can change gross TPS.
- Android/Windows GUI not tested. Flight schematic markers still not full in-flight 2D objects; require a faithful renderer projection of N14 transit.position and current system geometry, rather than fake travel animations.
- Longer soak 1000/10000+ only after short clean seed and end-to-end paid freight pass. Avoid micro-PR proliferation or balance redesign.

**Current tested status before last CI:** real 6 N14 departures proved; paid N21 wallet proved by GUT; N83 paid free-trade account corrected but 420-tick runtime not yet verified.
