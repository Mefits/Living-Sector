# PERF B — N9 balances-only scalar snapshot, 17.11.2026 03:36 MSK

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No other domains modified.

CODE COMMIT: `fc8ec9accd58e0bdb841aa1eb33a1d09bef9496f`
TEST COMMITS: `87b091d4ad287f4ea474a2ddbe87a443072ce1ab`, correction `5461b2cd6fec02456bc22324d568553853e2ddff`.

Files:
- `godot/scripts/sim/economy/credit_ledger.gd`: `balances_snapshot()` uses `_balances.duplicate()` instead of recursive `duplicate(true)`. All balances are validated scalar integer credits, and the returned Dictionary is still detached from the authoritative N9.
- `godot/tests/p2_perf_b_balances_snapshot_scalar_isolation_20261117.gd`: targeted negative mutation/alias test, paid transfer and receipt preservation.

Source verification: `import_accounts` validates amounts, `balance` returns -1 for missing accounts, `transfer` and `has_receipt` exist. No change to N9 WeakRef/fork, N152, N158, N39, N38 format or save atomicity.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime test, no benchmark and no measured speedup. The eliminated recursive walk may be small; N9 is not proven responsible for late-tick degradation.

NEXT: E to measure actual `balances_snapshot` calls/time and N9 receipt counts at early/late windows; B to inspect only measured N9/N38 growth. Same-seed before/after, N9/N39/N38/BT/RNG/cargo/contract parity and late Windows soak remain acceptance gates. Do not duplicate 99ab25e9 or 1676db61.
