# PERF A — iterative protected graph traversal (2026-11-16 14:41 MSK)

CODE COMMIT: 408a423fba376d69b79140915f025d12ae5696d5
TEST COMMIT: ee1c86f9241bcef23f36a0afb07401f6a3ffd7b2

FILES:
- godot/scripts/sim/phase1/n39_market_owned_write_guard.gd
- godot/tests/p2_perf_a_deep_mutable_graph_check.gd

WHY: Replace recursive mutable-container graph walk with iterative pending stack, retaining identity-based deduplication and cross-graph alias detection. Deeply nested protected market metadata no longer consumes the GDScript call stack during traversal. Existing full Schema.validate remains authoritative. No production integration or balance changes.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. Godot 4.7.2 not invoked. No measured FPS/TPS benefit; this is a defensive bounded-stack change, not an acceleration claim.

NEXT: Run the new targeted Godot test plus existing p2_perf_a_market_owned_write_guard_check.gd, then measure protected guard overhead against full Schema oracle on representative N150 markets. Coordinate opt-in shadow wiring with D; do not replace production Schema guard.
