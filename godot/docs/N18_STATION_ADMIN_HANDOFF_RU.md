# N18 — Station administrator (CODE_UNVERIFIED)

**Source:** frozen Rust `native/crates/sim_core/src/strategy/station.rs` and `strategy/production_chain.rs` at `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. **PR dependency:** N6 #100 (itself stacked on N5 #93, N9 #96, N11 #94). No merge.

## Implemented

- One read-only station workforce plan per tick: Rust 60% local population cap, already occupied workers, whole-team assignment, stable facility-ID order, shared real owner cash shadow budget, explicit denial reasons, no station-wide money mutation during planning.
- Local shortage urgency from Rust: `10 + essential*40/(1+stock/20) + min(shortage_ticks,100)*0.2`, +100 for Head priority and ×1.15 for retained viable assignment. Ties resolve by facility ID.
- Existing co-located recipe prerequisite priority: when Head wants food but farm lacks water, existing refinery with real ice may receive the workers first. No imaginary intermediate factory, no phantom water.
- Execution is delegated to the existing N6 paid production boundary; actual credits and fractional stock change only after N6 validates and records a wage receipt. Duplicate dispatch cannot pay twice, snapshots preserve the producer receipt history. Shadow mode cannot execute.
- Headless smoke exercises read-only shadow, water-before-food, paid production, deterministic next-cycle reallocation, idempotence, snapshot/restore, insufficient funds and workforce locality.

## Architecture decision

Rust ECS uses `StationAdministration` as a temporary planning resource and native payroll as the only writer. Godot 4 equivalent is a small `RefCounted` with `Dictionary` records and explicit `plan/dispatch`, **not one `Node` per station or worker**. Existing `native_recipes.gd` is the only recipe implementation and N6 `paid_production.gd` is the only wage/stock writer. No third-party addon improves this small deterministic domain boundary. For thousands of stations, plans can run on work cadence rather than every rendered frame. This follows Godot's data/scene separation and Game Programming Patterns' fixed-step, command, and data-locality approach.

## Limits / next

**CODE_UNVERIFIED:** Godot executable absent in agent environment; smoke not executed. This is not yet the complete Rust station administration: missing mining execution, cross-owner processing fees, actual-work feedback, `TickRunner` integration, globally shared labor reservations across several populations, dynamic repair/restock phase, and full per-recipe profitability/market context. N6 itself is CODE_UNVERIFIED. Plan input is an explicitly supplied authoritative station snapshot, not a self-created world registry. Do not mark P5 verified.

Run locally: `godot --headless --path godot --script res://tests/n18_station_admin_check.gd`.

Review dependencies before merging; this draft is stacked on N6 and must not be merged independently.
