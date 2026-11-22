# Astra II-B — N39 N104 release owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 14:13 MSK
BASE PR #262 HEAD: 0c7395cbb3684c7ee23171b2780fac86b0f5ca1d
ASTRA: II-B bounded owned write sets, L129/L196 World snapshots, full Schema oracle, alias/rollback.
TASK: N104 release currently deep-clones complete ships, contract_board and faction_relations on commit. Replace with selective changed-row ownership across all three domains while preserving exact candidate, Schema, N9 and immutable history guards.
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n104_release_owned_publication.gd
TEST: old deep-clone oracle, changed contract/ship/relation, negative unrelated changes, malformed and nested alias, rejected rollback; Godot TEST_NOT_RUN until manual verification.

CODE SHA: 8e4df119e76eb67207d5dc57be3b0f6a8f87c53a
TEST SHA: 7bfcdf816013312a278d0dc9c27b6ab6d8c1d16c
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
IMPLEMENTED: apply_native_n104_release_contract now uses _n104_owned_release_publication for changed ship, contract and faction relation rows. Revalidates full Schema before publishing; source N9 account equality and contract write-set gates remain. Negative regression includes foreign ship/contract mutations, removals, malformed contract, missing IDs, nested alias isolation and old deep-copy oracle.
RISK: No Godot executable run; source N104.stage may still deep-copy internally. Full same-seed/N38 replay and paid-tick performance remain unverified.
NEXT: Astra II-B real N39 L129/L196 repeat world_snapshot callers, or N104 release source staging deep copy once ownership boundary is proven; preserve complete Schema/N9 oracle.
