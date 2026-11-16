# PERF D — 2026-11-16 06:12 MSK — population totals

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

CODE SHA: `052a72b087369a63d4087e941a469103a1fa3faa`
TEST SHA: `e68435a5e12ce9ec2ac87758104e767a1164c47e`

Files:
- `godot/scripts/sim/phase2/unified_native_station_administration_phase.gd`: N18 aggregates population, workforce, occupied workers once in sorted population-ID order per due cycle, instead of recomputing these for each market. Existing facility roster and planner unchanged. Uses local totals only, no persistent cache or mutable alias.
- `godot/tests/p2_perf_d_population_totals_oracle.gd`: cached-vs-naive equality across 12 cycles, with moves, faction ownership changes, removals, additions and negative population counts.

TEST EXECUTED: NOT RUN; Godot 4.7.2 unavailable. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
Measured speedup: NOT MEASURED. No claims about FPS, N18 planner parity or N38 restart. No CI/Actions run.

Next: execute oracle and existing `p2_perf_d_station_roster_oracle.gd`; compare complete N18 plans and paid-world checkpoints at 420/900 equal-seed ticks; profile market count versus population scan cost. No other worker files touched. Lease: RELEASED (domain-owned isolated edit).
