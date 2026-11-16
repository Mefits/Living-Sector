# PERF E · checkpoint coverage acceptance guard · 2026-11-16

Branch: `integration/perf-astra-5-workers-20261116` (draft PR #262).

## Changes
- Code commit `be4b830d2dd7770c5ae9596440bfa99368a0befe`: `godot/scripts/sim/phase2/n158_worker_request_metrics.gd`.
- Test commit `8e7ad32d1ae45f6f98b2385659c77710e9f9a91c`: `godot/tests/p2_perf_e_checkpoint_coverage_forgery.gd`.
- The comparator previously trusted caller-supplied `complete=true` and could accept a pair of 0/0 paid-tick windows as evidence of acceleration. It now requires exact 100-tick coverage at every checkpoint before accepting timing claims.
- Targeted negative regression covers forged 0, 1, 99 and 101 counts, and a pair of equally forged zero-count windows.
- No simulation/World/N9/N38/worker/UI logic, cadence, prices, RNG or balance changed.

## Verification
- CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. No Godot execution in this run. No CPU/FPS/TPS improvement claimed.
- Static preload path checked against existing file. This is an acceptance safety change, not an optimization.

## Next concrete code
Connect N9 authoritative journal and SourceClock event-queue primitive counts to E-owned checkpoint sampler without live aliases, preserving missing/unknown semantics. Then execute bounded same-seed 100/300/600/900 paid-tick comparator after A/C/D hotpath changes; report phase times and N38/BT/RNG parity.
