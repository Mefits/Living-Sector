# N6 — paid local production slice (CODE_UNVERIFIED)

Rust frozen baseline: `agents/facility/workforce.rs` and `economy/recipes.rs`.
A staffed local shift pays exactly **1 CR per worker**. Only the Rust 60% of local population labor cap is used; the caller must supply already unoccupied workers. The paid shift requires the facility and household accounts to exist in N11 ledger. N5 recipes use fractional market quantities and N9 validates capacities.

The N6 coordinator performs a detached recipe dry run, checks every resulting inventory limit, then commits a balanced wage transfer through N11 ledger and applies the prepared stock state without asynchronous callbacks. One facility can complete at most one shift per tick; durable receipt IDs block duplicate wages. The resulting outputs and tick survive snapshot/restore.

**Scope boundary:** this is the self-owned, same-location stock case. It does not implement foreign-stock commissioning, owner-paid processing fees, household allocation across multiple facilities, full workforce reservation, station policy permits, research gates, market settlement, or integration into TickRunner. Those remain explicitly open. No production happens automatically on a Godot tick yet.

Dependencies: N5 PR #93, N9 PR #96, N11 PR #94 (ledger file imported unchanged from N11). Avoid merging this stacked PR before these dependencies are reconciled.

Run: `godot --headless --path godot --script res://tests/n6_paid_production_check.gd`.

Static source parity reviewed; Godot executable was not available in the agent environment. **Do not mark VERIFIED.**
