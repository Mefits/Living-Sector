# N131 — Price engine

Frozen source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`, `native/crates/sim_core/src/economy/price_engine.rs`.

Pure Rust coverage/pressure tiers, urgency, 5% tick clamp, 1–500 bounds and bid/ask spread. This computes price candidates; does not trade or move money. Dependency: market supply/demand and shortage_ticks from authoritative market.

Phase 1 only: independent GDScript state-in/result-out; do not connect to P1 or run large tests. Quick future checks: N131 coverage 50 stable, urgency 50 > urgency 0, 5% cap; N132 missing tools blocks engine_t2, one batch consumes all inputs; N133 no eligible refinery still advances timer, selected refinery damage is deterministic. **CODE_UNVERIFIED**: Godot parser/runtime not executed.
