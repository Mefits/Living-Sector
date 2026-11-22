# Astra III/E — 600/900 bounded direct/threaded source parity
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 18:46 Europe/Moscow
BASE HEAD: a098a7224cd84b8c756b1bb1999830877f57674a
ASTRA: complete bounded early/late paid-tick profiling with exact direct-vs-worker checkpoints, N9/events/N39 growth and N38 restart at 600/900; no worker/UI changes.
INTENDED FILES: godot/tests/p2_perf_e_real_direct_threaded_oracle.gd; godot/tests/p2_perf_e_900_direct_threaded_oracle.gd
EXPECTED: opt-in 600/900 real source ticks, strict 480s wall cap, 100-tick windows at 100/300/600/900, checkpoint and size parity, negative fixtures, no Actions.

CODE SHA: 2dfc59ac4629ba5ed6a9e3f777beddc40abc1652
TEST SHA: 565e0e1b616d9c22a2b6ebd1a82f41d85fc44580; 3375f7c3ff8df8a74f45c1fd98772a831dc8b0f9
IMPLEMENTED: Existing executable p2_perf_e_real_direct_threaded_oracle.gd now supports opt-in LS_E_LATE_DIRECT_THREAD=900 with 900 real source ticks, 480000ms bounded wall budget, exact checkpoints at 1/20/60/100/200/300/600/900, 100-tick windows ending 100/300/600/900, adjacent and first-to-last attribution, detached N39/N9/events counts and successive growth, exact direct/thread checkpoint parity and N38 restore at 900. Default 100 and existing opt-in 300 unchanged. Each failed paid tick, timeout, missing checkpoint or mismatch exits FAIL rather than declaring parity.
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED. Added targeted fixture p2_perf_e_900_direct_threaded_oracle.gd for 600/900 exact snapshots, N9/event mismatches, wrong SourceClock, sparse paid-tick windows, impossible worker attribution and forged growth ticks. Fixture is synthetic only; actual benchmark uses real source ticks.
RISK: A 900-tick same-seed dual-owner run may exceed 480s, in which case FAIL/budget (not parity PASS). No CI/Actions run.
NEXT ASTRA E: inspect source tick versus request attribution at late checkpoints with a bounded single-backend profile and actual Godot test once permitted; compare N38/BT/RNG snapshots and phase p95 under measured budget.
