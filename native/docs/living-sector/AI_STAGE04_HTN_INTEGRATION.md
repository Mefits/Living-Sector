# AI Stage 04 — experimental HTN 0.2.1 adapter (NOT BUILT)

Stage 04 follows Stage 03 in the offline Galaxy 0.2 source snapshot. This is **not an executable integration**; `strategy::coordination` still uses the existing director. There are no HTN-issued ship orders, no new simulation results and no claim that the HTN code compiles until a Cargo environment validates it.

## What is new

- `crates/sim_core/src/strategy/planning/htn_adapter.rs` implements `HtnAdapter: Planner` using the same method-decomposition approach as `reference/ai-bench-v1.3-source/src/htn_adapter.rs`. It invokes the real upstream `htn::plan` (crate `htn = "=0.2.1"`) to validate primitives *and* the resulting ordered plan.
- Actions are projections of `ActionSpec`, **not** independently manufactured recipes. `Produce` requires a matching recipe in the captured native snapshot and an existing appropriate native facility. `Deliver` requires an owned stock source, destination, at least one potentially free ship and bounded funds. `Construct`, `Research`, `FoundColony` are not yet modeled and cannot become free actions.
- Physical state is tracked by (location, commodity); production consumes exact inputs, delivery subtracts source stock and adds destination stock, and every action consumes its projected cost from spendable credits. Fractional inputs are conservatively rounded **down**. Production outputs remain forecasts until native receipts arrive.
- Search is bounded by `SearchBudget` (nodes/depth). The resulting `PlanResult` can be checked with `validate_plan` and inspected without applying native orders.
- Unit tests (currently unexecuted) cover a two-step water supply chain, missing raw stock, budget floor, missing refinery, bounded search and ambiguous market locations.

## IMPORTANT limitations — do not claim full gameplay integration

1. `PlanningSnapshot` currently lacks verified route graph/fuel consumption, available labour, exact reservations and market-specific IDs. For this reason the HTN result is a **hypothesis** rather than proof of a runnable native order. It cannot be dispatched safely until the native executor rechecks each step.
2. If several owned market entities share one location name, the adapter conservatively returns `InvalidSnapshot` instead of aggregating unrelated warehouses. Future work must use *stable market/facility IDs* in snapshots and action addresses; never silently sum supplies.
3. Current Galaxy native `native_first_actions()` covers immediate shortage relief and construction, not a generated multi-step production action catalogue. The HTN adapter is **not currently fed from the coordinator**. W1 in this block is a fixture with only native recipe semantics, not a game-world campaign. Generate and validate real `ActionSpec` candidates in the next block after compiling.
4. The port's HTN methods are data-driven, not special-cased for water/ice/test IDs. However method search uses a bounded DFS, not optimal cost search; HTN crate is used to validate grounded primitive execution rather than to discover methods autonomously.
5. No migration of actual gameplay, economy or saved state was performed in Stage 04. The existing shipped EXE and Linux binary are from Galaxy 0.2.

## Build and handoff

`Cargo.toml` gained a pinned `htn = "=0.2.1"` dependency, so the *original* Cargo.lock needs to be refreshed once in an environment with Cargo. The included `VERIFY-AI-STAGE.cmd` runs `cargo check -p sim_core` first (unlocked) and then `cargo test --locked -p sim_core strategy::planning` and related checks. Keep the *generated new* Cargo.lock with the validated source package. Do **not** claim tests passed if Cargo is not present.

**Acceptance after build:** the new HTN W1 fixture must produce `deliver-ice → process-ice` and pass `validate_plan`; the unmodified gameplay must still compile. This does not yet validate real transport or worker execution.

**Next implementation once compile succeeds:** make snapshot market identifiers unambiguous; expose genuine native transport/production actions as a shared action catalogue; compare the baseline and HTN in *shadow* on the same actual Genesis snapshot, then add native dispatch/receipts incrementally. Do not expand the economy or create a second game-world bench.
