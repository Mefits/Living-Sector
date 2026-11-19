# Astra III/E — live checkpoint observation cost attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 11:50 MSK
BASE_SHA: 5745020f7e5569f1475731b4fb30b52eae61a919
ASTRA: E bounded paid-tick profiling, measured observation overhead and exact N38 parity.
INTENDED: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_checkpoint_cost_attribution.gd
GOAL: measure checkpoint wall cost separately from paid tick and reject forged/missing cost accounting, compare strict and periodic real runs without conflating overhead with simulation speed.
RISKS: checkpoint cost depends on runtime memory; no Windows/Godot execution; no CPU-time claim.
EXPECTED: positive and negative/oracle tests for parity, counts, timing, boundaries; CODE_UNVERIFIED until executed.

CODE_SHA: 937cff7f970a2bc974d63f57a9cc14ad8edff3e5; 45510fe60e765109883fc59cc2ecdec0c804821b
TEST_SHA: 515f2eba9f98205c6b76e80f3ddd92d6b97be5f1; 5dfa81f3c78b7ed0684dd011a271d22756314715; 5b341927835fcb7893c3525dd67c2b2de355e128; 37d82bfa2c1555af55c33ce901116741d082c75b; dab045f95b9732af8620f48a84353578a98503de
TEST: NOT_RUN
CODE: N158 live headless benchmark measures each full checkpoint separately from paid tick elapsed. A/B acceptance checks every gate's bounded checkpoint_usec, rejects unexpected cost, sums plain/profiled checkpoint costs, validates forged window/mode totals, and reports strict-vs-periodic observation cost alongside (not inside) paid tick wall time.
CALLSITES: run_pair, compare_windows, compare_checkpoint_modes, live _step; updated all four known existing E fixture callers and new negative/oracle.
NEGATIVES: missing, negative, oversized, non-gate, wrong SourceClock, forged sums, strict/periodic mismatch.
LIMITS: No runtime Godot/Windows test; cost is wall-time not CPU; no performance improvement claimed.
NEXT ASTRA E: obtain actual same-seed 100/300/600/900 window timings and bounded internal N39 copy/Schema/N9 counters via read-only interfaces agreed with A/B; exact N38 parity and real restart.
