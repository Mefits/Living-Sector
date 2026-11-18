# Astra III/E — bounded phase growth attribution

STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 22:54 MSK
BASE_SHA: b8719d7fbeed8f06d297b1839e564ae1fd1b790f
ASTRA BACKLOG: E bounded N158 paid-tick phase/callsite benchmarking; compare early and late windows with same seed and exact direct/threaded checkpoint oracle.
INTENDED FILES: godot/scripts/sim/phase2/n158_phase_growth_acceptance.gd; godot/tests/p2_perf_e_phase_growth_acceptance.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
EXPECTED: paired phase-window growth attribution, cadence-normalized elapsed cost, strict negative fixtures for forged/missing/mismatched windows and bounded output. No CI/Actions.
