# Astra III/E — isolate warmup checkpoint work from measured paid windows
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-19 12:46 MSK
BASE SHA: f36296720f5f1f215d5a1043c5d437343927ac59
ASTRA: bounded N158 paid-tick benchmark, measured instrumentation overhead, same-seed parity and checkpoint attribution.

CODE SHA: ca77e7fbcce5142e25ad58f08d23bab79bdbbd2a
TEST SHA: 6b7c32f2fe923a1a690cfdb2c44b7906d4722ee1
FILES:
- godot/tests/p2_perf_e_live_instrumentation_ab.gd
- godot/tests/p2_perf_e_live_ab_warmup_isolation.gd

RESULT: Existing live benchmark warmup previously called _plain_step/_profile_step and built full checkpoint on every strict-mode warmup tick or every tenth periodic-mode warmup tick. Both modes still execute all actual N158 paid ticks; warmup now uses _step(..., capture_checkpoint=false), never builds a checkpoint on intermediate warmup ticks. An explicit full N38 parity oracle at the start of each measured window checks the two independently seeded runtimes, outside the paid-tick wall-time samples. The 100-tick measured window retains its 1/10 stride checkpoint gate and measured checkpoint_usec. Added counters verifying complete warmup paid-tick coverage and zero warmup checkpoint capture; no ownership, cadence or economy change.

POSITIVE/NEGATIVE REGRESSION: fake paid runner validates 200 warmup ticks without checkpoints, one explicit boundary checkpoint, measured 10-tick stride and cost fields, plus rejected stale SourceClock, refused step and failed tick. Live runner remains required for authoritative World/N9/BT/RNG parity.

TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. No GitHub Actions. Godot Windows run and strict/periodic same-seed cost measurement still required.
NEXT ASTRA III/E: connect bounded per-phase/callsite counters from A/B-owned interfaces into real 100/300/600/900 paid windows, with source-clock/parity/size attribution and negative oracle; do not edit A/B files.
