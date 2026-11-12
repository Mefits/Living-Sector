# N9 — inventory boundaries (CODE_UNVERIFIED)

Rust reference: `native/crates/sim_core/src/economy/commodities.rs` defines ship `Cargo = HashMap<Commodity,u32>`; `economy/recipes.rs` operates on fractional `HashMap<Commodity,f32>` and explicitly makes the output cap optional pending complete warehouse capacity support. Thus **no global 1000-unit capacity is inferred from design discussions**.

Implemented `inventory_store.gd`: validates known native commodity IDs, finite nonnegative quantities, optional per-commodity caps; atomic multi-item source→destination transfers with all-or-nothing checks; separate integer-only ship holds with total capacity supplied by the caller; stable canonical stock snapshots. This is an inventory primitive, **not** a market transaction, production cycle, logistics simulation or a replacement for Rust's economic price/ledger rules.

The transfer operation preserves quantities across two independent inventories and rejects self-transfers, insufficient stock, full destination, invalid IDs, nonfinite values and partial transfers. Do not call this primitive as a stand-in for delivery contracts; N15/N16 must coordinate physical ship travel, ownership, money and escrow.

Validation when Godot executable is available:

```sh
godot --headless --path godot --script res://tests/n9_inventory_check.gd
```

No Godot runtime was available in the agent environment, so this code is **CODE_UNVERIFIED**. This implementation intentionally depends on N5's native commodity catalog (PR #93), and its PR is stacked on that branch. Do not merge it before that dependency without rebasing/review.
