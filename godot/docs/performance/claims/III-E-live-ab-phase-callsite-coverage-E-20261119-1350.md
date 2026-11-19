# Astra III/E — live A/B paid-phase and callsite attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
TIME: 2026-11-19 13:50 Europe/Moscow
BASE_SHA: 5d1fe2e04a313134d068dc0bea5f44789441cfa7
ASTRA: bounded paid-tick early/late benchmark, phase avg/p95 and real callsite attribution, same-seed N38 parity.
INTENDED_FILES: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/scripts/sim/phase2/n158_live_ab_phase_acceptance.gd; godot/tests/p2_perf_e_live_ab_phase_acceptance.gd.
EXPECTED: integrate 100 paid-tick phase distributions and per-call samples into live A/B, independently verify timing/cadence totals and parity, reject forged/partial phase coverage and mutation aliases.
RISK: phase cadence can skip ticks; no invented calls, no modification to authoritative World or N9.
CODE_SHA: 2405db6b82180e91f531a6a6290e67e7737b8ba0, 324c3627c7becd73f8cefa369be90167b523976a
TEST_SHA: 2e6c7ffc4886e2c907389c8f787c59a9e96deb71
TEST: NOT_RUN (Godot/Windows not executed); CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
RESULT: Live independent same-seed N158 A/B benchmark now captures actual paid_phase_distribution and paid_callsite_costs at each 100-paid-tick boundary, validates all four phase totals, calls, active ticks, p95, SourceClock and nested wall-time accounting against the already exact checkpoint-gated A/B report. Outputs bounded detached scalars; rejects forged/missing/overcounted phase metrics. No authoritative state mutation.
NEXT ASTRA III/E: connect A/B owner-provided bounded World/Schema/N9 copy counters at exact same paid window gates, then manual Windows 100/300/600/900 comparison and N38 parity.

