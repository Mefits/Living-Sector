# Astra II-B · N39 L196 lifecycle row ownership

STATUS: IN_PROGRESS
OWNER: A
DATE: 2026-11-18 13:10 Europe/Moscow
BASE HEAD: ec50834c1ba59fd7c35004b824fbb5c2e5efea8d
SOURCE BLOB: 35dd0d3d5b81ac4eb51b54be701d527b59862cbb
TASK: II-B, N39 L196 lifecycle N156/N130: avoid cloning every facility row on ordinary ticks while retaining complete owned rollback, paid repair and restock semantics.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n39_l196_lifecycle_rows.gd
EXPECTED CHECK: positive lifecycle updates, rejected payroll isolation, due N130 paid restock, full Schema/ledger oracle, same-seed parity; no CI this shift.
