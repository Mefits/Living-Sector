# N5 — Native commodities and recipes handoff

Status: **CODE_UNVERIFIED** (Godot executable not run). Rust source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`.

## Implemented
- 17 native commodities in the exact `Commodity::ALL` order, with Rust tiers and base prices; invalid slug rejected.
- 14 native recipes with exact facility names, ingredient amounts and multiple output quantities; T2/T3 retrofit IDs are preserved, **not automatically unlocked**.
- Pure fractional-batch transform: check inputs, optional capped output, optional price margin gate, then consume inputs before producing outputs. Reject invalid efficiencies and prevent free production on insufficient inputs.
- One short `SceneTree` smoke test for fractional production, multiple outputs, price gate, output cap and repeated execution.

## Boundaries and design choice
Godot `RefCounted` static catalogs + dictionaries avoid a separate `Node` per commodity/recipe. This is a data operation, **not** a running facility. Employment, wages, research permissions, module bonuses, real market storage, scheduling and transport must be validated by future N6/N9/N11 and not inferred from these recipes. Price threshold is passed as a parameter to support native live tuning; default 0.5 mirrors Rust. A Rust `f32` vs Godot float discrepancy at extreme values requires runtime parity checking. No third-party plugin is needed.

Reference patterns: [Godot RefCounted](https://docs.godotengine.org/en/stable/classes/class_refcounted.html), [Game Programming Patterns — Data Locality](https://gameprogrammingpatterns.com/data-locality.html). No per-entity `Node` objects are created.

## Morning verification
From the `godot` directory: `godot --headless --path . --script res://tests/n5_native_recipes_check.gd`. Verify exit code 0 and `N5 PASS`. Then integrate with a real facility only after research/module/workforce gates are ported.

No claim of Godot runtime verification, no merge.
