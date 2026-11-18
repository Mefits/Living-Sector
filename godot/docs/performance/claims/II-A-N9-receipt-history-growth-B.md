# Astra II-A — N9 paid transaction staging

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: B
STARTED: 2026-11-18 10:17 MSK
BASE_SHA: 0719842b7526cd91f4decf2bd1f30fe0563c4ca8
SOURCE: ASTRA_FIVE_SHIFTS_RU.md, II-A / B ledger paid-path remaining work.
CLAIM_SHA: 7c77273c2c20c2d9d27b33a6fe178cab5e327a17
CODE_SHA: 5edf8f2e59ae7118b6fd36fa9c2dc154b613fcd9
TEST_SHA: 839b510186662a1a44c69d1442a996464bed46d4
FILES:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_paid_staged_wallet_atomic_20261118.gd
TEST: NOT_RUN (no Godot execution; source-reviewed only)
RESULT: On the real N9 commit() paid path, stage final validated wallet values in one pass and publish only after every wallet passes. Removes repeated authoritative balance lookup and repeated final addition on the second publish pass. No changes to receipts, idempotency, N38 format, World/N39 or WeakRef. Regression covers late insufficient funds, repeated wallet legs, duplicate operation, overflow, immutable receipt, fork, and exact N38 restore.
PERF: NOT_MEASURED; no speedup claim. This is a bounded allocation/lookup reduction, not proven late-tick growth fix.
NEXT: Astra II-A receipt journal growth: compare append/snapshot counters with real early/late paid ticks before enabling private shard reuse. Do not duplicate existing N9 WeakRef/projections.
