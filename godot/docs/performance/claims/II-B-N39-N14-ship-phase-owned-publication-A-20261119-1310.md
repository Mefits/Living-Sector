# Astra II-B — N39 N14 ship phase owned publication
STATUS: IN_PROGRESS
OWNER: PERF A
DATE: 2026-11-19 13:10 MSK
BASE SHA: 4faa483bf766d0b9bdb137976b74118cdd7a7cd3
BACKLOG: II-B bounded owned write sets; real N39 run_tick/ship phase hot path, L129/L196 copy pressure.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n14_ship_phase_owned_publication.gd
SCOPE: replace N14 apply_ship_phase full fleet deep copy with strict row-owned detached publication, preserve immutable fields, complete Schema and N9 oracle, negative roster/alias/rollback tests.
TEST: NOT_RUN; CODE_UNVERIFIED.
