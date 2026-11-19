# Astra III/E — bounded phase growth attribution

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 22:54 MSK
BASE_SHA: b8719d7fbeed8f06d297b1839e564ae1fd1b790f
ASTRA BACKLOG: E bounded N158 paid-tick phase/callsite benchmarking; compare early and late windows with same seed and exact direct/threaded checkpoint oracle.
INTENDED FILES: godot/scripts/sim/phase2/n158_phase_growth_acceptance.gd; godot/tests/p2_perf_e_phase_growth_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
EXPECTED: paired phase-window growth attribution, cadence-normalized elapsed cost, strict negative fixtures for forged/missing/mismatched windows and bounded output. No CI/Actions.

CODE_SHA: 8c224637e73dc79dac87d561cbc29cc8d6919622, 15a418ee8de32ff84684461d2c0c4ae7df7ada4d
TEST_SHA: 7bb0a26881f541e1860bd9ce151ed93951f32104
TEST: NOT_RUN (Godot unavailable here; no Actions requested)
CODE_UNVERIFIED: true
RESULT: Real paid-tick direct/threaded oracle now records cadence-normalized, exact-checkpoint-gated phase cost growth for independent 100-tick windows at 100/300/600/900. Includes per-call/per-active-tick/per-paid-tick ratios, validation and negative fixtures; no simulation/World mutation.
NEXT_ASTRA_E: bounded instrumented callsite costs for copy/Schema/N9 where supported by actual N158 calls; validate against exact same-seed checkpoint and negative fixtures, without changing foreign subsystem ownership.
