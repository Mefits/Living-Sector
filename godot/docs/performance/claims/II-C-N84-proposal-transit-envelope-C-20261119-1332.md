# II-C N84 proposal-scoped transit envelope
STATUS: IN_PROGRESS
OWNER: C
DATE: 2026-11-19 13:32 MSK
BASE_SHA: 1df1ca3672f523cffe8f094004dd0ab7871144e1
ASTRA: II-C ship/contract/dock/route caches; eliminate repeated N84/N14 fleet envelope scans, explicit invalidation on BeginTransit.
FILES: godot/scripts/sim/phase2/unified_ship_phase.gd; godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_transit_envelope.gd
EXPECTED: same authoritative validation for default callers, proposal-only reuse with explicit invalidation after each staged transit; positive and negative oracle for identity/transit/token, BT/cargo/route ownership.
TEST: NOT_RUN
