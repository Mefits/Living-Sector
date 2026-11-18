# II-C — N140 redundant agent-map / ship roster construction

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
STARTED: 2026-11-18 10:34 MSK
BASE_HEAD_SHA: 9ba8a1f8dc9dbf7685aa54ed0a609c4545940e0f
SOURCE: ASTRA_FIVE_SHIFTS_RU.md → C / II-C ship-contract-dock-route hotpaths
TASK: Identify and eliminate a repeated, actually called N140 agent-map/ship-roster materialization without changing order or ownership semantics.
INTENDED_FILES: godot/scripts/sim/phase2/unified_n140_*.gd; godot/tests/p2_perf_c_n140_*.gd
EXPECTED_CHECK: independent old/new deterministic agent ordering and negative mutated/duplicate identity regression; runtime not assumed.

COMPLETED: 2026-11-18 10:xx MSK
CODE_SHA: f1d4446db3a985f42f30671089c42106dc5d6bfc; corrective 8d910b2045f6d85dd9cf9f3b6ba13dfd11db2083
TEST_SHA: a59a1814c5c4e3feaa4823c482f6bf7924549e37
FILES: godot/scripts/sim/phase2/unified_n140_ship_lod_phase.gd; godot/tests/p2_perf_c_n140_no_lod_gate_oracle_20261118.gd
FIX: when all validated ship rows lack AgentLod, bypass redundant SourceLod recompute/ship_gate agent-map deep copies; preserve detached fleet, every-ship firing, recompute zero-tier stats, invalid transit rejection and mixed-LOD original path.
TEST: NOT_RUN (no Godot runtime executed). Source oracle and negative tests added, no speed claim.
RISK: SourceLod no-LOD semantics and recompute stats require real Godot oracle run; no paid-tick before/after measurement.
NEXT: II-C N140 mixed-LOD copy reductions after source-site profiling; run targeted oracle and same-seed paid tick windows 100/600/900 in coordinated morning checkpoint.
