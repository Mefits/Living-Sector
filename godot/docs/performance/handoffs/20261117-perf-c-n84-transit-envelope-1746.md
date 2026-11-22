# PERF C handoff — 2026-11-17 17:46 MSK

CODE COMMITS: 87f506c7820d6be5ab5d1d5c3e27f198825b8449, f0f2953eaa09585ea3c35d6265c06985c9240064.
TEST COMMIT: f935e191430ddb217a3ee8511ae09cee50d7cef4.
FILES: phase2/unified_ship_phase.gd; phase2/unified_ship_ai_execution.gd; tests/p2_perf_c_n84_envelope_oracle_20261117.gd.

N84 preview_depart previously traversed all ship rows on every Travel leaf to verify identity/transit and compute max token. Proposal-local envelope now reuses this check while token and fleet cardinality remain stable; N84 keeps original selected-ship restore, ShipTransit token restore, paid departure command, and fallback. Token changes invalidate. No N39/N9/N158 edits.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured CPU improvement, no same-seed or N38 parity evidence. New test helper compares cached/uncached outputs, including stale token; needs integration into runnable test harness. Risk: identity/transit mutated without token or fleet-size change inside a single N84 proposal could invalidate cached envelope; inspect mutation sites and expand invalidation before acceptance. Other-ship invalid-state behavior still differs from full depart() baseline as in previous C changes.

NEXT: source-level profile N84 travel preview calls and dock_queue 100/600/900, negative mutation oracle, real Godot test and exact BT/RNG/contract/cargo/N38 replay before acceptance. Do not duplicate Astra commits 99ab25e9/1676db61.
