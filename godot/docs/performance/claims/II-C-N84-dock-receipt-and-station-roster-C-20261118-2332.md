TASK: II-C ship/contract/dock/route caches — N84 dock receipt + station roster hotpath
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-18 23:32 Europe/Moscow
BASE_SHA: eaf56e717cc441af005b0fd847e4251a3c0e7772
BRANCH: integration/perf-astra-5-workers-20261116
INTENDED_FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_roster_oracle.gd
GOAL: proposal-local dock receipt latest-tick index and station lookup roster, preserve station priority, live ownership/proof validation, deterministic order, negatives and cached-vs-uncached oracle.
TEST: NOT_RUN

CODE_SHA: e8be259ea8c221efb8276501134688e459b7bee0
TEST_SHA: 3219389a075444cd38533a8419dbfd3fd624ada1
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_roster_oracle.gd
RESULT: N84 DockWait paid-tick receipt scan now uses one per-proposal latest-tick index without materializing values() or colliding with ship IDs matching scratch keys. Contract dock station candidate is cached within proposal with live facility type/existence validation. Original latest-tick max and station priority retained.
ORACLE: 2000 receipts, repeated 40 queries, undock negatives, scratch-key ship ID collisions, missing/negative ticks, new-proposal receipt invalidation, station facility removal/type change, market ownership change between proposals.
RISK: Godot parser/runtime and full N38/BT parity not executed; live market ownership is assumed immutable within one synchronous propose(), as for existing passenger roster.
NEXT: II-C N84/N153 remaining dock occupancy and contract candidate scans; paid 24/100/500 ship exact BT/cargo/fuel/route parity and p95.
