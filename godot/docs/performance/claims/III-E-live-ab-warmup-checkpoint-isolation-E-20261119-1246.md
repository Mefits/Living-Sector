# Astra III/E — isolate warmup checkpoint work from measured paid windows
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-19 12:46 MSK
BASE SHA: f36296720f5f1f215d5a1043c5d437343927ac59
ASTRA: bounded N158 paid-tick benchmark, measured instrumentation overhead, same-seed parity and checkpoint attribution.
INTENDED FILES: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/tests/p2_perf_e_live_ab_warmup_isolation.gd; optional E-owned benchmark adapter.
ISSUE: existing warmup executes _plain_step/_profile_step which produce full checkpoint every 1/10 ticks despite warmup not requiring parity; that unmeasured work contaminates later measured windows and makes strict vs periodic modes non-equivalent during warmup. Need explicit checkpoint policy, independent warmup boundary parity and negative/oracle regression; no economy changes.
EXPECTED: warmup paid ticks still executed exactly, no warmup checkpoint per tick, one explicit boundary oracle, measured windows preserve all gates and cost accounting.
TEST: NOT_RUN; CODE_UNVERIFIED.
