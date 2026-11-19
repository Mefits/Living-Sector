# Astra III/E — bounded instrumentation A/B overhead
STATUS: IN_PROGRESS
OWNER: E
TIME: 2026-11-19 07:51 MSK
BASE HEAD: 2733d339d99f3ad0190252193c81d926fa2a4018
SOURCE: ASTRA_FIVE_SHIFTS_RU.md E paid-tick benchmark and measurable profiler overhead.
INTENDED FILES: godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd; godot/tests/p2_perf_e_instrumentation_ab_overhead.gd; E-owned benchmark acceptance callsites.
EXPECTED: paired exact same-seed windows with bounded samples, deterministic parity gate, overhead isolation and positive/negative oracle; no N39/N9 writes.
TEST: NOT_RUN
