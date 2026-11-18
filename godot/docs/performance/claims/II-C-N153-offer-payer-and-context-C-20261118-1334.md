# II-C N153 offer-context paid dispatch
STATUS: IN_PROGRESS
OWNER: C
TIME: 2026-11-18 13:34 MSK
BASE_SHA: c1aa68545e4f51ac87482772dbcadd6d4b04f519
ASTRA: II-C ship/contract/dock/route caches — repeated N153 ship-by-offer dispatch observations
INTENDED_FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_offer_context.gd
SCOPE: hoist offer-invariant payer and quote proof; preserve ship-dependent top-up, fuel, posture, selector and strict tie-break; test positive and negative oracle.
EXPECTED_TEST: source-level targeted Godot regression, no Actions.
