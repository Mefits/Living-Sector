# II-C N80 repeated physical route legs
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-19 06:31 MSK
BASE_SHA: 2ec5077b50873fdca5f5bfa07896a3ee92ffae15
ASTRA: II-C ship/contract/dock/route caches, route cached-vs-uncached oracle, strict physical fuel parity.
INTENDED: godot/scripts/sim/phase2/unified_n80_ship_route_fuel.gd; godot/tests/p2_perf_c_n80_route_leg_cache.gd
PLAN: Call-scoped physical-leg cost reuse across repeated route segments with no World persistence; preserve error order, float summation, real N14 costs, negative geometry/clock/fuel cases.
TEST: NOT_RUN
