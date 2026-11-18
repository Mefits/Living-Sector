# II-C — N140 redundant agent-map / ship roster construction

STATUS: IN_PROGRESS
OWNER: C
STARTED: 2026-11-18 10:34 MSK
BASE_HEAD_SHA: 9ba8a1f8dc9dbf7685aa54ed0a609c4545940e0f
SOURCE: ASTRA_FIVE_SHIFTS_RU.md → C / II-C ship-contract-dock-route hotpaths
TASK: Identify and eliminate a repeated, actually called N140 agent-map/ship-roster materialization without changing order or ownership semantics.
INTENDED_FILES: godot/scripts/sim/phase2/unified_n140_*.gd; godot/tests/p2_perf_c_n140_*.gd
EXPECTED_CHECK: independent old/new deterministic agent ordering and negative mutated/duplicate identity regression; runtime not assumed.
