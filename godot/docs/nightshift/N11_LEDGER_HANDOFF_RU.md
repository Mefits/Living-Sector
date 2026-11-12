# N11 — native credit ledger boundary (CODE_UNVERIFIED)

Source: frozen Rust `native/crates/sim_core/src/economy/money.rs` (MoneySnapshot is an **accounting view, not a second ledger**), `agents/facility/workforce.rs` (WAGE_PER_SHIFT = 1 CR, paid shift only once per tick, validation before writes), `agents/faction.rs` (real treasury transfers), `economy/order_book.rs` (f32 matching price, separate from integer credits).

## Implemented

- A small data-only `RefCounted` ledger with native wallet identifiers supplied by the caller. No fake starting balances: `import_accounts` accepts only explicitly supplied seed/checkpoint balances.
- Atomic balanced multi-leg debits/credits, including payroll and escrow transfers; no negative wallets, overflow, duplicate receipt IDs or partial updates.
- Durable operation receipts and snapshot/restore; rejected operations leave balances and receipts unchanged.
- Short headless invariant smoke `res://tests/n11_ledger_check.gd`: payroll, insufficient cash, escrow reserve/refund, duplicate payment, conservation and reload.

## Deliberate boundaries / integration gates

This is a **transaction primitive**, not yet a full implementation of P2-05, P2-07 or P2-11. Rust has native wallets on ships, facilities, households, factions and crew savings, plus contract escrow; callers must map these native wallets explicitly. MoneySnapshot is not a minting authority. A future integration must derive initial balances from the versioned native seed, integrate actual production shift receipts and contracts, and match Rust f32-to-i64 rounding and trade settlement semantics before declaring parity. Do not count this code as a completed market or wage cycle. Existing `N5` commodity/recipe work is in another unmerged PR; do not assume it is on this branch.

## Engineering choice

Godot built-in `RefCounted`, `Dictionary` and `Array` provide a compact headless model; a plugin or per-wallet Node would add overhead without implementing Rust economic semantics. Use a single authoritative mutation boundary, as in command/event processing. The immutable receipt is copied for consumers. This is intentionally independent of rendering and FPS.

## Acceptance

```sh
godot --headless --path godot --script res://tests/n11_ledger_check.gd
```

Godot executable not available in this run; script is **CODE_UNVERIFIED**. No Rust build or paid CI used. Next: integrate with native wallets and workforce once N6/N9 prerequisites are merged; add actual trade/contract accounting and price rounding parity tests.
