# N100 — Hybrid Planner, frozen Rust source parity

**Status: SOURCE-COVERED / CODE_UNVERIFIED (Phase 1 only).** [Draft PR #188](https://github.com/Mefits/Living-Sector/pull/188), branch `feature/godot-n100-hybrid-planner-overnight11`. No Godot interpreter, parser, upstream Rust differential tests or native execution has been run. This document is an inventory, not a runtime acceptance.

## Explicit handoff

User explicitly stopped previous developers and authorized the second interactive development chat to take over the stale N100 claim on 2026-11-13. The old `second-chat-overnight` claim/run and initial source work remain preserved in `claims/N100.json:transfer_history` on the shared coordination branch. This PR continues the original branch, not a duplicate PR. N39/production belongs to the first chat.

## Frozen source mapping

| Native `strategy/planning/hybrid.rs` | Exact N100 implementation | Exclusive existing dependency |
|---|---|---|
| `HybridPreferences::default/bounded` | `bounded_preferences`; (1,1,0.5), finite clamp 0.1–8, corrupt weight fallback 1 | Existing Director profile is supplied by caller; no second personality |
| `rejected`, `HybridRoleTrace`, `HybridDecision` | `_rejected`, `_trace`, `decide -> {result,roles}` with rejection trace | N98 owns actual execution journal |
| `safe_candidate` | `_safe_candidate`: original common `validate_plan`, native domain replay per action, final goal stock | N155 `n155_planning_validation.gd` and `n155_native_domain.gd` |
| `compose_ingredient_route` | `compose_ingredient_route`: eligible single-input recipe final milestone, GOAP ingredients, sequential IDs/dependencies, checked sum, exact replay | N155 HTN method and GOAP search; no second optimizer |
| `score` | `score`: original credits/1000 + ticks/100 + caution×(0.15×steps + Produce count) | Personal weights passed down from N134/N155 Director |
| `HybridPlanner::decide` | `split_budget`, `_ingredient_goal`, `_disagree`, `decide`: 40/40/20 node shares, GOAP split if ingredient, full-goal direct fallback, selective Beam, stable Rust tie ranking, role statuses and refusals | N155 HTN + Telic exact GOAP, N99 Control Beam; no new Beam |
| `Planner::plan` | `plan` delegates to `decide.result` | N117 may compare forecasts, N121 alone dispatches |

**Deliberate native limitation:** the Rust composition only splices the GOAP subplan into a single-input final Produce; for recipes with multiple inputs/complex HTN it retains the valid original HTN decomposition (or searches the full goal), with no invented intermediate transfers. The native domain uses unique owned markets, floor of available physical inventory, legitimate facility/recipe matches, available ship slots/cargo/committed ship exclusion and spendable treasury above its floor. Action replay rejects phantom goods/cash and second ship departure. Because N155's per-location departure count is not a per-ship capacity assignment, N100 also performs a conservative matching check: every planned delivery requires a different real uncommitted ship with sufficient cargo space at its initial location. This prevents two large deliveries from reusing one large ship while a second tiny ship provides only a nominal slot. Replayed state is immutable relative to live ECS.

**Inter-PR interface:** N155 HTN and GOAP: `plan(snapshot,goal,actions,budget)`; N99 Beam: `plan(native_domain,actions,budget)` (N99 lower-case status and missing goal_id are normalized). N155 Validation: `validate_plan(snapshot,goal,actions,result,budget)`. N100 accepts optional `interfaces` for Phase2 injection and otherwise dynamically resolves the exact scripts by path. Missing Draft PR dependencies **fail closed**, they do not trigger fallback fictional plans. These are already-existing implementation contracts, no copy of their algorithms into N100.

## Safety boundaries and remaining verification

`Ready` is a proposed sequence, **not** an action, shipment, salary, credit, contract Paid or success. `native_dispatch_authorized` stays false. Phase2 must assemble all separate PRs, verify the original upstream HTN 0.2.1 and Telic 0.1.0 behavior, and use N121 authoritative execution receipts and live economy/route/fuel/workforce/treasury revalidation. Do not run N100 alongside a duplicate GOAP, Beam, production pass or ledger.

Author-only fixture file: `godot/scripts/sim/phase1/n100_hybrid_source_checks.gd`. Covers Rust ice→water composition, invalid depleted source, unusable/committed ship, insufficient treasury, ambiguous market, distinct high-capacity ship assignment, strict shared budget, stable preferences, forged action and no snapshot mutation. **Fixtures have NOT been executed.** Source readback: delimiter/string balance and symbol inventory only. No claim of executable Godot or verified upstream crate behavior.

Macro №7 may be marked **SOURCE-COVERED / CODE_UNVERIFIED** as a source-mapping claim once the independent existing N98/N99/N113/N117/N121/N134/N155 source inventory is accepted; this is not Phase2 integration and does not mean game mechanics work together.
