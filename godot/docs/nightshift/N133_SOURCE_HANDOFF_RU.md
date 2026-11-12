# N133 — Environmental accidents

Frozen source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`, `native/crates/sim_core/src/strategy/director.rs::environmental_events`.

Deterministic owned-refinery selection by ID, condition >0.35, damage 0.30 floored at 0.10, next crisis tick +2400*max(mult,1), event record. Dependency: authoritative facility operations and director next_crisis_tick. No fabricated repair or goods.

Phase 1 only: independent GDScript state-in/result-out; do not connect to P1 or run large tests. Quick future checks: N131 coverage 50 stable, urgency 50 > urgency 0, 5% cap; N132 missing tools blocks engine_t2, one batch consumes all inputs; N133 no eligible refinery still advances timer, selected refinery damage is deterministic. **CODE_UNVERIFIED**: Godot parser/runtime not executed.
