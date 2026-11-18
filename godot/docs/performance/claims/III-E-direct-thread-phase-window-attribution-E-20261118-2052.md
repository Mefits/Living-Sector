# Astra III/E — direct/thread phase window attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
DATE: 2026-11-18 20:52 Europe/Moscow
BASE_SHA: bd42def803faa24151dbf4d5c3b291920496a538
ASTRA: E measurement acceptance — true paid tick, phase/callsite avg/p95, bounded early/late same-seed direct/thread parity, overhead separated.
TASK: Connect existing N158 timed phase probe to actual direct and threaded benchmark owners, expose detached 100-paid-tick phase windows at checkpoints, gate them against exact source checkpoint parity and timing attribution, add positive and negative regression.
INTENDED_FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/scripts/sim/phase2/n158_real_owner_thread_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_direct_thread_phase_window.gd.
CHECK: source phase windows 100/300/600/900 with paid-tick coverage, exact checkpoint, missing phase, tick gaps, forged timing, and cross-owner phase reports; no Actions.
RISKS: diagnostic phase instrumentation overhead; opt-in benchmark only, no UI or default runtime change.

CODE_SHA: 751e38213f0a581be11cfcf98a222ea58ffc4e4a, 4ef4b7ce4048863a81e06942961320ae5b063565, 49c1124fc8ad44f15d349d626482637dde0f4635, 702a60da430abb747e43c371af5a6eed3851e223
TEST_SHA: 80f63a675ba1ca78917dc8d7eb110fec053ee68a
FILES: n158_real_owner_thread_probe.gd; n158_direct_threaded_acceptance.gd; p2_perf_e_real_direct_threaded_oracle.gd; p2_perf_e_direct_thread_phase_window.gd
RESULT: Opt-in threaded owner now instantiates timed N158 subclass, emits bounded 100-paid-tick phase report at checkpoint steps. Direct benchmark uses same timed subclass. Real checkpoint and paid-tick timing reports are joined by verify_paid_phase_pair; four phase totals/avg/p95/max are checked against exact source checkpoint and full measured advance. Phase report generation is outside recorded advance/projection request timing. Both phase summaries detached; no authoritative World changes.
TEST: NOT_RUN (no Godot 4.7.2 executed). Positive fixture: exact 100-tick checkpoint and phase distribution. Negatives: cargo parity, missing phases, tick gap, forged p95, phase time > advance, missing paid tick, missing category.
RISKS: The existing timed phase probe requires each phase to be observed on every paid tick; cadence-skipped phases may cause rejection and require an E-owned explicit zero-call phase marker with honest cadence metadata after runtime verification. Wall time is not CPU time. Performance not measured.
NEXT ASTRA E: inspect real phase coverage from targeted Godot test, then connect callsite-specific bounded counters and same-seed early/late phase delta without touching other worker domains.
