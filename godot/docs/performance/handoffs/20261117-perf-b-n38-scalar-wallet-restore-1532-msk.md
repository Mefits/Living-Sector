# PERF B · 17.11.2026 · N38 scalar wallet restore
Branch: `integration/perf-astra-5-workers-20261116` / draft PR #262.

- CODE `b6f4f75db2165fcd46be76cb6bc2d3003fc98fc5`: `godot/scripts/sim/economy/credit_ledger.gd`, N38 restore uses shallow detached copy of validated integer-only balances instead of recursive `duplicate(true)`; resets private order-chunk ownership on successful history replacement.
- TEST `3871dc98df007bd00ccd0826d9449e5d189fc0f9`: `godot/tests/p2_perf_b_n38_scalar_restore_detach_20261117.gd`. Checks exact receipt roundtrip, mutation of untrusted source wallets, negative wallet rejection without partial publication, fork isolation and duplicate operation ID.
- TEST STATUS: **NOT RUN / CODE_UNVERIFIED** (no Godot runtime exercised). This is a bounded N38 restore allocation reduction, **not** a measured improvement to paid-tick performance.
- Scope: no N39, N158, N152, N9 WeakRef/fork changes; no N38 schema or limit changes. CI #43972442164 predates this code.
- Remaining evidence gap: no actual N9 paid-path call/time series or N38 byte series for ticks 100/300/600/900; cannot attribute late-tick slowdown to B. Existing N9 `paid_path_profile()` and N38 `last_save_encoded_bytes()` / `last_save_encode_usec()` provide the relevant counters, but sampling needs coordination with E without serializing an extra checkpoint per tick.
- Next: collect same-seed N9 append/snapshot cumulative deltas and N38 actual save bytes at bounded checkpoints; if N9 contribution is low, stop B micro-optimizations. Run targeted test and exact N38 restart/rollback parity before acceptance.
