# Astra III/E — bounded N158 callsite cost attribution
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 23:47 MSK
BASE SHA: 31414c23c9c9f0cc124887f6724456195c67cb21
ASTRA BACKLOG: E — real N158 paid-tick measurement, bounded early/late comparison, overhead and exact parity gates; next open substage: bounded per-callsite cost distribution and cadence-aware direct/thread comparison.
INTENDED FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_callsite_cost_oracle.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd.
EXPECTED: bounded measured calls and per-call p95/max for real integrated phase callsites, strict paired coverage and exact-checkpoint gating, positive/negative oracle; no N9/N39/worker UI mutation.
TEST: NOT_RUN
