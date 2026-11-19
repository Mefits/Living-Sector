# Astra III/E — source-size / paid phase growth attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 01:50 MSK
BASE_SHA: 7ba3210a6d2b896011b12901fd4c0e18ed855e5b
ASTRA: E paid-tick bounded early/late profiling, phase callsites, receipts/contracts/dock/events size, same-seed parity.
INTENDED: godot/scripts/sim/phase2/n158_size_phase_attribution.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_size_phase_attribution.gd.
GOAL: correlate exact checkpoint-gated source size growth with actual direct/worker phase per-call growth, without claiming causality or CPU time. Strict negative oracle for inconsistent bounds, missing metrics, mutable aliases and fabricated sizes.
TEST: targeted headless script (NOT RUN until authorized); no CI.

CODE_SHA: f7e9867a75abe464a47a6c11908d458eafd6a3e2; affb890e9fcb6fe7756fc67a15b015cfe1ec3414
TEST_SHA: 18da637b7bdcaf700f0214fcceba168b8c37abb4
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
FILES: n158_size_phase_attribution.gd, p2_perf_e_real_direct_threaded_oracle.gd, p2_perf_e_size_phase_attribution.gd
IMPLEMENTED: real 100/300/600/900 benchmark now joins checkpoint-gated N39 ship/facility/dock/contract and N9/event count deltas with direct/worker paid phase per-call/per-paid-tick growth. Checks exact matching checkpoint bounds, full phase coverage, finite timings, matching cadence and independent bounded scalar output. Negative fixture rejects missing source/phase/category, invalid timing, divergent cadence and overlapping windows. Does not attribute causality or claim CPU speed.
NEXT ASTRA E: instrument internal copy/Schema/N9 costs via owner-approved observation interface; compare same-seed before/after and N38 exact parity. Do not modify A/B-owned code.
