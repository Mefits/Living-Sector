# N136 — economic proposal native source handoff

Frozen Rust: `native/crates/sim_core/src/strategy/economic_proposal.rs` @ archive/rust-galaxy-067-reference, plus read-only `economic_mandate.rs` and `charter.rs`.

GDScript: `godot/scripts/sim/phase1/n136_economic_proposal.gd`.

Source-mapped operations: `matches`, `can_spend`, `needs_review`, `can_offer`, `publish`, `authorize_action`, `decide`, `native_paid`, `expire`. Exact native 600-tick TTL, 120-tick consumed repeat suppression, one proposal per faction, exact location/commodity/kind/action/commitment, bounded cumulative approval tranche, and verified contract ID/tick/payment fields (nullable legacy save).

API accepts **detached Dictionary snapshots**; returns new proposal/charter dictionaries, or a structured decision result. No UI input can set a quote, spend funds or create a contract. The phase-2 coordinator must supply trusted current mandates, charters, commanders, real treasury and native-validated paid receipts. Receipt must already have been booked by mandate/charter/contract ledger before calling `native_paid`; this module records only a one-shot linkage. Other charter and mandate functionality is not duplicated. There is no runtime wiring in phase 1.

Static scope check: source file reviewed, new script read back, no other game files changed. Godot executable not invoked; **CODE_UNVERIFIED**, no runtime parity claim. Differences needing phase-2 verification: Rust i64 checked math vs Godot int64; UTF-8 byte length for action vs GDScript String.length; serialized enum spelling/commodity representation must match caller adapters. In particular, `authorize_action` assumes a charter dictionary exists; no-charter legacy compatibility is an external adapter responsibility.

P1 checkpoint, Rust archive, N39 and N135 untouched.
