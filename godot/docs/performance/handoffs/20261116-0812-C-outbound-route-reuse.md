# PERF C handoff — 2026-11-16 08:12 MSK

Branch: `integration/perf-astra-5-workers-20261116`; draft PR #262.

Code commit: `3deebb898832cbfbc9e934a3f54dde35542a0557`.
Test commit: `3604eb8002e12ec88c16701f42bd5a7bffeeeb76`.

Files:
- `godot/scripts/sim/phase2/n153_ship_eligibility_index.gd`: N153 outbound source→destination shortest_path is cached once per proposal-scoped endpoint index, with integer key 0 disjoint from String location IDs. First lookup still executes inbound before outbound. Subsequent ship origins compute independent inbound routes; route geometry and fuel checks remain per ship.
- `godot/tests/p2_perf_c_n153_offer_route_index_oracle.gd`: updated cache shape assertions; added distinct ship origin test.

Tests: NOT RUN (Godot unavailable); CODE_UNVERIFIED. Static review: no changed preloads or signatures; no World aliases stored; cache discarded after propose, including N38 restore. No measured speedup. No CI triggered.

Risk: Godot RouteGraph shortest_path for identical source and current ship location needs oracle execution; no change to contract acceptance, fuel calculation, deterministic tie breaks, or save schema intended.

Next: execute the oracle and compare N153 selection decisions with original on paid contracts and N38 restart; benchmark distinct origins with shared source/destination before expanding caching.
