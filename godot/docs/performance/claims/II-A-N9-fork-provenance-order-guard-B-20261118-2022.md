# Astra II-A / B — N9 fork provenance order integrity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF B
START: 2026-11-18 20:22 Europe/Moscow
BASE SHA: 66057229e78dbade9a523732408982760901f43d
ASTRA: II-A append-only + stage overlays + invariant transaction + provenance; bounded fork provenance must prove receipt order as well as shard identity.
INTENDED FILES: godot/scripts/sim/economy/credit_ledger.gd; godot/tests/p2_perf_b_fork_provenance_order_guard.gd
EXPECTED: strict child/parent lineage, unchanged prefix order, no forged or removed receipts, negative tamper cases and positive fork append/restoration; no full-history scan on trusted paid path.
CODE SHA: 3d1e30138d4bb14980e974f7a68054ef8e17d84f
TEST SHA: 19af51c17933869644062f9cdf23d761694e3335
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
IMPLEMENTED: retains_owned_receipts now checks append-only order prefix, validates appended IDs against authoritative shards, checks unchanged-shard identity for trusted fork, and retains exhaustive shard fallback for restored/unrelated ledgers. Negative tests cover tail reorder, missing appended ID, unmarked shard mutation; positive tests cover 135 receipts and N38 restore.
RISK: Godot 4.7.2 runtime not available; no CI triggered. Verify integer division, full replay and paid-tick overhead on Windows.
NEXT: Astra II-A measure N9 COW receipt shard append and snapshot costs at 100/300/600/900 paid ticks with same-seed full N38 oracle; do not enable experimental shard reuse without parity.

