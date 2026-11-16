# PERF E — worker tick admission, 2026-11-16 02:30 CET

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
Code commit: `f5aabbfa67cf844d1b90dd61fd534548ca62d2e6`.
Test commit: `cda398489311349f34547898aca52a80fbcb1606`.

## Delivered
- `godot/scripts/sim/phase2/n158_worker_tick_scheduler.gd`: opt-in, single-owner tick admission with paused step, speed, bounded wall-time credit, one in-flight tick, failure freeze, successful-load timing reset. No new World/Clock/Runner, no SceneTree access and no backend enabled.
- `godot/tests/p2_perf_e_worker_tick_scheduler.gd`: targeted negative and boundary tests for pause/step/speed, exact tick admission, in-flight guard, load reset and freeze.

## Evidence and limits
CODE_UNVERIFIED / TEST_ADDED_NOT_RUN: Godot 4.7.2 unavailable. Source manually reviewed for preload path, method signatures and GDScript indentation. FPS/TPS not measured. No Actions triggered. The scheduler is deliberately detached from the actual N158 runner; it does not itself prove deterministic replay or change game performance. PR #261 Windows verdict remains parser PASS, worker16 PASS, N39 420 CANCELLED, worker420 SKIPPED.

## Next concrete code block
Integrate tick admission with the existing `n158_worker_owner_bridge.gd` FIFO owner command protocol in a gated adapter; execute actual N158 ticks only after authoritative command handling and compare full N39/N9/N38/BT/RNG state against direct mode before touching `main.gd`. Ensure frame delta/elapsed is sampled by the owner and never consumes credit twice. Do not switch production backend before Windows parity and GUI measurements.
