# Astra II-A — N9 trusted fork receipt-order prefix
STATUS: BLOCKED
CODE SHA: NONE
TEST: NOT_RUN
REASON: Current trusted order proof already skips old receipt row comparisons when order chunks retain object identity, and scans only new IDs; eliminating remaining chunk identity checks without a separate immutable ownership proof would permit undetected mutation through exposed internal arrays. No safe significant performance patch identified. No production code changed.
NEXT: N38 encoded save growth: compare per-save serialization/verification read costs and implement a measured, backward-compatible improvement with roundtrip and tamper tests.
OWNER: B
START: 2026-11-19 15:22 MSK
BASE SHA: b6265a71 (to recheck against PR head)
ASTRA: II-A append-only history, immutable receipt provenance; reduce repeated historical scans on paid fork validation.
INTENDED: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_n9_trusted_order_prefix.gd
CHECK: exact legacy order oracle, fork append, parent append, malformed order/receipt, restore invalidation.
RISK: never accept mutable alias or invalid historical receipt; preserve strict fallback for untrusted lineages.
