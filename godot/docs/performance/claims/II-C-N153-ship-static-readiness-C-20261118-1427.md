# II-C N153 proposal-local ship readiness and route fuel inputs
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
TIME: 2026-11-18 14:27 MSK
BASE_SHA: 2d509506df2f757dae857951abd426a37a3bf923
ASTRA: II-C ship/contract/dock/route caches; eliminate repeated ship eligibility/dock/cargo/class checks across offers while preserving per-offer capacity, route and fuel gates.
INTENDED_FILES:
- godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd
- godot/tests/p2_perf_c_n153_ship_static_readiness.gd
EXPECTED_TEST: legacy uncached vs proposal-cached, changed ship state between proposals, stale dock, busy, cargo, class/fuel, capacity, route and winner parity.
RISK: no cache persists across propose(), World mutation or N38 restore.

CODE_SHA: 8ec27762f9186c0704d27c95d2e6f97b3d4fda2b
TEST_SHA: 660480541e61f8c292b17e451a858724a2a3429b
IMPLEMENTED:
- N153 propose() owns fresh per-call readiness and fitting dictionaries; no persistent World, N38 or cross-tick cache.
- Repeated busy/location/dock/cargo checks and Catalog fitting resolution across contracts for the same ship now reuse detached scalar results; capacity and route/fuel/BT/payment remain offer-specific.
- Both _ready_ship and propose callsites wired, preserving original rejection order and lazy fitting after successful route geometry.
TEST: NOT_RUN
CODE_UNVERIFIED: true
PERFORMANCE_NOT_MEASURED: true
ORACLE: 100 distinct ships, six quantities, paid/busy transit, invalid dock/ownership location, nonempty/non-Dictionary cargo, capacity, fitting and next-proposal invalidation.
RISK: Godot runtime not executed; exact N153 selection and N38 restart still require acceptance.
NEXT: II-C remaining N153 eligible-ship/contract candidate scans and route invalidation, then same-seed 24/100/500 paid-tick parity.
