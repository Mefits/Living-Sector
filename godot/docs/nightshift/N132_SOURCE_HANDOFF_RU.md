# N132 — Module production catalog

Frozen source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`, `native/crates/sim_core/src/economy/module_production.rs`.

All ten T2/T3 recipes, exact inputs and installation costs, stock target 2, availability and proposed batch. Tier 1 is default, not manufactured. Dependency: atomic market supply+ModuleStock commit and refit payment; not a shipyard ship-building cycle.

Phase 1 only: independent GDScript state-in/result-out; do not connect to P1 or run large tests. Quick future checks: N131 coverage 50 stable, urgency 50 > urgency 0, 5% cap; N132 missing tools blocks engine_t2, one batch consumes all inputs; N133 no eligible refinery still advances timer, selected refinery damage is deterministic. **CODE_UNVERIFIED**: Godot parser/runtime not executed.
