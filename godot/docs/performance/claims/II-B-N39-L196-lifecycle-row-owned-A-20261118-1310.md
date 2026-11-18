# Astra II-B · N39 L196 lifecycle row ownership

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
DATE: 2026-11-18 13:10 Europe/Moscow
BASE HEAD: ec50834c1ba59fd7c35004b824fbb5c2e5efea8d
SOURCE BLOB: 35dd0d3d5b81ac4eb51b54be701d527b59862cbb
TASK: II-B, N39 L196 lifecycle N156/N130: avoid cloning every facility row on ordinary ticks while retaining complete owned rollback, paid repair and restock semantics.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_l196_lifecycle_rows.gd
EXPECTED CHECK: positive lifecycle updates, rejected payroll isolation, due N130 paid restock, full Schema/ledger oracle, same-seed parity; no CI this shift.

CODE SHA: c62602c61bdfda532c76fca62c2d2a11e7e9304b
TEST SHA: e39188915464c7f26ceca40dbd9c627322f3c659
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: n39_native_world_production.gd run_tick N156/N130 lifecycle stage.
CHANGE: on ordinary non-restock ticks, shallow-copy facilities registry, detach paid-repair candidate rows before Payroll (including blocked write), and detach all lifecycle delta rows before condition/reserves mutation; on N130 cadence preserve deep facilities/markets ownership. Populations still detach for payroll. Keep full Schema and N9 account checks and atomic World/ledger publication.
NEGATIVES: rejected payroll work_blocked_reason isolation, late-added lifecycle row, nested reserves/work_shift alias, N130 seller/buyer/market ownership; compared against deep World model oracle. This is an ownership-model test, not direct production invocation.
NEXT ASTRA II-B: inspect N39 L129 remaining high-frequency World snapshot callers and bounded rollback stage; verify same-seed early/late paid tick CPU, Schema/N9/N38/BT/RNG parity before accepting speedup.
