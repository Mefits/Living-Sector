# PERF E handoff · 17.11.2026 · complete-only phase totals

Code commit: 806cdfe4dbffddca15a2e9d38208656dc8b6a518
Test commit: 2e85e1778979b38f552c85aa420e8f951c8f7b98

Files:
- godot/scripts/sim/phase2/n158_timed_phase_probe.gd
- godot/tests/p2_perf_e_complete_phase_totals_20261117.gd

The new paid_phase_totals(end_tick) reports only 100 contiguous, four-phase-complete rows, unlike phase_metrics() which includes partial/aborted calls. Returns detached primitive totals. It is diagnostic only; the authoritative SourceClock/N38 checkpoint must independently certify that all rows were paid ticks.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot runtime benchmark or speedup measured. No worker/UI/World/N9/ship behavior changed.

NEXT: invoke the targeted test in the next bounded parser/test checkpoint, then wire only independently verified paid-phase totals to A/C/D phase reports and compare 100/300/600/900 under N38/BT/RNG parity.
