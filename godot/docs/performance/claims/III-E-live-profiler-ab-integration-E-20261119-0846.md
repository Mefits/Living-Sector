# Astra III/E — live independent N158 profiler on/off A/B
STATUS: IN_PROGRESS
OWNER: E
TIME: 2026-11-19 08:46 MSK
BASE HEAD: 9d103a08ca5942a0a8d3b25ec7f71d1a8b7853fb
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E bounded paid-tick benchmarking and measured profiler overhead; continuation of III-E-instrumentation-ab-overhead-E-20261119-0751.
GOAL: wire two independently seeded real N158 runtimes (unprofiled N158 production and timed phase probe) into existing bounded A/B acceptance; actual paid steps and exact N38 checkpoint parity, early/late windows, fail-closed positive/negative oracle, optional 900-tick run with wall budget. No worker/UI or foreign-domain writes.
INTENDED FILES: godot/tests/p2_perf_e_live_instrumentation_ab.gd; godot/tests/p2_perf_e_live_instrumentation_ab_negative.gd; potentially own n158_instrumentation_ab_acceptance.gd.
TEST: targeted headless Godot positive/negative; NOT_RUN until execution. No GitHub Actions.
