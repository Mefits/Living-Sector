# N146 — Frozen SimCommand / CommandBuffer (macro 10)

Source: `native/crates/sim_core/src/simulation/commands.rs` on `archive/rust-galaxy-067-reference`.

Port: `godot/scripts/simulation/native_sim_command_buffer.gd` — all 23 command variants, required-field catalogue, Rust exact kind labels, ship-actor trace attribution (including ExecuteTrade buyer and TransferCredits payer), per-kind trace detail, Vec-like push/append/drain/clear and insertion order. Optional RequestDock facility preference retained. No physical state or credits are mutated by this module.

Phase-2 boundary: the authoritative phase runner owns the buffer, performs actual apply once through existing N90/N97/N108/N39 executors, and only then records durable receipts. Snapshot/restore here captures *pending intents*, not completed transactions; the phase runner must never replay drained commands as already-paid operations. Entity references are external stable IDs and must be remapped/validated against the live world. Rust buffer itself is ephemeral and does not serialize; the extra snapshot is a defensive adapter, not a claim of Rust save parity.

Cheap review: source variant and label count = 23; all variants are represented in FIELDS and LABELS. Godot Runtime not executed; CODE_UNVERIFIED. No edits to checkpoint, main, Rust archive or other claims.
