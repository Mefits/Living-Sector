# N42 — closed-transfer integrity audit (CODE_UNVERIFIED)

Base: integration PR #128 @ `1e4a1e9f34fff7313ce176107890ecdbe25fc85a`.
Frozen reference: `native/crates/sim_server/src/engine/persist.rs` (atomic economic frames), `economy/money.rs`; read-only reference.

## Scope and semantics

`world_integrity_audit.gd` is a **read-only diagnostic**. It accepts explicitly sourced credit account balances, facility stores, ship holds, owner IDs, locations and dock bindings. It does not import a live game world, create a wallet, execute transactions or change gameplay. It checks:
1. Complete typed snapshots, nonnegative finite inventory, nonnegative integer credits, sum overflow.
2. Ship identity/owner/location completeness, docking at actual location with an existing store.
3. Closed transfer conservation of **both** credits and every commodity across all stores and holds, with deterministic sorted diagnostics.
4. No mutation of input snapshots; no acceptance of missing data as zero.

**Critical limitation:** closed-transfer audit must NOT be applied across mining, consumption, production or construction ticks without separately verified source/sink receipts. It is a fail-closed tool for physical transfer/payment operations, not proof that the whole economy works. Aggregate conservation does not prove that a particular contract or receipt is legitimate; N27/N30/N31 remain separate controls.

## Design choice

Godot `RefCounted` + Dictionaries and deterministic sorted keys. No per-ship Nodes, no plugin, no second ledger. A single audit pass costs O(accounts + inventory entries + ships), with O(distinct commodities) aggregation; call only at transfer boundaries or diagnostic sampling, not every rendered frame. Existing N11 ledger remains the only proposed money authority. This module is deliberately opt-in until N39 production and N40 transit integration are reconciled.

## Acceptance

`godot --headless --path godot --script res://tests/n42_world_integrity_check.gd`

Expected marker: `N42_WORLD_INTEGRITY_OK`. Test covers conserved transfers, minted credits, phantom goods, mismatched docks, missing ownership, negative and NaN quantities, missing schema, and input immutability. No user saves are read or written. **Not run in Godot during this block.** Do not label RUNTIME_MECHANICS_VERIFIED.

Next: build a typed adapter from actual authoritative N9/N11/N15/N21 state only after their integration is reviewed; then add per-receipt checks and an actual Godot runtime log.
