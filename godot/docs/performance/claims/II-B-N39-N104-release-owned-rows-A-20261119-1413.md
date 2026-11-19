# Astra II-B — N39 N104 release owned publication
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 14:13 MSK
BASE PR #262 HEAD: 0c7395cbb3684c7ee23171b2780fac86b0f5ca1d
ASTRA: II-B bounded owned write sets, L129/L196 World snapshots, full Schema oracle, alias/rollback.
TASK: N104 release currently deep-clones complete ships, contract_board and faction_relations on commit. Replace with selective changed-row ownership across all three domains while preserving exact candidate, Schema, N9 and immutable history guards.
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n104_release_owned_publication.gd
TEST: old deep-clone oracle, changed contract/ship/relation, negative unrelated changes, malformed and nested alias, rejected rollback; Godot TEST_NOT_RUN until manual verification.
