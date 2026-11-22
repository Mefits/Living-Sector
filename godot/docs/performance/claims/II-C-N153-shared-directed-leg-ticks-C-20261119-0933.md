# II-C — N153 shared directed-leg tick geometry
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 09:33 MSK
BASE FILE SHA: 7f8ea3d9c80ddb9203c9080e04f8f9d7d73501f9
ASTRA: C fleet/contracts/route graph — avoid repeated N14 physical geometry calculations across distinct posted offers.
CODE SHA: fc5727446105e5e40ee1bb2e830ae7e33ba737e3
TEST SHA: 8be9738a250d7a355929a10d1ddcef53fec10cca
FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_shared_leg_ticks.gd
CHANGED: _ready_ship and propose share a proposal-local scalar directed-leg tick cache across offer-route indices; _physical_leg_ticks retains original velocity, invalid geometry and integer rounding. Original per-edge floating fuel summation, source rejection order, route-index scope, candidate order and payments are untouched.
TEST: NOT_RUN / CODE_UNVERIFIED / PERFORMANCE_NOT_MEASURED
ORACLE: 180 original-vs-cached fuel route/fitting/scale combinations; repeated leg cache, zero/negative/nonfinite geometry, zero speed/scale and new-proposal invalidation. Godot runtime and full paid BT/cargo/route replay remain pending.
RISK: no measured benefit yet; scalar cache keys use exact float values. Real N153 proposals and N38 restart must still be checked on Windows.
NEXT ASTRA II-C: remaining N84/N153 dock/contract paid-tick scans and full 24/100/500 active paid fleet parity (BT/cargo/fuel/routes/N38).
