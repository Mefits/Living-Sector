# PERF B — N9 paid-path profiler continuity, 17.11.2026 07:55 MSK

CODE COMMIT: b85002d0951e317d508387e74da7d6e91f89841b
TEST COMMIT: 8c4fb3df9f762ef68236320e4d0079fd2ec35351

Files:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_n9_paid_profile_fork_counters_20261117.gd

Problem: LS_PROFILE_N9_APPEND counters are instance-local and were reset to zero in every trusted Ledger fork. Because real paid operations create authoritative COW generations, late-tick append/snapshot counters could not be interpreted cumulatively. The fix carries seven scalar diagnostic counters into the child only when profiling is enabled. It does not alter receipts, balances, COW ownership, N38 schema or default non-profile behavior.

Targeted negative regression: inherited counters and maxima, independent parent/child mutation, diagnostics absent from snapshot. TEST EXECUTED: NOT RUN (Godot 4.7.2 unavailable here). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No CPU speedup claimed: this is measurement correctness, not a reduction in paid tick time.

NEXT: collect N9 paid_path_profile() from the authoritative ledger at matched tick 100/300/600/900 alongside phase CPU/p95 and receipt_count; compare delta append_calls, append_usec, snapshot_calls, snapshot_usec and N38 encoded bytes. Profile branch transitions carefully: rejected branches may accumulate work not represented in authoritative counters. If N9 contribution is small, report negative finding and stop N9 micro-optimizations. No CI triggered; batch into one <=12min checkpoint with parity/restart gates.
