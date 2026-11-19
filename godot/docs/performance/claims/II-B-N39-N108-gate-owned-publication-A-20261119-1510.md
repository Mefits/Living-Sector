# Astra II-B — N39 N108 gate pair/jump owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
START: 2026-11-19 15:10 MSK
BASE SHA: 3ddb5f54cb59fb75ff175233872305cacb582c06
ASTRA: II-B bounded owned write sets, real N39 World deep:L196; preserve full Schema oracle.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n108_gate_owned_publication.gd
SCOPE: Both N108 explicit gate pair and paid gate jump publication; row-owned changed facilities/ship/new receipts; negative alias, forbidden mutation, rollback and deep-copy oracle.
RISKS: proposal stage may still deep-copy; no runtime verification, preserve N9 receipt and fee accounting.
EXPECTED: positive and negative targeted regression, full existing Schema and Ledger checks unchanged.

CODE SHA: 3c88a373862ca9c5cfb006d4873e862d787eb9df
TEST SHA: 6180945dc6e20ebc11ec5d927eac943cecc968e8
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
CHANGED: N39 apply_native_n108_gate_pair and apply_native_n108_gate_jump now publish _n108_owned_gate_publication after full original Schema/N9 checks, with a second full Schema oracle on owned candidate and accounts equality for paid jump. The helper deep-detaches only two paired gates or one charged gate+ship and the new receipt; rejects unrelated proposal mutations, receipt history changes and missing/duplicate IDs. Negative and positive old-deep-copy oracle tests added.
RISK: N108.stage may still deep-copy full World; full-dictionary equality costs O(World size), so speedup is unmeasured. Test needs actual Godot parser/run and same-seed N38 restart before verified.
NEXT: Astra II-B N39 L129/L196 repeated world_snapshot readsites and paid stages, choose an unclaimed source-stage deep copy with proven ownership; preserve Schema/N9/rollback.
