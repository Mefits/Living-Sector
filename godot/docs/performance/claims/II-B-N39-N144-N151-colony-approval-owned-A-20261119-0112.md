# Astra II-B — N144/N151 colony approval owned writes
STATUS: IN_PROGRESS
OWNER: PERF A
START: 2026-11-19 01:12 MSK
BASE SHA: 425349b770ce55fee7ec9c95ec345abd299ff135
ASTRA: II-B bounded owned write sets, real N39 L129/L196, Schema oracle, rollback/alias.
SCOPE: N39.apply_native_n144_found_colony and apply_native_colony_foundation; duplicate(true) of entire growing construction_sites, construction_receipts, research_directors for append-only approval. Replace with shallow owned registry and per-faction detached research director, preserving atomic commit and source validation. 
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n144_n151_colony_approval_owned.gd
TEST: actual N39 helper parity vs full-deep oracle where feasible, positive/negative duplicate, failed schema rollback, mutable alias, unchanged unrelated rows, N9 unchanged. TEST_NOT_RUN pending Godot.
