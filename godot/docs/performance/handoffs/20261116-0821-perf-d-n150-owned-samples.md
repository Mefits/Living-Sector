# PERF D · 2026-11-16 08:21 MSK · N150 consumption samples

Branch: `integration/perf-astra-5-workers-20261116`; PR #262. Frozen Rust 0.6.7 remains behavioral reference.

- CODE commit: `a07e6268a0a46cf272aec99db2b9cba149e9d54d` — `godot/scripts/sim/phase1/n150_native_full_market_tick.gd`.
- TEST commit: `17bf5391987815e0a5bef78575224ba99db2f0bf` — `godot/tests/p2_perf_d_n150_consumption_owned_samples.gd`.
- N150 `tick_one_market` already deep-duplicates the whole input market. Consumption-window retention previously duplicated each retained sample *again*. It now retains the sample inside the already-owned staged market. Source and returned nested data remain detached by the initial full copy. Filtering, cutoff, order, observed sums, pricing and cadence unchanged.
- Targeted regression: cutoff and stable sample order over four ticks, input immutability, nested alias mutation, deterministic repeat, invalid sample rollback.
- TEST EXECUTED: NOT RUN (Godot 4.7.2 not available). Static inspection only; CODE_UNVERIFIED. No FPS/TPS improvement claimed or measured. No Actions started.
- Risk: end-to-end World/N9/N38 and 420/900 tick parity not yet executed. No live runtime switch or changed world authority.
- NEXT: run targeted N150 regression, original N150 tests, N38 restart360 and identical-seed 420/900 baseline-versus-patch before acceptance; inspect remaining market DTO copies only with profiles.
- Lease: no cross-domain files touched; no lease held.
