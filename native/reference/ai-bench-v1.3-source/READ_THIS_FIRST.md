# Source reference, not integrated game code

This is the original LS-AI-Galaxy-Bench-v1.3 Rust **research** source, including its own Cargo.lock, adapters, and license notices. It is intentionally NOT a member of the Galaxy workspace and does NOT drive live factions yet. The integration must adapt the actual algorithm APIs to `crates/sim_core/src/strategy/planning` and native Genesis actions; do not reuse synthetic benchmark world transitions.

Preserve the original versions (htn 0.2.1, telic 0.1.0, cranium 0.3.0) when evaluating algorithms.
