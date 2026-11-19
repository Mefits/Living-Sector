# Astra III/E — live A/B paid-phase and callsite attribution
STATUS: IN_PROGRESS
OWNER: E
TIME: 2026-11-19 13:50 Europe/Moscow
BASE_SHA: 5d1fe2e04a313134d068dc0bea5f44789441cfa7
ASTRA: bounded paid-tick early/late benchmark, phase avg/p95 and real callsite attribution, same-seed N38 parity.
INTENDED_FILES: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/scripts/sim/phase2/n158_live_ab_phase_acceptance.gd; godot/tests/p2_perf_e_live_ab_phase_acceptance.gd.
EXPECTED: integrate 100 paid-tick phase distributions and per-call samples into live A/B, independently verify timing/cadence totals and parity, reject forged/partial phase coverage and mutation aliases.
RISK: phase cadence can skip ticks; no invented calls, no modification to authoritative World or N9.
TEST: NOT_RUN
