# N38 — P1 checkpoint integrity and recovery

Status: **CODE_UNVERIFIED**. Branch based on N32 integration candidate PR #120. No merge into main.

## Source and scope
Rust reference: `native/crates/sim_server/src/engine/persist.rs` writes economic state as indivisible persistence frames and does not clear dirty flags until the entire frame is admitted. The Godot P1 save is currently **orbital-only**; this change does not claim Rust SQLite frame parity or persistence of live economy.

## Changes
- `save_state.gd`: JSON-normalized SHA-256 envelope, bounded read (16 MiB), strict envelope validation, atomic pending->primary promotion, preservation of known-good .bak if primary is corrupt, recovery from backup.
- Bare schema-v1 P1 checkpoints remain loadable through the existing TickRunner staged validation. A digest is accidental-corruption detection, not authenticity or anti-cheat.
- `tests/n38_save_integrity_check.gd`: deterministic bytes, tampered valid JSON, backup fallback, corrupt primary/backup rejection without live-state mutation, legacy compatibility.
- All functionality uses Godot `FileAccess`, `DirAccess`, `JSON` and built-in String SHA-256; no new addon or heavy Node.

## Windows acceptance
From `godot/` with Godot 4 Standard:

```cmd
Godot.exe --headless --editor --path . --quit
Godot.exe --headless --path . --script res://tests/n38_save_integrity_check.gd
Godot.exe --headless --path . --script res://tests/p1_tick_save_check.gd
```

Expected marker: `N38_SAVE_INTEGRITY_PASS`; nonzero exit or any parser/runtime error means fail. No Godot executable was available in the agent runtime. **Do not mark VERIFIED.**

## Boundaries and next work
This is a P1 checkpoint integrity slice, not authoritative economic persistence. The existing P1 snapshot excludes money, ships, contracts and production. Integrating Rust-style indivisible economic persistence frames requires a separate live TickRunner integration with real domain state and replay tests. In a crash between backup rotation and promotion, the backup remains recoverable. Recovery is intentionally non-destructive (does not silently overwrite primary during load).
