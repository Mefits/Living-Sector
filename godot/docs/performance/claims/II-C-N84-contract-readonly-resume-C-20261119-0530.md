# II-C N84 contract read-only gates and resume ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 05:30 Europe/Moscow
BASE_SHA: 911e7c56562431e8cffd70c3640e82aa39c3e6e4
ASTRA: II-C ship/contract/dock/route caches; N84 BT/world read-only/owned boundary.
CODE_SHA: b415b1626524f702abc83ab59cd297e115ddbb0a
TEST_SHA: 4fde6509b8bd359c4db063006b1fd7943e23e201
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_contract_readonly_resume.gd
CALLSITES: N84.propose N104Resume.propose, Bt.validate, Bt.tick, _owned_fleet_row.
RESULT: Contract saved BT validated on original read-only row before nested copy. N104 missing-plan resume attempts on original read-only row; ownership only on successful plan. Existing active autonomous BT validation remains before ownership; BT tick and dispatch still operate exclusively on owned row. All result rows detached by _owned_fleet_seal.
NEGATIVES: Invalid contract BT exact reason/actor, missing source/route no fabricated command, nested cargo/memory/transaction isolation and legacy seal oracle.
TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
RISK: N104Resume.propose must remain read-only on failure; runtime regression not executed. Confirm paid contract success and BT/cargo/fuel/route replay on Godot.
NEXT: II-C N84/N153 real paid 24/100/500 fleet fixture and dock occupancy cached-vs-uncached; preserve N9/N38/BT exact parity.
