# III/E — paired paid-tick drift oracle
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 04:47 MSK
BASE_SHA: c318e99ab306f8a532ab9438d12b31b10ef6d5d4
ASTRA: III / long-run evidence — same-seed bounded early/late paid-tick and direct-vs-threaded comparators; exact N38 parity.
INTENDED: godot/scripts/sim/phase2/n158_paired_paid_tick_drift.gd; godot/tests/p2_perf_e_paired_paid_tick_drift.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd
RESULT: compare aligned individual paid ticks, bounded per-tick overhead/drift and positive/negative oracles, without treating wall as CPU, no World retention.
TEST: targeted headless GDScript regression (NOT RUN until permitted).
RISKS: source tick and timing attribution; no changes to authoritative simulation.
