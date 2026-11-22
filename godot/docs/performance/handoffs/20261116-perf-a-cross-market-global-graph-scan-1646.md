# PERF A — bounded cross-market alias scan (16 Nov 2026)

CODE COMMIT: d32c604779b0644230df0cc9abc8e8b264e0f81e
TEST COMMITS: 2c690dc11b14204c3df2d5dd64abe54253efc22d, 41d68cc5fd58b44238af80b83dcfbe25b4feb9ec

FILES:
- godot/scripts/sim/phase1/n39_market_owned_write_guard.gd
- godot/tests/p2_perf_a_n39_cross_market_single_scan_20261116.gd

WHY: Cross-market alias detection previously called the recursive graph collector once per ordered pair of locations. Same-location checks already reject shared protected storage, so aggregating all protected old values and comparing once against all proposed market rows retains cross-location detection while avoiding O(markets²) repeated graph collection. Does not change authoritative N39, Schema.validate, TickRunner or production flags.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source review only. No measured runtime speedup or oracle parity claim. Test covers independent deep copies, cross-market protected-to-observation and protected-to-protected alias, and detached illegal stock change. No Actions triggered.

NEXT: Run this and existing p2_perf_a_* regressions with Godot parser; compare local guard vs full Schema oracle on valid N150 proposals and negative alias fixtures, measure per-call cost before opt-in shadow integration with D. Full N38 restart/420/900 gate remains pending.
