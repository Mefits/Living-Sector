# N105 — Native faction relief

Source: `native/crates/sim_core/src/agents/faction/relief.rs` frozen Rust 0.6.7. Pure data-only state-in/out port; not a second economy. `faction_floor` must be supplied from Rust `FACTION_WORKING_CAPITAL_FLOOR` at integration. Market snapshots must be unique per location, and only owned markets qualify. Atomic authoritative ledger application and duplicate tick guard are future phase-2 responsibilities. No Godot runtime test; CODE_UNVERIFIED.
