# PERF C · N4 flat route cache detachment · 2026-11-16 10:33 MSK

Branch: `integration/perf-astra-5-workers-20261116`; PR #262.
CODE COMMIT: `fa5ddd910cf302b21275b2f8bc8a3e39f90ff08f`.
TEST COMMIT: `12014d7b3f6bbe0b5e772ca4ef290a8bcbbb7428`.

## Files
- `godot/scripts/sim/route_graph.gd`: on cache hit and cache insertion, replace recursive `Dictionary.duplicate(true)` with explicit detached shallow dictionary and independent flat `locations` Array. N4 route schema contains only scalar metadata and this flat Array. No World/ship/contract/ledger changes.
- `godot/tests/p2_perf_c_route_flat_detach_oracle.gd`: verify cache hit/miss independence, negative route reasons, and invalidation on successful topology reload.

## Status
TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (Godot executable not available in connector environment). Static review only. No measured TPS/FPS improvement; expected reduction of recursive copy overhead on N153 route-cache hits. No CI triggered. No change to tie-break, pathfinding, route graph, fuel, cargo, or paid-contract decisions.

## Next
Run new test and existing p2_perf_c route oracles in Godot 4.7.2; compare cached/uncached routes, then paid-contract N153 replay and N38 restart. Benchmark 24/100/500 ships before further optimization. No edits to N39/N9/N158/main.
