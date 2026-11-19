# II-B N39 N154 construction commission owned registries — A
STATUS: IN_PROGRESS
OWNER: PERF A
START: 2026-11-19 05:10 MSK
BASE SHA: 1450bf4dd2a268b428703e536e8a700a2bab0e86
ASTRA: II-B bounded owned write sets / L129-L196 snapshots, Schema oracle and rollback/alias isolation.
SCOPE: apply_native_construction_site_commission (N154/N104 paid escrow), construction_sites/contracts/receipts, treasuries, board and escrow registries.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n154_commission_owned.gd; this claim.
EXPECTED: shallow owned registry roots with fresh inserted records, detached ContractBoard snapshot, unchanged authoritative mutable history, full Schema and N9 validation, positive+negative legacy deep-copy oracle.
RISKS: mutable aliases from board.snapshot or site rows, rollback on invalid commission, concurrent A writer CAS.
