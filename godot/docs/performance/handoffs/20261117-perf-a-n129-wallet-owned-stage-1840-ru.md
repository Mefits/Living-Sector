# PERF A · N129 wallet-owned stage · 2026-11-17 18:40 MSK

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

Code commit: `c0482078ebe2ecfeb2e611a264a19292fdbb2ee3`.
Test commit: `025cd74d5ac14ea6f8797ef48c4f3fb6eb316160`.

Changed `godot/scripts/sim/phase1/n39_native_world_production.gd` at N129 `L4930`: replace deep full-World stage with shallow root plus detached deep copies of `faction_treasuries`, `facilities`, `populations`. Those are the only nested World domains mutated in `apply_native_faction_finance`. The original Schema.validate, Schema.accounts, ledger fork/transfer, total conservation, account-by-account reconciliation and commit boundary remain intact. No changes to N9, N158, N38, or other worker domains.

Added `godot/tests/p2_perf_a_n129_wallet_owned_stage.gd`: synthetic full deep-copy oracle comparison, source immutability, nested mutation isolation, and negative shallow-row alias reproduction. It does not exercise the production N129 function.

Status: CODE_COMMITTED; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No runtime execution, parity, p95 or speedup measurements. The old #43972442164 PASS predates this patch and cannot validate it. This path is a due-only faction-finance stage; frequency and benefit must be measured rather than assumed.

Next: E to run targeted N129 funded/unfunded/rollback + N38 restart and same-seed exact ledger/World/BT/RNG/contract/cargo parity, then profile N39 callsite counts and early/late paid-tick CPU. Avoid repeat 99ab25e9 and 1676db61. No CI dispatched here.
