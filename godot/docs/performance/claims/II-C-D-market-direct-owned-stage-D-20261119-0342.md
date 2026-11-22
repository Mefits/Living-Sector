# Astra II-C D — N150 market direct owned staging
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-19 03:42 MSK
BASE_SHA: 483cb88294430274b01b1bd8b1d20f5de2bcdf83
ASTRA: II-C station/faction/market rosters, redundant market DTO materialization.
FILES: godot/scripts/sim/phase2/unified_market_phase.gd; godot/tests/p2_perf_d_market_direct_stage_oracle.gd
GOAL: eliminate intermediate full computed market registry and DTO output while retaining sorted N150 validation, source stock guard, crisis staging and atomic proposal; compare legacy vs direct including negatives.
TEST: NOT_RUN

CODE_SHA: 6972980f856cf7b820f0b1d925642ba73ee97c11
TEST_SHA: 34b4b925f497c1ea6e3136aafc111efbac8e1f27
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
FILES_CHANGED: godot/scripts/sim/phase2/unified_market_phase.gd; godot/tests/p2_perf_d_market_direct_stage_oracle.gd
IMPLEMENTED: inline N150 canonical sorted market staging; retain full-batch validation before crisis stage, per-market output validation and stock-mint guard, transfer deep-owned results into location-indexed proposal; avoid intermediate tick_markets wrapper and extra batch handoff.
ORACLE: legacy N150.tick_markets vs direct adapter at 0/1/3/12 markets and 1/16/51/100/400 ticks; source isolation, duplicate identity, malformed late market, exact prices/demand/orders/history/events.
RISK: parser/runtime and actual paid-tick speed unverified. The optimization removes wrapper dispatch/extra result registry traversal but does not eliminate core N150 market deep copy.
NEXT_ASTRA: II-C shared Head/station facility roster with safe per-cycle ownership and invalidation on install/remove/move/ownership; benchmark true faction/market paid ticks.
