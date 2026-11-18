# Astra II-B — N144/N151 colony approval owned writes
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
START: 2026-11-19 01:12 MSK
BASE SHA: 425349b770ce55fee7ec9c95ec345abd299ff135
ASTRA: II-B bounded owned write sets, real N39 L129/L196, full Schema oracle, rollback/alias.
CODE SHA: d52a6c97d7d7649e6c92d750f2b0f7bfb5f10631
TEST SHA: a8fcc294327d64145d2c671aefc4949e3184ecf7
TEST: NOT_RUN
CODE: UNVERIFIED
PERFORMANCE: NOT_MEASURED

Changed godot/scripts/sim/phase1/n39_native_world_production.gd:
- Shared real _colony_approval_owned_stage() for N144 and N151 approval.
- Both callers now detach only append-only construction_sites and construction_receipts registry roots rather than deep-copying all historical nested site/receipt rows.
- N144 deep-detaches only the faction director whose strategic memory is updated; when no memory is supplied, research_directors stays read-only.
- Both real paths retain original duplicate/receipt/source recheck, full Schema.validate, Schema.accounts, N9 no-money and atomic World publication. No mutable historical row is edited by these append-only callers.

Test godot/tests/p2_perf_a_n144_n151_colony_approval_owned.gd:
- Invokes actual N39 stage helper and compares against legacy full-deep-domain oracle for single/multiple approvals and with/without memory.
- Negative duplicate, missing director, simulated late validation failure, changed-row alias isolation, unchanged historical data, N9/ships/markets invariants.
- Does NOT execute the complete N144/N151 production phase or full Schema with a complete physical fixture; manual Godot same-seed N9/N39/N38 checkpoint still required.
- No Actions started.

NEXT ASTRA II-B: inspect remaining N39 construction/escrow full-domain detach paths, select a distinct real hot paid stage with owned rows and complete production oracle; do not repeat N141, N121 or B4/N100.
