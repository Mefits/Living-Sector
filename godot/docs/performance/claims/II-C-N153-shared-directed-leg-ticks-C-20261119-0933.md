# II-C — N153 shared directed-leg tick geometry
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-19 09:33 MSK
BASE FILE SHA: 7f8ea3d9c80ddb9203c9080e04f8f9d7d73501f9
ASTRA: C fleet/contracts/route graph — eliminate repeated N14 geometry calculations across offers, preserve cached-vs-uncached fuel and route parity.
INTENDED FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_shared_leg_ticks.gd
EXPECTED: proposal-local directed-leg geometry cache across distinct offers; original per-edge arithmetic and errors; negatives for reverse direction, speed, geometry, missing endpoints and new proposal.
TEST: NOT_RUN
