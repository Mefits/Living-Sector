# Astra III/E — bounded real paid-tick benchmark integration
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 12:48 MSK
BASE_HEAD: 8267fdf5ecb2b0b2a170e7f9496b0c480015991d
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E separate benchmarking duty; paid-tick 100/300/600/900, bounded phase/copy/size evidence and no fabricated worker metrics.
INTENDED FILES: godot/tests/p2_late_growth_capture.gd; godot/tests/p2_perf_e_live_bounded_capture_oracle.gd
GOAL: connect actual N158 paid step and completed checkpoint to bounded per-window timing and authoritative size probe, remove unbounded 2600 default and misleading window semantics, ensure invalid/timeout failure and negative oracle.
EXPECTED TEST: targeted positive/negative script, later Godot manual run (no Actions).

CODE SHA: e739207380903f7429387e5d14554a0f18bbb7db, e77e32e31001729fcfa64ded72689f2d416d4192, 0059a540ac1084cf4314f4954fbd44e690f9f17e, 03b89f93eb019f7fdd8e05cfbbf7c04c56a3b16c
TEST SHA: 12a654e07e6b6785e50ed6d82db3b3c49ced4a8b
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
IMPLEMENTED: executable p2_late_growth_capture now stops at 900/480s, advances exactly one real paid source tick per step, uses a bounded 100-row timing window and TimedN158 phase rows; snapshots only at 100/300/600/900, checks detached N39 domain, counts real N9 receipts and event_queue.pending, emits phase avg/p95/max and early/late deltas with wall-not-CPU labels. N38 checkpoint files retained at milestones. Positive and negative oracle covers gaps, bad phase, bad duration, missing authoritative counts, invalid tick and detached data. No worker/UI, World/N9/N38 source changes.
RISK: No Godot execution yet. Real phase window may reject a tick with no phase invocation; this is a conservative invalid result, not a fake PASS. N38/BT/RNG same-seed direct/worker parity remains separate acceptance gate; elapsed step includes orchestration and is NOT worker-request or CPU time.
NEXT ASTRA E: run targeted oracle and bounded real 100/300/600/900 source profile at user-approved manual checkpoint, then attach exact same-seed direct-vs-worker N38 parity to actual completed snapshots, no CI now.
