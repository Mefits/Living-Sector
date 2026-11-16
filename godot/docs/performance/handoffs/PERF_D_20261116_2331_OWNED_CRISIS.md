# PERF D — paid N150 crisis-history deep-copy removal (2026-11-16 23:31 MSK)

CODE COMMITS: e026c309d1c5bb2c30670fe2a73dbaf48a4c1cba, a012d091cfa5454360f8cf7b9d72cd0c7c5ef3d6
TEST COMMIT: 98c5a98faf4c46844908de7000385b9ce4f3f4d0

FILES: godot/scripts/sim/phase2/unified_native_crisis_events.gd; godot/scripts/sim/phase2/unified_market_phase.gd; godot/tests/p2_perf_d_crisis_owned_history_20261116.gd.

WHY: The paid market proposal already receives a detached deep-owned N150 market; crisis staging previously duplicated the entire growing MarketHistory again, including trend_samples. A new optional already_owned parameter preserves the original detached public behavior for other callers and reuses N150-owned history only in unified_market_phase. Market prices, shortage thresholds, source event order, stock, N9, N39, N38, BT/RNG and cadence unchanged. The source World remains detached because N150 tick_one_market deep-duplicates the input before the call.

TEST: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Targeted oracle compares legacy vs owned event ordering, nested mutation isolation, invalid flags/counters, absent flags. No Godot runtime executed; no performance gain claimed.

MEASUREMENT: NOT RUN. Existing profiled baseline at tick900: markets ~131ms/paid tick and factions ~131ms/paid tick (300-tick window); this patch's share unknown. Next: execute targeted test and same-seed before/after early/late market phase timings with call counts, p95 and history sample sizes; then N38 restart and N9/N39 exact parity before acceptance. If no measurable benefit, revert.

NEXT CODE STEP: inspect repeated full DTO/history traversals in paid market path and remove only a demonstrated growing duplicate; do not add detached indices.
