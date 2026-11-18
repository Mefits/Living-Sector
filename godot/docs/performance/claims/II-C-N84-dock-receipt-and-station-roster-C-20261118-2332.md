TASK: II-C ship/contract/dock/route caches — N84 dock receipt + station roster hotpath
STATUS: IN_PROGRESS
OWNER: C
START: 2026-11-18 23:32 Europe/Moscow
BASE_SHA: eaf56e717cc441af005b0fd847e4251a3c0e7772
BRANCH: integration/perf-astra-5-workers-20261116
INTENDED_FILES: godot/scripts/sim/phase2/unified_ship_ai_execution.gd; godot/tests/p2_perf_c_n84_dock_roster_oracle.gd
GOAL: proposal-local dock receipt latest-tick index and station lookup roster, preserve station priority, live ownership/proof validation, deterministic order, negatives and cached-vs-uncached oracle.
TEST: NOT_RUN
