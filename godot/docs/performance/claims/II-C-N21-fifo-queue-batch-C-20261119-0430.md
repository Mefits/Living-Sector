# II-C N21 FIFO queue batch
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-19 04:30 MSK
BASE_SHA: ad5f5478d850346ae15c82d13d0cae274be3f0a0
ASTRA: C ships+dock_queue paid-tick hotpath; queue/occupancy, exact FIFO and N9 receipts
FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_fifo_batch.gd
PLAN: avoid repeated FIFO queue copying/linear erasure during paid admission; retain request semantics, ledger and receipts; positive/negative oracle.
TEST: NOT_RUN
