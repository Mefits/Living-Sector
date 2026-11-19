# PERF B · trusted N9 wallet fork · 2026-11-17

CODE COMMIT: cf1f19949cfbf0504c10d1310d24ea501bcdc4c0
TEST COMMIT: 705cd36abdf76a0b36ad55b6731584ca446d20d6

Files:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_fork_wallet_shallow_20261117.gd

WHY: Real paid-stage Ledger._profile_inner_fork() recursively deep-copied the account dictionary despite authoritative values being validated integer credits. Replace deep duplicate with shallow dictionary duplicate; no nested mutable wallet values are admitted through import/commit/register/restore. Receipts and COW shard ownership unchanged. This removes unnecessary recursive copying at every fork but does not establish a history-dependent hotspot.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Targeted negative checks: parent-child-grandchild balance isolation, duplicate paid operation, retained receipts, exact N38 snapshot/restore, tamper via external snapshot. No measured speedup or same-seed parity evidence yet.

NEXT: E bounded checkpoint should measure N9 fork calls/usec and receipts at early/late windows and compare same seed baseline/optimized, plus run targeted test. If N9 is not a material late-tick contributor, stop speculative N9 changes and report negative finding. No N39/worker/main changes, no CI triggered.
