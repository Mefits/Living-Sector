# Astra III/E — source-size / paid phase growth attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 01:50 MSK
BASE_SHA: 7ba3210a6d2b896011b12901fd4c0e18ed855e5b
ASTRA: E paid-tick bounded early/late profiling, phase callsites, receipts/contracts/dock/events size, same-seed parity.
INTENDED: godot/scripts/sim/phase2/n158_size_phase_attribution.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_size_phase_attribution.gd.
GOAL: correlate exact checkpoint-gated source size growth with actual direct/worker phase per-call growth, without claiming causality or CPU time. Strict negative oracle for inconsistent bounds, missing metrics, mutable aliases and fabricated sizes.
TEST: targeted headless script (NOT RUN until authorized); no CI.
