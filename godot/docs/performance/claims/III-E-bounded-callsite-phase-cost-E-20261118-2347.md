# Astra III/E — bounded N158 callsite cost attribution
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
START: 2026-11-18 23:47 MSK
BASE SHA: 31414c23c9c9f0cc124887f6724456195c67cb21
ASTRA BACKLOG: E — real N158 paid-tick measurement, bounded early/late comparison, overhead and exact parity gates; next open substage: bounded per-callsite cost distribution and cadence-aware direct/thread comparison.
INTENDED FILES: godot/scripts/sim/phase2/n158_timed_phase_probe.gd; godot/scripts/sim/phase2/n158_direct_threaded_acceptance.gd; godot/tests/p2_perf_e_callsite_cost_oracle.gd; godot/tests/p2_perf_e_real_direct_threaded_oracle.gd.
EXPECTED: bounded measured calls and per-call p95/max for real integrated phase callsites, strict paired coverage and exact-checkpoint gating, positive/negative oracle; no N9/N39/worker UI mutation.
TEST: NOT_RUN

CODE SHA: 9d0c05139d42ad79186a01ff0f0c8cd336f18fd7; c62e83dbe047df61ffaedda82c103b63032499ff; 44f13780ba867a64f162a9aa158da719fb207d91; 0ec74c005d93e6ce97dd36336647865335ea2e23
TEST SHA: 7e9940067476bea35b822c870006df222e441b06
TEST: NOT_RUN (no Godot execution; CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED)
RESULT: Instrumented actual N158 integrated-phase invocations in 100-row bounded rolling windows; preserved per-call duration, call count and cadence, detached nearest-rank p95/max/average. Owner exports scalar cost report only at committed checkpoints. Real direct/thread harness now rejects missing/forged callsites and mismatched cadence, requires exact checkpoint gate and independent phase aggregates. Negative oracle checks missing checkpoint, forged calls, forged totals/p95, missing phase, alias, aborted tick.
RISK: Execution/parser and actual 100/300/600/900 runtime cost remain unverified. Wall elapsed, not CPU. No claims of speedup.
NEXT ASTRA E: bounded instrumentation of copy/Schema/N9 callsites through E-owned read-only adapters where available, compare early/late cost against real N39/N9 growth and strict parity; coordinate A/B ownership without editing their files.
