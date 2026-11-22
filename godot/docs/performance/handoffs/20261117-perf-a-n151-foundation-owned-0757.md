# PERF A — 2026-11-17 — N151 founding approval L2232

Branch: `integration/perf-astra-5-workers-20261116`, PR #262. No merge.

Code: `2dce367a6be3da6171bf67a6e48c017a06c2ef28`
Test: `e3c85495384d49c30cdbab02a80ecbb9da1112fd`

Changed `godot/scripts/sim/phase1/n39_native_world_production.gd`: `apply_native_colony_foundation` now stages a shallow World root and deep copies only `construction_sites` and `construction_receipts`, the two domains written by the approved-site transaction. The proposal site is separately detached. Original N9 snapshot and full Schema validation/accounts checks remain. No N158/N9/C/D/E files changed.

Added `godot/tests/p2_perf_a_n151_foundation_owned_stage.gd`: full deep-copy structural oracle, rejected-stage nested isolation, proposal isolation, negative shallow alias fixture. This is a targeted copy-ownership test, not a live production-path or Schema execution test.

Status: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No runtime or CI executed; CPU gain and long-run parity not measured. Potentially saves one full World deep copy per successful colony approval, but frequency may be low and it does not prove reduction of the main late-tick slowdown.

Next: run targeted test with Godot, verify production N151 full Schema/N9/receipt parity, measure actual L2232 call count and prioritize higher-frequency remaining N39 full-copy write stages. E should own a bounded same-seed early/late checkpoint including N38 restart and full economy/cargo parity.
