# N10 — native market pricing and pure order matching (CODE_UNVERIFIED)

Frozen Rust source: `archive/rust-galaxy-067-reference` @ `6e40615be95cc6ddbabe21c3b94def5c52f8622d`:
- `native/crates/sim_core/src/economy/price_engine.rs`: coverage bands, 20-tick urgency onset, 50-tick ramp, max 2.5x urgency, max 5%/tick, price floor 1.0, ceiling 500.0, cent rounding; spread buy/sell quotes.
- `native/crates/sim_core/src/economy/order_book.rs`: most aggressive bid / cheapest ask first, crossing prices, midpoint*(1-spread/2), integer partial fills and remainder orders. Rust trade price is **not** cent-rounded.
- `native/crates/sim_core/src/economy/commodities.rs`: 17 native commodity slugs, reused via N5 catalog.

Implementation:
1. `native_price_engine.gd` reproduces Rust's price-pressure curve, urgency, capped elasticity and spread. Atomic `reprice_market` rejects invalid tick inputs rather than partially updating.
2. `native_order_book.gd` performs pure deterministic commodity-scoped matching and returns proposed trades plus remainders; original orders are never modified. Equal-price tie-break by order ID is an intentional deterministic enhancement (Rust's unstable tie order is unspecified).
3. `market_price_history.gd` stores per-market per-tick price observations in bounded memory (default 256), preventing FPS-driven duplicate ticks.
4. `n10_market_check.gd` includes native-price fixtures, spread, partial fill, no-cross, purity and atomic rejection.

**Not implemented:** market trade settlement, physical delivery, escrow, wallet transfer, order expiration, persistence of full order books, native demand aggregation. Matching is **only a proposal**; calling it does not create commodities or credits. N15/N16 will connect inventory and ledger after their PR dependencies. The history bound is a local memory policy, not a Rust economic formula. This PR is stacked on N9/#96 (which itself depends on N5/#93); review dependencies before merge.

Architecture: Godot built-in RefCounted + Dictionary/Array, no external plugin, no per-ship Nodes; see `GODOT_TOOLING_DECISIONS_RU.md`. Rust order matching is a small pure algorithm, so a third-party market plugin would add overhead and risk semantic drift.

Run when Godot is available:
```sh
godot --headless --path godot --script res://tests/n10_market_check.gd
```
Godot executable absent in this environment: **CODE_UNVERIFIED**, test not run. No VERIFIED checklist counters changed.
