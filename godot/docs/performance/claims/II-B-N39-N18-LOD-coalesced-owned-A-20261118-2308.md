# Astra II-B — N39 N18 staffing / LOD owned stage
STATUS: BLOCKED
OWNER: A
START: 2026-11-18 23:08 MSK
BASE_SHA: 3c47fe08a0eff1b1a1fd1e6af0954be7183a38d8
ASTRA: II-B bounded owned write sets, local validators, versions/delta; N39 L196 paid tick stages.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_staffing_lod_owned.gd
GOAL: Coalesce the N18 staffing and immediately subsequent LOD cursor writes into one owned facilities stage while retaining per-stage Schema oracle, no mutable alias, no-op and rejected-stage behavior; regression against legacy staged behavior.
TEST: NOT_RUN
CODE_SHA: NONE
TECHNICAL_BLOCKER: N18 publishes its validated staffing World before LOD; LOD may then fail its Schema validation, in which case the already published N18 state must remain. Coalescing the two stages into a single publication changes rollback semantics. Reusing N18 detached facility rows after publication would mutate the authoritative World through shared mutable aliases. A correct implementation needs an independently owned intermediate snapshot or a proven two-stage commit model; neither is established by the current code. No unsafe code change was made.
NEXT: Astra II-B L129 external readsite ownership/invalidation or a separate N39 stage with single atomic publication; do not reuse published N18 rows.
