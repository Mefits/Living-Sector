# PERF D handoff — 2026-11-16 21:26 MSK — N150 paid order compaction

- Code commit: `23801fc0b603797aa3edb1c71fb88db52f767758`
- Test commit: `a1e884f190e1f56a79c2fc7f5455c4d003a4bafc`
- Changed: `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`, new `godot/tests/p2_perf_d_n150_owned_order_compaction_20261116.gd`
- The actual paid `tick_one_market` deep-owns the market; `_retain_orders(..., true)` now compacts that already-owned array in-place, retaining stable order and rejecting malformed entries. Standalone `false` still returns detached nested copies. No changed order expiry, price, stock, RNG, cadence, N9, N39 or N38.
- Existing baseline (profiling enabled): market phase 39.43s per 300 paid ticks in 601–900 window (~131ms/tick); this change targets pending order list allocation/copy, but **its individual contribution has not been measured**.
- Test: **NOT RUN** (no Godot execution); **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**. No claims of acceleration or full parity. No CI launched.
- Next: run targeted test and same-seed early/late profile with site-level order counts and CPU time; confirm exact market DTO/price/stock, N9/N39/N38 restart and BT/RNG parity before accepting. If order list size is negligible, move D focus to measured N150 history/Head site.
