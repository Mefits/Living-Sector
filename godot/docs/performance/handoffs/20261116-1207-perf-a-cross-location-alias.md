# PERF A — cross-location protected market alias (2026-11-16 12:07 MSK)

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262. Frozen Rust 0.6.7 remains authoritative.

- CODE COMMIT: `4b9d6f36a3f35154872aa0d647adbcc6f2083593`
- TEST COMMIT: `a6c16563a616bb9fd7bd8e2992b839c756d521a6`
- Files: `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`, `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`.
- Added cross-location alias rejection: a protected mutable N39 market value must not be shared with a different market's observation/protected fields. Previously only same-location row aliases were compared. Test covers two leak directions, independent detached valid baseline, and detached illegal mutation.
- No production wiring, no changes to N158/N9/SaveState/Schema oracle; existing validation remains authoritative. Performance benefit: **NOT MEASURED**. Additional shadow-only comparison may increase diagnostic overhead.
- TEST EXECUTED: **NOT RUN** (Godot runtime unavailable in this connector-only pass). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source-only review: existing Guard/Observation preloads and method signatures verified.
- NEXT: run `p2_perf_a_market_owned_write_guard_check.gd` under Godot 4.7.2; benchmark shadow validator on 24/100/500 markets and compare against full Schema oracle; coordinate with D before any N150 production shadow hook.
