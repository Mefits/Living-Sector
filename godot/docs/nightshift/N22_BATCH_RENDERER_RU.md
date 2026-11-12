# N22 — Lightweight ship rendering boundary (CODE_UNVERIFIED)

Rust reference: `native/crates/sim_core/src/agents/ship/components.rs` (`ShipIdentity.id/class/faction_id`, `ShipPosition.position`, `system_id`). Rust keeps ship position, transit, cargo and AI separate by access pattern. This port deliberately projects **only** the current position and identity; it never estimates movement from routes or changes game state.

## Decision
Use one `Control._draw()` CanvasItem for all currently visible ships, not one Node per ship. This follows Godot's built-in custom 2D drawing and the data-locality approach in Game Programming Patterns. MultiMeshInstance2D is a later benchmark candidate, not installed: this first slice allows per-class symbols, selection and view-space culling without GPU-instance setup. No external addon is needed; LimboAI/GUT would not help this rendering boundary.

`ship_batch_model.gd` validates and atomically replaces an array of records, rejects duplicate IDs, non-finite positions and malformed records, stores stable sorted IDs and exposes viewport filtering and picking. `ship_batch_canvas.gd` transforms camera coordinates, culls, draws and emits selection. Its `set_ships()` input must be a **real** projection of the authoritative SimWorld ship position (not guessed from travel routes). No renderer is wired to the current P1 map because that model has no live N14/N21 ship state integrated; doing so would show misleading static seed ships.

## Test and limits
`godot --headless --path godot --script res://tests/n22_ship_batch_check.gd`

The test covers 10,000 record ingestion, visible rectangle, nearest picking, invalid/duplicate atomic rejection, screen/world transforms and camera invalid input. No Godot executable was run in the agent environment. Status remains CODE_UNVERIFIED. `visible_records()` and `pick()` are linear O(N); for 10k ships this is a starting point, **not a proven FPS benchmark**. Follow-up: connect N14 position snapshots and N21 docking to this view, then measure Godot Profiler on 100/1k/10k agents and only add spatial partition/MultiMesh if needed.
