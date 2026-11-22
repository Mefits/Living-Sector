# PERF E · N38 restart explicit arm negative regression · 2026-11-16

Branch: `integration/perf-astra-5-workers-20261116`; PR #262.

CODE COMMIT: `8f94ddb3ae29cd42404d07be953b799625d24f2d`.
TEST COMMIT: `7d3c4474472e72220c5fbeb870d61fb5396b054a`.

FILES:
- `godot/scripts/sim/phase2/n158_parity_checkpoint_trace.gd`: `verify_restart` now requires an outstanding `require_restart_verification` request, rejecting unsolicited verification with `restart_not_requested` and freezing the trace.
- `godot/tests/p2_perf_e_restart_requires_arm.gd`: negative unsolicited verification and positive armed restart at tick 360 followed by tick 361.

WHY: previously a caller could invoke `verify_restart` without arming the restart gate and get a successful result. This weakens the explicit N38 verification protocol. No World/N9/N38 implementation or default runtime changed.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or Windows FPS measurement. Expected benefit: safety invariant only, performance unmeasured.

NEXT: integrate this trace with real opt-in N158/N38 restart harness; collect full direct/worker snapshots including N9/BT/RNG and run bounded parity + Windows F5 FPS paused/x1/x8/x16. Keep default backend unchanged until evidence.
