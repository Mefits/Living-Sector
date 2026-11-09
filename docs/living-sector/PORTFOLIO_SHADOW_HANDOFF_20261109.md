# Strategic portfolio: first reusable game integration (2026-11-09)

**Branch:** `feature/genesis-portfolio-advisor-shadow-20261109` based on `feature/genesis-c1-colonization`. No changes to the default gameplay decisions, ship orders, production, money, save schema or technology unlocks.

## Why this is NOT another benchmark-only feature

The new source `crates/sim_core/src/strategy/portfolio_policy.rs` is compiled into **Genesis sim_core**, not a standalone scoring dashboard. `strategy::options::shadow_portfolio` feeds it actual native shortage / proposal data, and `/api/strategy` exposes the result as `factions[].head.shadow_portfolio`. Its choice is **read-only** and cannot create an order or spend money; existing policy still controls `selected_option`, grants and execution. Its local unit tests cover negative-value proposals, treasury floor, zero supply relief, deadline and bounded survival urgency. A native integration test additionally checks that the original funded contract remains unchanged.

## What the first version can and cannot judge

- It compares ALL currently viable native supply/build proposals across goals, rather than choosing the first goal with any positive option. It uses native projected shortage relief, delays, existing net credits value, treasury after commitment, survival importance and reserves.
- It never rewards a command just for being issued, never adds credits, and rejects speculative proposals with zero projected result.
- The currently deployed C1 head has **no T2–T4 research or megastructure operations**. The policy therefore cannot choose a scientific project in-game yet. The experimental 18-resource/29-building model and AI Decision Bench remain reference material, not a replacement for Rust ECS / real transactions.
- `shadow_portfolio` is a **counterfactual**, not the current command. It should not be treated as evidence that HTN, Telic, Cranium or Beam won a test. Those planner libraries are still only in the external bench.
- No complete Rust/Windows runtime test was performed in the generation environment; compile and CI are pending, and this branch is NOT approved for merge into the C1 release.

## Adoption gate: stages, not one big rewrite

1. **Compile the shadow module** on the new branch, run focused tests for `portfolio_policy` and native `strategy_block_head_` plus an API smoke with a clean 6-system seed. Keep current C1 untouched.
2. **Collect paired decisions** at the same snapshot: incumbent `selected_option`, shadow `action`, shortages, treasury, predicted / real shortage relief after 1200 base ticks. The score is diagnostic; realized outcome matters.
3. **Bench framework comparison:** export the SAME validated native action/outcome contract to the separate AI Bench. Repair the fake leaderboard first: compare fixed simulation-horizon welfare, continuity, research, industry, reserves, population and downtime; report planning latency independently. An action-count or faster-ticks bonus cannot define who won.
4. **Technologies and economy:** only after actual T2/T3 facilities/research/energy exist in Genesis, expose their real native preconditions/outcomes to the policy; do not copy abstract `technology_points` or 29 placeholder costs as player assets.
5. **Controlled promotion:** only if multiple clean-seed campaigns show meaningful improvement without treasury duplication, shortages worsening, broken persistence or runaway construction, let an explicit feature flag use the new suggestion to authorize ONE native contract. Keep the ability to revert without save migration.

## AI architecture boundary

- **Head** ranks long-horizon outcomes, selects a project and issues authority.
- **Station administrator A1** manages local staffing, modules and actual supply needs; its policy need not be replaced by benchmark algorithms.
- **A2/executor** assigns and executes native contracts and construction with real ships, preserves save/restore. No benchmark action may directly mutate stocks.
- HTN may be useful for deliberate construction/research dependency chains; Beam for a bounded set of strategic options; Cranium for tactical choices among ready tasks. This is a **hypothesis to test**, not an integration decision.

## Key current diagnostic

The supplied 15-run external `summary(7).json` (three 100-system scenarios × five methods) shows HTN waiting 140/140 turns on every scenario, and identical action traces for control Beam, Telic Beam and Cranium+Telic in each scenario. Cranium Utility makes local profitable moves but does not reach T2. The leaderboard mixes final quality with different elapsed ticks and therefore is **not** a valid framework choice yet.

## Next change

After shadow compile/API checks: generate a compact native **paired decision log** and a first small batch of independent C1 missions where the incumbent and shadow can be evaluated against the same state; no permanent gameplay changes before this comparison.
