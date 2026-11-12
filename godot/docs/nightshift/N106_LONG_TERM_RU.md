# N106 — Persistent production objective

Exact Rust source: `native/crates/sim_core/src/strategy/long_term.rs`. Maintains committed objective across head policy changes, only completes on actual post-creation output receipt. `chains` must be generated from authoritative `production_chain::inspect`, not hypothetical market stock. `contracts` are read-only native contract snapshots. Construction project tag must be confirmed against Rust `strategy/construction.rs` before phase-2 wiring. No contracts or money created. CODE_UNVERIFIED.
