# PERF E — N158 projection failure boundary (2026-11-16 11:57 CET)

Code commit: b3fe9773280d5d43a728d907d1315771ffbe2247
Test commit: 11680ad760a18c4b66d0a042d7715fdfbce840d5

Files:
- godot/scripts/sim/phase2/n158_owner_step_binding.gd
- godot/tests/p2_perf_e_step_projection_health_boundary.gd

Reason: the experimental step binding previously returned a UI projection even after N158 reported a phase failure, stopped, or lost its clock. Now fail closed on those conditions and on an in-flight step. Binding also rejects a missing clock. No simulation mutation, cadence, balance, worker activation, or World/N9/N38 change.

Tests: TEST_ADDED_NOT_RUN / CODE_UNVERIFIED (Godot not executed). No measured FPS gain. No Actions launched. Current plan says opt-in GUI worker is already wired; do not duplicate that work or enable by default.

Next: execute targeted test in a bounded checkpoint alongside opt-in GUI worker parity and N38 restart; collect real Windows paused/x1/x8/x16 FPS at comparable tick windows before any default switch.
