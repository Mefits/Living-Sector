# Galaxy 0.2: native integration handoff

## Authority and architecture

Base is the supplied offline snapshot `65ce7bf53babf5abf47992558cccf1d371068589`, not a fetched repository. Current user priority supersedes old A1/A2 "no observer/build" notes: runnable autonomous galaxy, personality mixtures, preservation of working Genesis mechanics. No GitHub publishing was performed.

The new director is an optional policy over C1, not another simulation. ECS inventory, population, accounts, contracts and construction sites remain authoritative. A director candidate never creates a facility. Colony grants go to `strategy::colony::commission`; deliveries/construction go through existing grants, station orders and ship BT execution. New research is a synchronous validated ECS transaction with a work receipt participating in the shared workforce occupancy calculation.

The architecture deliberately uses an inspectable bounded candidate comparison; no claim is made that Telic/HTN/Beam has been integrated. Native construction checks provide causal preconditions. A full dependency planner can replace candidate generation without replacing the transaction/execution layer. The current director does not solve arbitrary unseen long production chains.

## Changed layers

- `strategy/director.rs`: normalized archetype mixtures, observations, candidate scoring, research transaction, bounded history, crisis detection and industrial incidents.
- `strategy/orders.rs`, ship behavior and `engine/apply.rs`: assigned pilots receive verified quotes and route coordinates. Cargo already aboard may coexist with a new order when free capacity suffices. Leaving a dock releases the actual facility berth, and admission prunes stale occupancy.
- `strategy/construction.rs`: colony industry proposes mining, refining and farming in dependency order and uses ordinary metal deliveries and paid labor.
- `strategy/options.rs`: compare all supported native shortage options with personality; old chooser retained when director disabled.
- `strategy/coordination.rs`: one global choice per cycle; finishes viable expeditions, protects survival, applies research only in execute mode.
- `strategy/colony.rs`: research prerequisites, 50 settlers in Galaxy mode, gas-bearing colony candidates, prioritization by home gas shortage. Existing expeditions may finish without rechecking a new unlock.
- `simulation/config.rs` and `ai/personality.rs`: native colonizer class, passenger capacity 50, engineering crew, cargo 500.
- `agents/facility/mod.rs`: tech adds available production batches; input consumption and native wages still apply.
- `agents/facility/workforce.rs`: research receipts share the same per-tick worker occupancy ledger as production and construction.
- `sim_db/persistence.rs`, `engine/persist.rs`, `engine.rs`: versioned `galaxy_director_v1` record in existing simulation_state, emitted in the same EconomicFrame as accounts, markets, population and tick; restored before snapshots.
- `sim_db/spawner.rs`: charted ordinary cruise corridors in Galaxy mode. No teleports or new resource inventories.
- `sim_db/seeder.rs`: optional explicit facility seed credits, keeping old default.
- `snapshot.rs`, HTTP observer and `observer/galaxy.html`: real API commander view beside the original map.

## Research economics

One successful shift consumes one Electronics, pays ceil(local Electronics price) to the owning station and 10 CR to the existing ten workers, and earns ten work units. Treasury retains at least 10,000 CR. Reject invalid price, missing stock/workers, crisis, repeated tick, missing research and integer overflow before any write. Inputs are consumed in the native market; all money moves between existing accounts. A persistent last-shift receipt prevents repeat execution after resume and avoids double staffing.

Technology effects are intentionally small and native: two batch-cap improvements, colonization permission and long-distance colonization permission. Full original research data remain in reference; do not label the four native technologies T1–T4.

## Personality contract

Existing persisted `Personality.prefer_goals` accepts positive finite `leader_economist`, `leader_pacifist`, `leader_aggressor`, `leader_expansionist`, `leader_technocrat`, `leader_isolationist` weights. Normalize to one. Seed uses two traits; three work through the same map. Axes are not physical bonuses or hidden resources. Safety constraints precede strategic preferences. The current aggression effect is expansion weighting, not implemented military policy.

## Validation

See reports for actual outcomes. Tests use real C1 engine movement, funding, construction and resume; no fixture teleport is used in the Galaxy integration test. Windows is cross-compiled; Linux runs the same core for executable validation. Do not describe cross-compilation as a Windows GUI runtime test.

## Remaining work / risks

- Replace heuristic short-horizon native relief value with explicit downstream dependency value, especially remote raw supply and new-colony industry.
- Add sustainable colonial production and migration staffing policies before greatly increasing galaxy size.
- Add native science facilities and richer tech requirements; keep workforce/material accounting atomic.
- Keep science view synchronized with actual worker receipts; do not invent missing metrics.
- Full war, diplomacy, T2–T4 materials/29 buildings, finite deposits and energy need actual native actions before strategic candidates can claim them.
- Director memory is bounded intent/history and research state, not learned economic forecasting. Do not describe it as general strategic learning.
- Engine initial personalities/world seeding include inherited randomness. A single successful run is not multi-seed balance certification.
- The supplied archival repository contains historical documents referring to older branches. This document and the packaged executable are the current local handoff; no remote branch was modified.
