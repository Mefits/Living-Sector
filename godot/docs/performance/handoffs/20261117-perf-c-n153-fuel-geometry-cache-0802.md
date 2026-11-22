# C handoff — 17.11.2026 N153 fuel geometry

CODE: 83eb3b79918647255d2f2cf537659d6f3a7465c6, cdbdb10839f1fb2be6e0aed76f1db55c1a663cd5
TEST: 94ecfe889f45aaf7d9004f6a9be16a7a891fc4e7
BRANCH: integration/perf-astra-5-workers-20261116 (PR #262)

FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_fuel_geometry_oracle_20261117.gd

WHY: N153 evaluates complete directed-leg fuel requirements per ship per offer. The route geometry was proposal-scoped already, but every ship with identical origin/speed/fuel rate recomputed all legs. This change caches the scalar flight cost/error for identical (origin,speed,rate,tick_scale) within each source/destination proposal, preserving all per-ship cargo, contract, ownership and fuel checks. Cache uses integer -1 in existing route-index dictionary, disjoint from string location IDs and existing integer 0/1 route entries. No persistent cache, World write or N38 change.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED. Test compares optimized with fresh uncached oracle, low fuel, speed variants, changed positions in a fresh proposal, cargo and active paid contract. Requires Godot parser and targeted runtime validation before acceptance; fixture class name should be checked against live Catalog if test fails. No measured speedup claimed. Baseline #43972442164 predates this patch.

NEXT: run targeted oracle and bounded same-seed early/late N153 site timing, paid-tick p95, route leg counts; reject if negligible or parity differs. Full N38/BT/RNG/cargo/contract parity and Windows soak remain pending.
