# II-C N21 FIFO queue batch
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-19 04:30 MSK
BASE_SHA: ad5f5478d850346ae15c82d13d0cae274be3f0a0
ASTRA: C ships+dock_queue paid-tick hotpath; queue/occupancy, exact FIFO and N9 receipts
CODE_SHA: a2dc030323954ad64a55e45809222dbc12bf5cab
TEST_SHA: 1b3d0de645b3c67c8bd5bd6e83fb1536b2b58711
FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_fifo_batch.gd
CHANGED: _admit accepts invocation-local prevalidated fee; request head, request fast path and paid FIFO advance pass their quote, avoiding duplicate _fee and relations calculation. _admit mutates only detached stage queue, removes FIFO head with pop_front or fast-path member with erase, avoiding queue duplication per admission.
INVARIANTS: same occupancy, credit guards, N9 transfer, receipt, queue order and fee; no new persisted cache or World mutation. Tests compare quoted vs uncached actual paid admission, N9 transfer parameters, source ownership, non-head, negative fee, full dock and existing paid-tick oracle.
TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
RISK: no Godot execution; benchmark 24/100/500 and full N38/BT/cargo/route parity remain pending.
NEXT: II-C remaining N84/N153 contract/dock candidate hotpaths and paid 24/100/500 exact parity.
