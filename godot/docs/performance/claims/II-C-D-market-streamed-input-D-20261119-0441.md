# Astra II-C D — streamed market input staging
STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-19 04:41 MSK
BASE_SHA: 098daac4f9c8fbc398807e00b55f4984a0011ba3
ASTRA: II-C station/faction/market rosters; eliminate redundant market DTO materializations.
INTENDED_FILES: godot/scripts/sim/phase2/unified_market_phase.gd; godot/tests/p2_perf_d_market_streamed_input.gd
SCOPE: Keep complete preflight validation before N150; stage only market identity/location, materialize each borrowed N150 input just-in-time in sorted identity order. Preserve error precedence, crisis order, stock guard and deep-owned output. Oracle compare previous adapter for valid/invalid markets and aliases.
TEST: NOT_RUN
