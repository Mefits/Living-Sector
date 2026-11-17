# PERF B — N9 restore single-pass validation (17.11.2026)

CODE: d31847d266e1e025a56d01e6c62ed90475dd8295
TEST: 18f903e8bc1ebf954c9daf7e5293f6f2f634be7d

Files:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_restore_single_pass_atomic_negative_20261117.gd

N9 restore previously scanned all receipt rows to validate and then scanned them again to construct immutable COW partitions. Validation now happens during the local index build, with no authoritative field published until all rows validate. Late invalid rows reject the entire restore. Receipt order, deep detachment, version, f64, idempotency, rollback, and N38 format are unchanged.

Targeted negative: 100 paid operations; malformed late receipt; original target ledger unchanged; valid restore roundtrip; duplicate operation rejected; receipt index audit.

TEST EXECUTED: NOT RUN (Godot runtime unavailable in this execution). CODE_UNVERIFIED. No CPU/paid tick or late-window speedup measured. This path is restore-only, NOT evidence of solving cumulative paid-tick slowdown. Previous #43972442164 PASS predates this commit.

Next: obtain actual N9 paid_path_profile counters at ticks 100/300/600/900, compare to phase CPU costs; stop N9 micro-optimizations if contribution is negligible. Avoid repeating 99ab25e9 and 1676db61; no N39 changes.
