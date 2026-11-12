# N118 — Phase 1 Rust component port

Frozen source: `native/crates/sim_core/src/strategy/colony.rs commission` (for N119 use `native/crates/sim_server/src/engine/admin.rs`).

Dependencies: N79 admission, N77 construction sites, N104 escrow.

Pure commission proposal: create site or paid passenger/construction contract; caller must commit atomically. Rust facility_offset_position not ported: external authoritative position required.

Minimal static check: source inspected and standalone GDScript added. Godot parser/runtime NOT executed. Status CODE_UNVERIFIED. No P1, main or Rust archive writes.
