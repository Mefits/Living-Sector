# N28 — read-only credit ledger reconciliation (CODE_UNVERIFIED)

Frozen Rust source: `native/crates/sim_core/src/economy/money.rs` — `MoneySnapshot::capture` sums native ship/facility/faction/household/crew savings/escrow wallets; it is a diagnostic view, **not** a second minting authority. This block audits the N11 Godot `credit_ledger.gd` transfer boundary without altering wallet balances or receipts.

## Functionality

- Caller supplies **actual initial accounts** from the versioned native seed or trusted checkpoint; the auditor never guesses or creates starting money.
- Replays receipt legs in sorted receipt-ID order, checking zero-sum, valid wallet references, nonnegative balances, overflow, malformed metadata and missing/extra wallets. Compares replayed balances with the authoritative snapshot, reports deterministic errors.
- A failed audit is observational only. It does not repair or silently modify money, contracts, inventory or game state.
- `tests/n28_ledger_audit_check.gd` covers wage, escrow, save/restore, deterministic repeat, tampered balance, missing receipt, malformed receipt and money creation attempt.

## Limits

This is **P8-03 partial**, not full Rust parity: native wallet aggregation for ships/crew/households and contract board funding still require integration; trade rounding and order matching remain in N25. Replay from arbitrary receipt ID order assumes independent transfers or receipt IDs encode chronological order; future ledger should add explicit monotonic sequence and audit by sequence. Until then this check may report a false failure if receipt IDs sort differently from valid chronological spending. No Godot runtime was executed here; `CODE_UNVERIFIED`.

Run: `godot --headless --path godot --script res://tests/n28_ledger_audit_check.gd`.
