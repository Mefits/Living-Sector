# PERF E handoff · 2026-11-16 04:33 CET

Branch: integration/perf-astra-5-workers-20261116; PR #262.

Code commit: 4567941cdd7245421d9db9b62a22f1b6dad49054
Test commit: ad5168eb740ed9777af545a79383511475c97ea6

Files:
- godot/scripts/sim/phase2/n158_worker_execution_adapter.gd
- godot/tests/p2_perf_e_execution_adapter_boundary.gd

Implemented: opt-in single-owner pump coordinating existing FIFO/control scheduler with caller-supplied authoritative tick, projection and N38 persistence callbacks. Commands drain before tick admission; only completed tick produces a detached FrameView; tick failure freezes command intake and preserves prior committed presentation. Does NOT create a second World/Runner, start a thread, call SceneTree or change main.gd.

Tests: TEST_ADDED_NOT_RUN / CODE_UNVERIFIED (no Godot execution). Static signatures checked against current control coordinator and existing preloads. No FPS/TPS measured. PR #261 worker16 PASS, N39 420 CANCELLED, worker420 SKIPPED; no new Actions.

Risks: adapter accepts owner-provided tick success; integration must only report true after actual N158 atomic commit. Callback projection must contain detached scalar trees. One tick per pump is intentional; no performance claim. Existing scheduler clamp/cadence requires parity verification before use. Not wired to production by default.

NEXT: implement experimental N158-specific callback binding using real N158 API and bounded parity harness, then N38/BT/RNG replay. Do not switch main.gd until parity. No shared files edited; lease not required for new E-owned files.
