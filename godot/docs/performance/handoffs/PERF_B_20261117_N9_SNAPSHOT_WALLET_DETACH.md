# PERF B handoff — 2026-11-17 snapshot wallet detach

Branch: integration/perf-astra-5-workers-20261116 (PR #262)
Code commit: a62f21a7f2c03669d7a651ab1d1c3db0f144aaa6
Test commit: e8b99d7f85761da3d780f8e9d8d880d07b3f88f7

Files:
- godot/scripts/sim/economy/credit_ledger.gd
- godot/tests/p2_perf_b_snapshot_wallet_detach_20261117.gd

Actual N9 snapshot() path: replace recursive _balances.duplicate(true) with _balances.duplicate(). The ledger validates every wallet value as an i64 integer, so no nested mutable wallet value can alias the source. Receipts retain full deep copy and N38 v1 shape unchanged. This removes unnecessary recursive copying of growing wallet maps on each actual N9 snapshot, but is not proof of late-tick contribution.

Negative test: 514 wallets, real payment, exact snapshot/restore, mutate exported wallet and nested receipt, duplicate payment rejection, malformed negative balance restore rejection. No N39 changes.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED. Performance improvement: NOT MEASURED. No same-seed timing/parity claim; no CI launched.

Next: use existing LS_PROFILE_LEDGER and LS_PROFILE_N9_APPEND timing to determine snapshot calls/time per tick100/300/600/900 and compare same-seed before/after; if snapshot is negligible, stop B micro-optimizations and report negative finding. Also check encoded N38 save bytes against 16 MiB only at actual save checkpoints.
