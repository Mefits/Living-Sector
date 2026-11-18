# II-C N140 mixed AgentLod owned gate
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 11:25 Europe/Moscow
BASE_HEAD_SHA: 09bf4f1fd6226727e7ccf1a6aa87443599e65c9f
ASTRA: II-C ship/contract/dock/route caches; C remaining N140 agent-map/ships copies and cursor parity.
SCOPE: godot/scripts/sim/phase2/unified_n140_ship_lod_phase.gd; godot/tests/p2_perf_c_n140_mixed_owned_gate_oracle_20261118.gd
PLAN: Remove redundant full agent-map staging/copy and SourceLod ship_gate map copies for mixed LOD fleet by using original SourceLod cursor operations per ship. Preserve ordered validation, recompute stats, skip/fire decisions, cursor ownership and errors. Compare independent old SourceLod recompute+ship_gate oracle including malformed cursors, sleeping, observers, alias.
TEST: NOT_RUN; Actions forbidden.
