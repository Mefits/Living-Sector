# II-C — N21 dock queue paid-tick owned staging

STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 12:26 Europe/Moscow
BASE HEAD: 47d50c6f184d136d2a693959087b37e2875c9fc3
ASTRA: II-C ship/contract/dock/route caches; growing dock_queue paid-tick path.
INTENDED FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_dock_queue_owned_stage.gd
PLAN: eliminate redundant deep copies of dock queues/ledger on real paid queue advance while preserving FIFO, paid receipts, mutable ownership, and N9 semantics; positive and negative oracle tests.
EXPECTED CHECK: source oracle on paid admission, insolvency, stale waiter, FIFO, ownership, N38-compatible ledger; Godot unavailable => TEST_NOT_RUN.
