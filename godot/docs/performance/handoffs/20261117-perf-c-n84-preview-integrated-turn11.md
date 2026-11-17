# PERF C — N84 BeginTransit single-ship preview integration (17.11.2026)

CODE COMMIT: 8dbd057e978bb16ea0cc106934ac92823f22297d
TEST COMMIT: 2055808fbca509a9efbebe1fdc71abd4e0bb7484
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_preview_integration_oracle_20261117.gd

The real N84 BeginTransit proposal still called ShipPhase.depart(staged, ...) inside its ordered BT loop. That method restores/deep-copies the entire staged fleet on each proposed departure. It now calls existing ShipPhase.preview_depart() and replaces only the candidate's already-detached staged row, retaining all earlier ship BT cursor changes. N146/N39 authority, paid contract/cargo checks, tick cadence and deterministic ship order are untouched.

Targeted independent full-fleet oracle: 100 distinct ships, preserved earlier BT row, receipt/token equality, immutable source World, mutable-alias rejection, invalid destination negative cases. Existing p2_perf_c_n84_single_ship_transit_preview_oracle_20261117.gd also covers dock occupancy and stale token.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No runtime timing or same-seed paid tick comparison. Critical parity risk: preview_depart validates full fleet identity/transit/token but only ShipState.restore() on selected row, whereas full depart restores every row. Need full negative invalid-unrelated-ship schema oracle and N38 replay before acceptance; potentially gate preview on explicit opt-in if these diverge.

NEXT: run targeted Godot oracle, N38 restart, same-seed tick100/600/900 with source-site timing N84 BeginTransit count, full-fleet restore time, ships+dock ms/paid tick p95; compare before/after. Do not attribute aggregate acceleration without measurements. Do not touch N9/N39/N158 or repeat 99ab25e9/1676db61.
