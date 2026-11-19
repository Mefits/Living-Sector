# PERF A — N15 fleet logistics validated publish, 17.11.2026

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

CODE: `d1b0d594e8d3df4442a2fe59bb680838a4cc6f1a`.
TEST: `7ecb36fd38015917f5ab00c961839db10692a5b2`.

Files: `godot/scripts/sim/phase1/n39_native_world_production.gd`, `godot/tests/p2_perf_a_n15_fleet_logistics_owned_publish.gd`.

N39 `apply_fleet_logistics` previously performed `_world = staged.duplicate(true)` after validating N15 undock/load/unload. Now authoritative root is copied shallowly, and only the four explicitly writable domains (`ships`, `markets`, `dock_receipts`, `cargo_receipts`) are detached deeply from the validated proposal. Other domains retain authoritative source values; caller-owned proposal aliases cannot enter the published mutable domains. Existing full Schema.validate, Schema.accounts/N9 check, receipt and write-set checks remain unchanged.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED. Test compares full-copy oracle, source immutability, proposal mutation isolation and negative shallow alias. No Godot runtime or CI executed in this iteration. No measured CPU benefit or late-tick parity claimed. Existing CI #43972442164 predates this change.

NEXT: run targeted N15 test, real N15 paid-tick and N38 restart parity; measure publish copy calls/time and CPU ms/paid tick early/late before claiming performance. Check remaining full-copy sites with profiler rather than optimizing rare paths. No changes to N9, N158 or C-owned ship code.
