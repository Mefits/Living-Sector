# Observer Industrial Visual V4

**Scope:** observer-only (JavaScript, CSS, HTML); no economic simulation, seeding, wallet, market or SQLite changes.

Changes:
- Distinguishable glyphs and tooltip type for stations, shipyards, mining/salvage, gas, refineries, factories, farms, storage and service structures.
- Major-site emphasis computed from a real station + 4 or more co-located facilities (**not a claim of political capital**).
- A shared real location can display a main marker plus a limited number of clickable small facility markers, with collision avoidance against planet symbols; actual ECS positions remain untouched.
- Compact breakdown and sorted facility selectors in the inspector, plus real owner/faction, state, crew count, reserves and permitted production-stat multiplier.
- No inferred station owner from ship affiliation. Unknown facility types degrade to a generic symbol.

This branch starts from the committed `feature/observer-s7-options-20261106` branch, **not** from the separately distributed Windows V3 archive. Do not overwrite a local V3 Observer directly with these individual repository files; the V4 Windows/UI patch archive separately retains the V3 camera, static planet textures and stable ship headings.

Integration: reconcile the V3 local artifact with this branch into one UI track before merging with the economy foundation. The server currently serves only the four original Observer assets, so no new network asset routes are needed.
