# II-C N140 mixed AgentLod owned gate
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 11:25 Europe/Moscow
BASE_HEAD_SHA: 09bf4f1fd6226727e7ccf1a6aa87443599e65c9f
CLAIM_SHA: 05103c535cf417847ca49479b6b468700793c3de
CODE_SHA: 866125423666da0b19f3350ec959261abcb178d0
TEST_SHA: 4a53d26508212d3479475d01c4e1e1bd448b3b68
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
ASTRA: II-C fleet/contract/dock/route caches; N140 agent-map/ship redundant copies.
FILES:
- godot/scripts/sim/phase2/unified_n140_ship_lod_phase.gd
- godot/tests/p2_perf_c_n140_mixed_owned_gate_oracle_20261118.gd

RESULT: The real mixed-AgentLod N140 stage no longer materializes a transient full agent map or invokes SourceLod.recompute and ship_gate, each of which recursively duplicates that map. A single detached fleet now receives source set_divisor and try_fire operations in sorted ship order, with per-position stats and original skipped-tick decisions. All source rows/observer inputs validated before writes. No N39/N9/N158 edits.
ORACLE: Independent reconstruction of original SourceLod.recompute + ship_gate for 120 distinct ships, 2 observer sets, ticks 1/2/7/50/100/150, multipliers 1/2; exact fleet, fire map, stats and changed flags; negative invalid cursor/transit/null lod and nested BT/cursor alias checks.
RISK: Godot parser/runtime and same-seed N38 parity unverified; SourceLod original error reason strings may differ on malformed inputs, while rejection is preserved. No measured speed claim.
NEXT ASTRA C: Inspect actual N84/N140 callsites for remaining full-fleet copy boundaries and route/contract invalidation; implement an owned-boundary or versioned cache fix only with positive and negative paid cargo/route/BT oracle. Run targeted tests and same-seed 100/600/900 later on user-approved checkpoint; do not launch Actions now.
