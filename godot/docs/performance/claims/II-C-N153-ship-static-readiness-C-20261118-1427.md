# II-C N153 proposal-local ship readiness and route fuel inputs
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-18 14:27 MSK
BASE_SHA: 2d509506df2f757dae857951abd426a37a3bf923
ASTRA: II-C ship/contract/dock/route caches; eliminate repeated ship eligibility/dock/cargo/class checks across offers while preserving per-offer capacity, route and fuel gates.
INTENDED_FILES:
- godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd
- godot/tests/p2_perf_c_n153_ship_static_readiness.gd
EXPECTED_TEST: legacy uncached vs proposal-cached, changed ship state between proposals, stale dock, busy, cargo, class/fuel, capacity, route and winner parity.
RISK: no cache persists across propose(), World mutation or N38 restore.
