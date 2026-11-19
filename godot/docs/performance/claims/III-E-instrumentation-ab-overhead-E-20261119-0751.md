# Astra III/E — bounded instrumentation A/B overhead
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: E
TIME: 2026-11-19 07:51 MSK
BASE HEAD: 2733d339d99f3ad0190252193c81d926fa2a4018
SOURCE: ASTRA_FIVE_SHIFTS_RU.md E paid-tick benchmark, measured profiler overhead.
CLAIM SHA: b4f706d17440d3a4a5aaf67d694baa3d818bfd26
CODE SHA: 0aa127857d57527a29ee0f837fc2ed38c9f1e859
TEST SHA: 6d9606bbf3226de7d621e5134f56d8995f19bdba
FILES: godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_instrumentation_ab_overhead.gd
RESULT: bounded 1..100 paid tick pairs, alternating arm execution, strict per-tick source clock and detached checkpoint callback, rejects failed/forged timing and partial checkpoints, reports paired p50/p95 and instrumented-vs-plain elapsed overhead and explicit measured instrumentation time; early/late window accounting. No authoritative world copies retained.
TEST: NOT_RUN (no Godot runtime executed); CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
LIMITATION: caller must supply independent same-seed real N158 step callables and exact full-state comparator; this is a usable acceptance driver, NOT YET wired into existing live 900-tick benchmark, therefore no claim of actual measured overhead or performance improvement.
NEXT: wire independent direct N158 runtimes with profiler enabled/disabled into this driver at 100/300/600/900 and compare N38 checkpoints and elapsed overhead, while preserving domain E ownership.
