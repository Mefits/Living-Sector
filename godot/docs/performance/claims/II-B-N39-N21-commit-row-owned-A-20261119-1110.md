# Astra II-B — N39 N21 commit row-owned publication
STATUS: IN_PROGRESS
OWNER: PERF A
START: 2026-11-19 11:10 MSK
BASE SHA: f71424cbf9bd1f1b56e587da995faabdc4845b92
ASTRA: II-B bounded owned write sets / real N39 World L129/L196; eliminate deep copy of all ships, facilities, dock receipt history in _commit_native_n21_unprofiled after full Schema/N9 oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n21_commit_row_owned.gd; this claim.
TEST: positive/negative detached write-set, retained immutable rows, nested alias, no mutation on rejected proposal, exact legacy deep-copy value oracle. No Actions.
