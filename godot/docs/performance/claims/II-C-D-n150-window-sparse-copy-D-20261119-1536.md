# Astra II-C D — N150 consumption-window bulk ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
DATE: 2026-11-19 15:36 MSK
BASE SHA: 54dddfafa5a1b5953d317beb935a2e9dc84b79e3
ASTRA: II-C market rosters / eliminate redundant materializations on paid market path.
CODE SHA: 44cb56596c6d70d106f26ad70a46e2b5a910eaa4
TEST SHA: 1c78f07a7b5ff30d0479f05938a2cec4b7fad08d
TEST: NOT_RUN
PERFORMANCE: NOT_MEASURED
FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_sparse_window.gd
CALLSITE: tick_one_market -> _owned_flow_without_expired -> observed demand / prices / shortage. For every fully retained consumption window, validate and accumulate in source order, then native bulk deep-copy Array once rather than per-sample GDScript deep duplication. Mixed windows still copy only survivors.
ORACLE: independent original loop with fully retained, mixed, expired, empty, cutoff, nested alias and invalid expired/NaN/typed row negatives.
INVARIANTS: identical source iteration/float accumulation, no borrowed output, same error ordering and cutoff. No cross-tick cache.
RISK: Godot parser/runtime not executed; bulk copy benefit and phase cost require Windows same-seed measurement. This is a narrow substage, not proof of overall late-tick acceleration.
NEXT: Astra II-C Head/N121 cross-faction facility/contract read-view with invalidation at actual calling cycle; preserve wrong-market-owner negative and decision order.
