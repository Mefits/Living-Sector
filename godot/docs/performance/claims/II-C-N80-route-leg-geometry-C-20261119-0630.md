# II-C N80 repeated physical route legs
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-19 06:31 MSK
BASE_SHA: 2ec5077b50873fdca5f5bfa07896a3ee92ffae15
ASTRA: II-C ship/contract/dock/route caches, route cached-vs-uncached oracle, strict physical fuel parity.
INTENDED: godot/scripts/sim/phase2/unified_n80_ship_route_fuel.gd; godot/tests/p2_perf_c_n80_route_leg_cache.gd
PLAN: Call-scoped physical-leg cost reuse across repeated route segments with no World persistence; preserve error order, float summation, real N14 costs, negative geometry/clock/fuel cases.
CODE_SHA: 451d95b3338a6dcefc7c3113298fb2afd2e6e27f (initial b0bd3b7ee9c9103e1e92f06b40eb7c24e82b252d)
TEST_SHA: 485378c7dc9317d58bbe3aac0fad27e45ce2eb8f
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
RESULT: N80 physical preflight now caches validated directed leg tick counts within one invocation, including repeated BT candidate routes; retains per-occurrence fuel summation and original validation/rejection order. No persistent World/N38/graph cache. Test contains original uncached loop oracle, repeated legs, reverse edges, position mutation across calls, low fuel, invalid route/clock/BT leaves, input immutability.
RISK: Godot 4.7.2 parser/runtime and active paid-tick speed not yet measured. Cache benefits only repeated physical legs inside a single preflight, not unrelated N153 routes.
NEXT ASTRA II-C: N84/N153 paid contract/dock candidate hotpaths; provide valid 24/100/500 paid-ship parity fixtures and profile before/after.
