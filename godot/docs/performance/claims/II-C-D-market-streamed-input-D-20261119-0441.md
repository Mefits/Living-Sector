# Astra II-C D — streamed market input staging
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 04:41 MSK
BASE_SHA: 098daac4f9c8fbc398807e00b55f4984a0011ba3
ASTRA: II-C station/faction/market rosters; eliminate redundant market DTO materializations.
CODE_SHA: 0a0654a62b42c26e4aab40c9835062e14d2518b0
TEST_SHA: 6341a4a2edf1b3d59f3abc28bd919442e218cbe6
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
FILES:
- godot/scripts/sim/phase2/unified_market_phase.gd
- godot/tests/p2_perf_d_market_streamed_input.gd

RESULT: Complete source-row preflight and duplicate-ID rejection still precede every N150 invocation. The adapter now stores only id->location in its initial scan and assembles borrowed pricing/flow/orders/history input for each market just before its sorted N150 tick. No all-markets input DTO registry is retained; output ownership still comes from N150 and crisis staging. Sorted tick and crisis ordering, stock-mint guard, preflight error precedence and source World isolation remain intended invariants.

ORACLE: standalone N150+crisis reference against adapter for 0/1/3/12 markets, ticks 2/16/64/201, reversed insertion, alias mutation, malformed preflight/duplicate ID and invalid order. Not executed; CODE_UNVERIFIED.

NEXT ASTRA II-C D: remove repeated faction Head facility/contract scans via bounded per-planning-cycle indexed read view with owner/status invalidation and positive/negative oracle. Do not repeat completed station administrator snapshot or N150 order/window work.
