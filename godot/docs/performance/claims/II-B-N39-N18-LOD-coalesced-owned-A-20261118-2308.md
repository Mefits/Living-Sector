# Astra II-B — N39 N18 staffing / LOD owned stage
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-18 23:08 MSK
BASE_SHA: 3c47fe08a0eff1b1a1fd1e6af0954be7183a38d8
ASTRA: II-B bounded owned write sets, local validators, versions/delta; N39 L196 paid tick stages.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_staffing_lod_owned.gd
GOAL: Coalesce the N18 staffing and immediately subsequent LOD cursor writes into one owned facilities stage while retaining per-stage Schema oracle, no mutable alias, no-op and rejected-stage behavior; regression against legacy staged behavior.
TEST: NOT_RUN
