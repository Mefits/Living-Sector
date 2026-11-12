# N44 — native research and station tier gate (CODE_UNVERIFIED)

Frozen Rust sources: `native/crates/sim_core/src/strategy/director.rs` (`TECHNOLOGIES`, 12 entries), `governance.rs` (`next_technology`, `ResearchMandate::validate`, `mandate_spending_gate`), `progression.rs` (tier slot limits, `upgrade_research_ready`).

Implemented: pure deterministic prerequisite traversal, mandate input validation, budget/floor preflight, station tier and occupied-slot checks. Uses RefCounted data with no SceneTree nodes or plugins. Unknown technology fails closed. No calendar/year gates.

**Not implemented:** actual paid research shifts, electronics consumption, ECS ownership, commander state, mandate persistence, treasury mutation, technology unlock or upgrade execution. Those remain owned by native Rust / later Godot world bridge. A successful preflight is not a receipt and must be revalidated by the authoritative executor. Campaign dependency metadata is not executable research.

Smoke: `godot --headless --path godot --script res://tests/n44_research_gate_check.gd`. Not run in this environment; do not count as Rust parity or VERIFIED. N39 production and N43 location resolver files untouched.
