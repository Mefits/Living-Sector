# II-C — N21 dock queue paid-tick owned staging

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 12:26 Europe/Moscow
BASE HEAD: 47d50c6f184d136d2a693959087b37e2875c9fc3
ASTRA: II-C ship/contract/dock/route caches; growing dock_queue paid-tick path.
INTENDED FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_dock_queue_owned_stage.gd
PLAN: eliminate redundant deep copies of dock queues/ledger on real paid queue advance while preserving FIFO, paid receipts, mutable ownership, and N9 semantics; positive and negative oracle tests.
EXPECTED CHECK: source oracle on paid admission, insolvency, stale waiter, FIFO, ownership, N38-compatible ledger; Godot unavailable => TEST_NOT_RUN.

## Completion
CODE SHA: fe81add1b9de557bd858cb1abea1fbfd99d79231; 086c8c9ec5c35348110f095ea3e9ac796385d600
TEST SHA: 6f070a0615ef7c15e1b3774a65c6ab2e80f1c5eb
FILES: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_dock_queue_owned_stage.gd
CHANGED: advance() lazily restores N9 once for first real paid FIFO admission, reuses same Bank for subsequent paid dock receipts, returns one detached N9 snapshot; _admit() avoids a throwaway deep copy on paid path; _queue() copies scalar IDs without recursively duplicating them.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. New independent sequential per-admission dictionary-restore oracle checks multiple paid admissions, insolvent/stale waiters, exact World/N9/receipts, retry idempotence, input ownership, and invalid ledger.
RISK: Godot parser and full N38 replay not run; source assumes Bank.transfer and Bank.snapshot preserve receipt insertion order across multiple paid admissions. No Actions requested.
NEXT ASTRA II-C: examine N153 contract dispatch route cache invalidation and source-level paid-tick scans with cached-vs-uncached oracle, including ownership/paid cargo/tie-break negatives.
