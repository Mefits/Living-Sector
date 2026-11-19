# Astra III/E — live A/B checkpoint contamination control
STATUS: IN_PROGRESS
OWNER: E
DATE: 2026-11-19 09:47 MSK
BASE SHA: 2317c3f283af71bfabff5dc83993eedb2749ca99
ASTRA BACKLOG: bounded same-seed profiling and measured profiler overhead, exact N38 parity.
ISSUE: current live A/B calls full checkpoint after EVERY paid tick, perturbing memory/caches and making claimed profiler overhead inseparable from checkpoint workload.
INTENDED FILES: godot/tests/p2_perf_e_live_instrumentation_ab.gd, godot/tests/p2_perf_e_live_instrumentation_ab_negative.gd, godot/scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd
EXPECTED: measured step-only paired mode with periodic full-state parity gates; independent oracle rejects sparse/forged checkpoint coverage; existing strict per-tick mode retained.
TEST: NOT_RUN; CODE_UNVERIFIED
