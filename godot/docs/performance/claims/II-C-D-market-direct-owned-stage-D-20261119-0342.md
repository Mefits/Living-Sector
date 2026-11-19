# Astra II-C D — N150 market direct owned staging
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-19 03:42 MSK
BASE_SHA: 483cb88294430274b01b1bd8b1d20f5de2bcdf83
ASTRA: II-C station/faction/market rosters, redundant market DTO materialization.
FILES: godot/scripts/sim/phase2/unified_market_phase.gd; godot/tests/p2_perf_d_market_direct_stage_oracle.gd
GOAL: eliminate intermediate full computed market registry and DTO output while retaining sorted N150 validation, source stock guard, crisis staging and atomic proposal; compare legacy vs direct including negatives.
TEST: NOT_RUN
