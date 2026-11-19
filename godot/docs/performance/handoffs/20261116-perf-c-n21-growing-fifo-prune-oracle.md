# PERF C — 2026-11-16 N21 growing dock queue prune
CODE COMMIT: c90e635c5e35281a45a9482431a68c25f8d453aa
TEST COMMIT: bd7d9f8f37cf4fffa5934868c13c4ebb6c49a850
Branch: integration/perf-astra-5-workers-20261116 (PR #262)
Files:
- godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd
- godot/tests/p2_perf_c_n21_prune_oracle.gd

Actual invoked hotpath: N21 advance/request calls _prune on growing dock_queue. Original _prune uses after.has(sid) per valid queued item, making duplicate suppression O(Q²) for Q valid waiters. Replacement uses local seen Dictionary, first valid occurrence only; order, stale waiter checks, and unchanged-queue result preserved. No cached state between ticks, no N9/N39 mutation or changes to fees, paid contracts, cargo, BT, fuel, or tie-break. Queue copying and World snapshots remain separate potential bottlenecks.

Test: standalone N21 prune oracle compares original linear after.has algorithm to new _prune with 240 valid ships, duplicates, stale location, missing ship, and null attempt tick; checks no mutation of original fixture and idempotence. Reuses p2_n21_fifo_paid_source_check.run_checks() for paid fee, insolvency, receipt retry, FIFO, stale transit.
TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
Benefit: asymptotic reduction of duplicate suppression only; no measured CPU savings or same-seed paid-tick parity yet. Existing CI baseline tick900 ships ~392ms/tick, dock_queue ~88ms/tick, not attributable to _prune without site timing.
NEXT: source-level time N21 _prune vs _queue/World copy and _occupants, bounded same-seed 100/600/900 windows and exact N38/paid parity; coordinate with A if World snapshot dominates. Do not launch full 2600-tick CI.
