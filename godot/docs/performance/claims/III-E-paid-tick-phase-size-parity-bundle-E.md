# ASTRA III / E — paid-tick phase + size + parity acceptance bundle

STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 11:50 MSK
BASE HEAD: 8bcae0e3f98701d452d9ac4e67cd18b9aa095c77
ASTRA: E bounded benchmarking protocol, paid-tick phase attribution, authoritative size counters and same-seed exact N38/BT/RNG checkpoint parity.
INTENDED FILES: godot/scripts/sim/phase2/n158_paid_tick_acceptance.gd; godot/tests/p2_perf_e_paid_tick_acceptance_bundle.gd
EXPECTED: complete 100-paid-tick windows only; direct/worker compare with detached exact checkpoint oracle, phase and request attribution, size evidence, negative coverage and alias tests. No World mutation, no CI.
