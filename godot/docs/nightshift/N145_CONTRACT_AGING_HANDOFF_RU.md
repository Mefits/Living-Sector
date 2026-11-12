# N145 — contract Posted aging / renewal (macro 5)

Source: frozen `native/crates/sim_core/src/economy/contracts.rs`, specifically `age_open_reputation`, `age_escalate_payment`, `sweep_expiring`, `expire_unclaimed`, `posted_for_ship`, and posted index maintenance.

File: `godot/scripts/sim/native_contract_aging.gd`. Standalone RefCounted static methods; accepts/returns serialized native contract dictionaries keyed by ID. Native snake_case status and kind slugs required.

- Reputation opens every 100 ticks, 10 points per step from initial gate (Rust u8 step wrap preserved); never raises reputation gate.
- Price ages every 50 ticks, +5% of original per step, cap +100%, never reduces existing payment. Fixed faction strategy rewards remain initial.
- Delivery and Construction renew at most 3 times; Subsidy once and becomes public; other types expire immediately. Renewal premium 25% of current payment; new expiry is current tick plus configured lifespan.
- Rebuild posted/status/destination/faction tier indexes and return eligible posted IDs without mutating credits, cargo, funding or physical stocks.
- Returns renewal/expiration event summaries; authoritative escrow refunds on expiry MUST be performed by the N104 funding authority in the same exclusive tick, not by this component. Never use this as a second financial ledger.

**Phase-2 handoff:** apply returned board snapshot and index rebuild as one atomic board transaction; emit events and route terminal expiry to the real payer/refund logic. N16/N104/N135/N97 already own escrow, dispatch and physical settlement; do not run their duplicate aging rules. No UI integration or Godot runtime performed.

**CODE_UNVERIFIED:** GDScript parser and Rust float32 `round()` parity untested. For very large i64 payments the standalone module fails closed on age overflow; native Rust may overflow in debug and use f32 saturation on renewal. Do not claim exact numerical parity on those edges until Phase 2.
