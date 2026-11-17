# PERF C — N153 winner-only route detachment (17.11.2026 10:16 MSK)

CODE COMMIT: 083475da74fd80e705ce2d00ad73159bc827234c
TEST COMMIT: 39d112402ea92491f7f66c211eeaa98a4409a5b3
FILES: godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd; godot/tests/p2_perf_c_n153_winner_only_detach_20261117.gd

WHY: _ready_ship() formerly duplicated inbound/outbound arrays for every ready candidate, although most candidates lose N153 selection or N81 tie-break. Geometry is proposal-local and read-only; defer copying until a candidate actually reaches the published winner row. Existing fuel, cargo, paid quote, source posture, N153 selection, and strict profit tie-break checks remain unchanged. This avoids per-ready-candidate route-array allocations but does not change graph path computation or N39.

TEST: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. The new lightweight regression asserts the actual source ownership boundary, detached winner semantics, and presence of individual paid/fuel/cargo/tie-break guards. It is NOT an independent full N153 oracle and does not establish full parity. No Godot execution or measured speedup. No CI launched.

RISK: _ready_ship is a callable helper and now exposes proposal-local shared route arrays; callers must not mutate its returned paths. Within current propose() the only escape to result is copied. Validate any external direct consumers before acceptance. Run existing N153 tests and full exact N38/BT/RNG/contract/cargo parity before release.

NEXT: instrument real N153 candidate count vs winner count and path copy CPU time at paid tick100/600/900 same seed; run independent legacy-vs-optimized oracle, stale route/ownership and paid-contract negative tests. If negligible, move to measured N84 Travel/dock scan instead of further speculative caching. Do not duplicate 99ab25e9/1676db61.
