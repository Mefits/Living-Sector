# Astra II-C / D — Head capture no-goal hotpath
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 13:40 MSK
BASE SHA: c1981cebc86a5fef6fb775a8b05ceceb1f4ec628
CODE SHA: 927b14a44114fc96f5e3de2cc6334b39a3416cab
TEST SHA: 8a4965481f4ee5523641a94a1e66974e938a363e
FILES:
- godot/scripts/sim/phase2/unified_native_hybrid_planning.gd
- godot/tests/p2_perf_d_head_no_goal_capture.gd

RESULT: Extracted shared _capture_preflight and gated expensive full World capture on actual SourceGoal before projecting facilities, markets, ships, contracts and recipes. Normal no-goal Head proposals now avoid repeated global registry scans; goal-bearing proposals retain original capture, search budget and source planning. Core preflight error precedence retained. No changes to World, prices, contracts, BT/RNG or N39.
TEST: NOT_RUN (Godot execution unavailable; no Actions per user).
PERFORMANCE: NOT_MEASURED.
RISK: malformed nested World rows that previously failed capture can now be ignored on no-goal decisions; validate exact failure semantics in full negative/legacy parity before acceptance.
NEXT ASTRA II-C: per-faction Head contract/ship roster shared read projection with ownership invalidation, only after identifying real repeated callsites and preserving exact ordering.
