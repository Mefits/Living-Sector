# PERF C handoff · 2026-11-16 07:14 MSK · N153 shared route geometry

Branch: `integration/perf-astra-5-workers-20261116` · draft PR #262.
Code commits: `08c372b4`, `cae3644e`, `32660c12`. Test commit: `4147bc97`.

Files:
- `godot/scripts/sim/phase2/unified_n153_contract_dispatch.gd`: reuse proposal-scoped route geometry across posted delivery offers with the same (source,destination) endpoints; still recheck each ship's cargo, active contract, fuel, faction posture, purchase price, payer balance and N153/N81 decision for each offer.
- `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`: endpoint-scoped cache accessor. No persistence across World changes, ticks or N38 restore.
- `godot/tests/p2_perf_c_n153_offer_route_index_oracle.gd`: directed route separation, same-offer geometry reuse, changed-position fresh-root invalidation and negative reverse-route oracle.

Test execution: NOT RUN (Godot unavailable). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured FPS/TPS claim. Source-level check: referenced RouteGraph and EligibilityIndex scripts fetched from the same branch, exact method signatures matched; helper stores no World references. No CI/Actions.

Expected benefit: fewer repeated `shortest_path` and physical-leg geometry evaluations for multiple contracts with the same endpoints in one N153 propose call. No change to contract acceptance or payment semantics intended.

Next: run targeted test, compare N153 cached/uncached candidates and full checkpoint on real paid contracts (24/100/500 ships), then N38 restart and negative tests. Measure duplicate-endpoint frequency before deciding whether to retain. No other worker-owned files touched.
