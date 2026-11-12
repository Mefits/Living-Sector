# N139 — native production-chain read-only port

Rust source: `native/crates/sim_core/src/strategy/production_chain.rs` at frozen `6e40615be95cc6ddbabe21c3b94def5c52f8622d`. Related source: `strategy/production_dependencies.rs` and `strategy/construction.rs`.

Godot file: `godot/scripts/simulation/strategy/native_production_chain.gd`.

## Scope
- One-batch local input readiness using real recipe inputs/outputs, least missing recipe and lexicographic tie-break.
- Co-located installed producer priority for the first missing precursor; never imagines a future factory.
- Five causal physical stages: commission, materials, paid labor, local recipe inputs, actual first output.
- Contract status discrimination (posted, accepted, picked up, delivered, paid/expired), site progress, workforce blockers, output receipt tick and cumulative units.
- Pure read-only API: caller passes snapshots of authoritative world state; no changes to inventory, credits, contracts, workers, or sites.

## Interface
`inspect(faction, construction, sites, producers, contracts, markets, recipes) -> Dictionary`.
`construction.selected_goal` has commodity/destination. Arrays contain dictionary projections of native ECS records. `producers[].work_shift` exposes `last_recipe_ticks` and `produced_outputs` keyed by recipe ID. `markets[].supply` is actual market inventory. `recipes` is the N73 native recipe catalogue projected as dictionaries. The stage snapshot must be taken after native refresh, as in Rust.

No runtime adapter or UI is added in phase 1. The caller in phase 2 must preserve native order of refresh, contract reconciliation, paid shifts, and receipt materialization. In particular, Delivered alone does NOT mean construction materials were credited.

## Choice
RefCounted static pure functions and Dictionary projections avoid thousands of per-entity Nodes and preserve the Rust read-only separation. No plugin is needed for a deterministic five-stage inspector. This does not duplicate N39 production execution or N18 administration.

## Checks and status
Rust source and related dependency schema read. GitHub file committed and readback pending. Godot parser/runtime not run; **CODE_UNVERIFIED**. No headless test scaffold was added per current phase-1 instruction.

## Deferred
Authoritative world snapshot adapter, integration with N73 recipe catalogue, exact physical receipts and comprehensive runtime parity belong to phase 2.