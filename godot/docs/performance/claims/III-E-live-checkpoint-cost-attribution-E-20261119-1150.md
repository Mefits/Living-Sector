# Astra III/E — live checkpoint observation cost attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 11:50 MSK
BASE_SHA: 5745020f7e5569f1475731b4fb30b52eae61a919
ASTRA: E bounded paid-tick profiling, measured observation overhead and exact N38 parity.
INTENDED: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_checkpoint_cost_attribution.gd
GOAL: measure checkpoint wall cost separately from paid tick and reject forged/missing cost accounting, compare strict and periodic real runs without conflating overhead with simulation speed.
RISKS: checkpoint cost depends on runtime memory; no Windows/Godot execution; no CPU-time claim.
EXPECTED: positive and negative/oracle tests for parity, counts, timing, boundaries; CODE_UNVERIFIED until executed.
