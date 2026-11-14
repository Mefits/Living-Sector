# Living Sector P2 — N142/N4 authentic Rust SQLite return corridors (14 Nov 2026)

PR #249; base head `c5f28ea`, branch `integration/godot-phase2-unified-20261113`.

## Why this block
- **Ground truth:** frozen Rust `native/crates/sim_db/src/seeder.rs` (section 5, travel routes) inserts EVERY authentic `worlds/*.json::travel_routes` entry twice into SQLite with `ON CONFLICT(from_location,to_location) DO UPDATE`: forward AND reverse. The physical Rust `WorldRegistry` operates on those database rows, not the unexpanded JSON.
- Existing Godot `godot/scripts/sim/world_registry.gd` used `RouteGraph.load_worlds(seed.worlds)` without the Rust DB seeder expansion, so all 12 source JSON edges were treated as 12 directed one-way flight legs. Autonomous N14/N153 could not return along valid Rust-native corridors.
- In the eight **actual frozen Galaxy 0.6.7** world JSON files: exactly **12 input corridors**, **24 native SQLite directions**, **12 authentic existing nav locations**. We independently checked this count from the source files, plus alpha-station→earth-station 120 and pirate-outpost→lane-barnard→lane-tau→lane-epsilon→earth-station 855.

## Changes
1. `route_graph.gd::load_worlds(worlds, native_seeded_db=false)` retains exact directional raw JSON graph by default (N58/N59/N56 fixtures unaffected). In **native seeded DB** mode, reproduces the two Rust seeder UPSERTs per source edge with last-upsert-wins distance and provenance; never derives route distance from render/world position and never adds new locations.
2. `world_registry.gd` uses `load_worlds(seed.worlds, true)` for the single physical N4 graph shared by N14/N153/ship transit and colony planning. Original source entities, population and funds unchanged.
3. `route_graph_audit.gd::audit(..., native_db_mode=false)` keeps exact JSON audit by default and can explicitly verify the seeded DB bidirectional projection, including latest explicit opposite-direction upsert.
4. Updated N4 acceptance `n4_registry_routes_check.gd` to assert 24 real Rust DB route rows and a 855-cost pirate→Earth return chain; existing directional raw N58 and N56 tests still retain their original assumptions. Extended P2 construction Gate4: a remote N91 engineer must now be able to RETURN along the native seeded Sol corridor rather than be blocked as invented.
5. New `p2_native_seeded_route_parity_check.gd`: checks 12 raw/24 DB rows and all actual pairs, independent N58 audit in both modes, one genuine N14 return departure on an original Alpha Centauri hull with real N43 positions, unchanged N39 input, and explicit no ghost `mars-colony` node or route.

## Limitations / next priority
- Source parity of graph creation has been implemented, but **Godot was not executed here**. Static brackets/strings, all preloads and indentation PASS. **GitHub Actions = 0.** Test is **ADDED, NOT RUN**. Do NOT report that an autonomous contract was completed.
- Correcting the reverse graph does not create a demand/contract; the user's tick 212 showed **N104=0, N153 accepted=0, N14 departures=0**. N135 requires demand and actual physical stock shortage. Run ONE coordinated local Godot integration gate on a real paid freight path, avoiding Actions.
- **No `*-colony` locations** exist in original source JSON/SQLite seeder, and no destination route is implied by a reversed edge. The new N151 funding approval still correctly rejects missing colony navigation; source Rust colony strategy also appears unable to open a clean-seed project without native registration. Need source-backed colony-node lifecycle decision before adding it; no imaginary direct Mars corridor.
- No edits to frozen Rust 0.6.7 source, financial formulas, techs, balance, unobserved new routes or actual N38 saves.
