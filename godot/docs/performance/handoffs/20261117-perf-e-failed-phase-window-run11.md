# PERF E — failed-phase window rejection (17.11.2026)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262. No merge.

CODE: `d6ee59211b83e46e4d55e0d9bdb08a2de7621387`
TEST: `d3bfcd2727916c9391a49e9f5f86df1cc9f547d4`

Files:
- `godot/scripts/sim/phase2/n158_timed_phase_probe.gd`
- `godot/tests/p2_perf_e_failed_phase_window_20261117.gd`

Problem: previously an unsuccessful phase was simply skipped. Already accepted phases for the same source tick remained in the bounded candidate window; later successful calls could complete that row and falsely certify a 100-tick window. The probe now invalidates the entire window upon a failed phase and rejects subsequent calls from that failed tick. A new test checks non-resurrection and recovery after 100 fresh contiguous ticks.

TEST EXECUTED: NOT RUN — CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Godot runtime unavailable in this execution. No new FPS/TPS or speedup claim; this is diagnostic correctness only. Existing CI #43972442164 predates this patch. No changes to authoritative World/N9/worker/UI, source cadence, economy, BT/RNG or Astra fixes.

NEXT: execute targeted `p2_perf_e_failed_phase_window_20261117.gd` and existing `p2_perf_e_paid_phase_window_20261117.gd`; then a single bounded <=900 paid-tick profiling run (<=12 min) with N38/BT/RNG parity and measured phase/request wall time. Note: a phase probe alone does not certify that the whole source tick committed; acceptance must still be gated by authoritative paid-tick completion.
