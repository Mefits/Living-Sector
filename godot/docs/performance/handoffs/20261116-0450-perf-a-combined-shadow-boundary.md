# PERF A — N39/N150 combined shadow boundary (2026-11-16 04:50 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

Code SHA: `cc24c58107d7b04fffa0e4cbf3cacb25fdc0678a`.
Test SHA: `04495ee7d5ff30a8a66880814788e56124f89083`.

Files:
- `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`
- `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`

Added `validate_shadow_boundary(snapshot, markets)` to validate detached protected-field ownership and invoke the existing N150 observation validator with a minimal detached identity baseline. No second World/ledger, no production integration, no full Schema oracle replacement. Existing protected snapshot still fails closed on malformed rows. Negative tests cover invalid price, crisis flag, in-place stock/identity mutation and missing protected identity.

TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Static signature/path review performed against current N150 validator and guard. No performance measurement; no claim of speedup. No Actions.

NEXT: coordinate shadow-only invocation at N150 commit boundary with D; compare result against full Schema oracle on paid world and N38 restart. Do not enable fast path or remove Schema.validate before verified equivalence and 420/900 tick benchmark.
