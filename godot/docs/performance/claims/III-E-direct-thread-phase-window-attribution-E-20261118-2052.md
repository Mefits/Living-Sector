# Astra III/E — direct/thread phase window attribution
STATUS: IN_PROGRESS
OWNER: E
DATE: 2026-11-18 20:52 Europe/Moscow
BASE_SHA: bd42def803faa24151dbf4d5c3b291920496a538
ASTRA: E measurement acceptance — true paid tick, phase/callsite avg/p95, bounded early/late same-seed direct/thread parity, overhead separated.
TASK: Connect existing N158 timed phase probe to actual direct and threaded benchmark owners, expose detached 100-paid-tick phase windows at checkpoints, gate them against exact source checkpoint parity and timing attribution, add positive and negative regression.
INTENDED_FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_direct_thread_phase_window.gd.
CHECK: source phase windows 100/300/600/900 with paid-tick coverage, exact checkpoint, missing phase, tick gaps, forged timing, and cross-owner phase reports; no Actions.
RISKS: diagnostic phase instrumentation overhead; opt-in benchmark only, no UI or default runtime change.
