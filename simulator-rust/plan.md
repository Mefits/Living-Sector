# simulator-rust — fresh-eyes review, bundled for execution

## Context

You asked for a fresh pair of eyes on `simulator-rust/` to:
1. Document the current agent/economy systems with mermaid diagrams.
2. Spot places it could be smarter, more emergent, or architecturally cleaner.

This file is the master plan. It is organized into **bundles** — self-contained chunks of work that can be picked up independently in later sessions. Each bundle has a goal, the concrete items, an order, and a verification approach.

> **Concurrent-edit caveat.** Another Claude is editing the tree right now. Symbol names (`plan_goal`, `tick_populations`, `SimCommand`, `ContractBoard`, etc.) are durable anchors; line numbers and thresholds may drift. Re-read at head before acting.

> **This file will be copied to `simulator-rust/plan.md` as the first step of Bundle 3**, so it's tracked with the code and visible to whoever picks up next.

---

## Bundles at a glance

| # | Bundle | Theme | Effort | Risk |
|---|---|---|---|---|
| 1 | Starter Bundle | Quick wins: causal trace, price decay, personality drift, contract sizing, LOD extension | ~1–2 sessions | Low |
| 2 | Big AI Arc | Utility-scored planner + mid-action replan | ~2–3 sessions | Medium (rewrites `plan_goal`) |
| 3 | Mermaid Docs | Extract Part 5 diagrams into `simulator-rust/docs/ARCHITECTURE.md` + copy this plan in | ~1 session | None |
| 4 | Backlog | Everything else, scoped but unprioritized | As-needed | Varies |

Recommended order: **3 → 1 → 2 → 4**. Docs first so future sessions (and the other Claude) have the shared reference; starter bundle next for low-risk wins; big AI arc when you have a clean session; backlog as appetite dictates.

---

## Bundle 1 — Starter Bundle (low risk, high leverage)

**Goal.** Five small, independent improvements that each visibly improve sim behavior without touching tick-phase order or the BT engine. No single one is architectural; together they push the feel from "mechanical" toward "emergent."

**Items, in suggested implementation order:**

### 1.1 (R) Causal trace endpoint
- **Problem.** Debugging "why did ship X go broke?" is archaeology.
- **Change.** Add `GET /api/debug/ship/:id/trace` that returns the last N `SimCommand` entries mentioning that ship. Command trace ring buffer already exists (`app_state::COMMAND_TRACE_CAPACITY`, `engine::record_command_trace`).
- **Files.** `sim_server/src/http/api.rs` (new route), `sim_server/src/app_state.rs` (expose filtered query).
- **Acceptance.** Spawn a ship, let it trade, query endpoint, see Buy/Deliver/Pay events for that ship only.
- **Effort.** ~1 hour.

### 1.2 (E) Price memory decay
- **Problem.** `ShipMemory.price_knowledge` keeps every price forever → stale routing.
- **Change.** Decay stored prices by age when scoring, or store an EMA. Weight in `trade_opportunity` consideration.
- **Files.** `sim_core/src/ai/considerations.rs::trade_opportunity`, `sim_core/src/agents/ship` (price observation site).
- **Acceptance.** Unit test: observe a price at tick 0, observe a better price at tick 500 for same commodity at different station — ship routes to the fresher source even if raw margin is slightly lower.
- **Effort.** ~2 hours.

### 1.3 (F) Contract quantity scales with shortage depth
- **Problem.** `DELIVERY_CONTRACT_QTY = 50` hardcoded. A market short 500 units spawns 10 serial 50-unit contracts.
- **Change.** Compute `qty = clamp(shortage_magnitude, min_qty, max_qty_by_facility_credits)` at post time.
- **Files.** `sim_core/src/agents/facility::tick_post_contracts`.
- **Acceptance.** Smoke run: watch contract board — big shortages produce one big contract instead of a swarm of small ones.
- **Effort.** ~2 hours.

### 1.4 (D) Personality drift
- **Problem.** Personality is frozen at spawn. No character arc over thousands of ticks.
- **Change.** Nudge axes by ε on key events: completed contract → +profit, near-starvation → +safety, exploration-discovery → +exploration. Clamp to [0,1].
- **Files.** `sim_core/src/ai/personality::Personality` (add `drift` method), hooks in `DeliverContract` apply and `Rest`-timeout path.
- **Acceptance.** Unit test: simulate 100 deliveries, assert `profit` axis increased; simulate 5 near-starvations, assert `safety` axis increased.
- **Effort.** ~3 hours.

### 1.5 (L) Extend LOD gating to facilities + populations
- **Problem.** CLAUDE.md admits facility/pop phases don't LOD-gate. They'll dominate at 10k agents.
- **Change.** Gate `tick_recipes_and_mining`, `tick_restock`, `tick_populations` on `AgentLod::try_fire`; scale any per-tick accumulators (sentiment inertia, crew hunger) by `skipped_ticks`.
- **Files.** `sim_core/src/agents/facility`, `sim_core/src/agents/population`; `AgentLod::try_fire` already supports it.
- **Acceptance.** Spawn 500 facilities with observer present on 50, observer absent on 450 → perf HUD shows facility-phase cost drop proportional. 155 existing tests still pass.
- **Effort.** ~4 hours. Main risk: missed accumulator scaling → slow drift over hours.

**Bundle verification.** `scripts/verify.sh --strict` clean + `WORLD_SPEED=4 scripts/smoke.sh 60` shows no economic regression. Ship-list panel shows visibly more personality variation after 2000 ticks.

---

## Bundle 2 — Big AI Arc (A + B)

**Goal.** Replace the priority waterfall in `plan_goal` with a unified utility scorer and add mid-action replanning. This is the single biggest "AI feel" upgrade available.

### 2.1 (A) Unified utility scoring
- **Problem.** `plan_goal` is a priority cascade. A ship with 1% fuel never considers any contract, even one that passes a refuel station on the way. Opportunities near the path are invisible.
- **Change.** Score every candidate goal in one pass. Low fuel dominates by sheer consideration magnitude (fuel_urgency → 1.0 × safety weight), not by hardcoded bypass. Add compensating considerations: `fuel_on_route`, `morale_on_route`, `reachable_without_refuel`.
- **Files.** `sim_core/src/agents/ship::plan_goal` (rewrite), `sim_core/src/agents/ship::score_goal` (expand), `sim_core/src/ai/considerations` (add new signals), `sim_core/src/ai/utility::best_action` (may need weighting tweaks).
- **Subtasks.**
  1. Define the new ActionSpec set (rest_crew, refuel, sell_cargo, fulfill_delivery, trade_run, retrofit, explore, idle) with factors + directions.
  2. Write per-goal candidate generators (reuse `try_plan_contract`, `try_plan_trade_run`).
  3. Implement combined scorer.
  4. Replace `plan_goal` body. Keep BT builders unchanged — they consume the chosen goal.
  5. Unit tests per goal: starvation-level fuel ⇒ refuel wins; healthy fuel + juicy contract ⇒ contract wins; gate-fuel edge case ⇒ refuel wins by narrow margin.

### 2.2 (B) Mid-action replan on opportunity
- **Problem.** `Running` BT can't pivot. Ship finishes current plan even if a 10× better deal lands.
- **Change.** Each tick, compute current goal's score + best alternative's score. If `alternative > current × 1.25` AND `ticks_since_plan > MIN_COMMIT`, abort BT and replan. Hysteresis + min-commit prevent thrashing.
- **Files.** `sim_core/src/agents/ship::decide_and_act` (add score tracking on `ShipMemory`), planner integration.
- **Acceptance.** Scenario: ship mid-trade run; spawn a high-value subsidy contract on a station it can reach — ship abandons the trade run, picks the contract. Inverse scenario: ship mid-retrofit, juicy trade posted — ship finishes retrofit (retrofits are committed by design).

**Bundle verification.** `scripts/verify.sh --strict` clean, 155 tests pass. Spawn two worlds with same seed, one with waterfall, one with scorer. Qualitatively: scorer fleet shows more opportunistic routing; waterfall fleet shows more lockstep behavior. Perf p50 increase < 200 µs.

**Blast-radius notes.** `plan_goal` is central — almost every BT path starts there. High-value test: make sure the crew-starvation-death-spiral fix from Phase 18k still holds. The waterfall's biological-needs-first behavior must emerge naturally from the new scorer, not be lost.

---

## Bundle 3 — Mermaid Docs

**Goal.** Turn the architecture mermaid into a tracked doc so future sessions share the reference, and copy this plan into the repo.

### 3.1 Copy `plan.md` into repo
- Copy this file to `simulator-rust/plan.md`.
- Add it to `.gitignore` review — probably tracked, not ignored.

### 3.2 Create `simulator-rust/docs/ARCHITECTURE.md`
Contains eight mermaid diagrams (see Part 5 below), each with a one-paragraph caption. Cross-links to CLAUDE.md for the "Systems wired" table.

### 3.3 Add link from `simulator-rust/CLAUDE.md`
Single-line pointer near the top: "See [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) for diagrams of the tick loop, AI stack, and economy."

**Verification.** `gh pr checks` or whatever renders — view the file on GitHub, confirm mermaid renders.

**Effort.** ~30 minutes once the other Claude is done.

---

## Bundle 4 — Backlog (scoped, unprioritized)

Each item is an independent change we might pick up later. Ordered only by the section they belong to.

### AI / decision-making
- **(C) GOAP / HTN planner.** Synthesize multi-step plans instead of hand-authoring BTs. Defer until goal count doubles. `sim_core/src/ai/planner` (new). High effort.

### Economy
- **(G) Money sink / inflation anchor.** Pick one: docking-fee burn, wage void sink, faction treasury ceiling. Low-medium effort. **Important** for multi-day runs.
- **(H) Facility profitability gate on recipes.** Skip negative-margin batches. `facility::tick_recipes_and_mining`. Medium effort.
- **(I) Reverse-auction contracts.** Ships bid price; facility picks. High effort. Probably after G + F.
- **(J) Bundled convoy contracts.** Aggregate nearby same-commodity demand into one big contract. Medium effort.
- **(K) Population wealth as a real variable.** Wire wages → wealth → growth → consumption. Medium effort; test carefully.

### Scalability / engine
- **(M) Incremental snapshot cache.** Dirty-set rebuild instead of full scan. Medium-high effort.
- **(N) Rayon on ship phase.** Architecture already supports it (no cross-ship writes within phase). Medium effort.
- **(O) Spatial grid for LOD + proximity queries.** Replace O(n × observers) with grid lookup. `sim_core/src/spatial/` skeleton exists. Medium effort.
- **(P) Contract board index.** Bucket by (rep-tier, destination-system). Low effort.

### Observability / ergonomics
- **(Q) Parameterize magic numbers.** `WorldTuning` struct, admin-tweakable. Low-medium effort, lots of touchpoints.
- **(S) `MarketCrisis` / `FacilityStarving` events.** Threshold-crossing events for Godot to surface. Low effort.

---

## Part 5 — Architecture as-is (the diagrams for Bundle 3)

### 5.1 Tick loop phase graph

```mermaid
flowchart TD
    ctrl[drain control channel<br/>pause/speed/step]
    bodies[bodies: regen resources]
    lod[LOD recompute<br/>every 50 base-ticks]
    ships[ships: advance transit +<br/>observe prices + decide_and_act]
    appS[apply ship commands<br/>dock / supply delta / contract accept]
    drain1[drain materializations /<br/>decommissions / respawns]
    facs[facilities: recipes + mining +<br/>condition + restock + post contracts]
    pops[populations: consume + sentiment +<br/>passenger contracts + migration]
    mkts[markets: produce → consume → emergency →<br/>surplus → match → demand → shortage → price]
    appM[apply market commands<br/>credit transfers, supply deltas]
    drain2[drain pending queues again]
    facts[factions: tax + subsidy + construction]
    snap[snapshot cache rebuild]
    bcast[broadcast to WS clients]
    persist[emit persist writes to worker]

    ctrl --> bodies --> lod --> ships --> appS --> drain1 --> facs --> pops --> mkts --> appM --> drain2 --> facts --> snap --> bcast --> persist
    persist -.->|next tick| ctrl
```

### 5.2 Runtime data ownership

```mermaid
flowchart LR
    subgraph client[Godot client]
        gd[scene + panels]
    end
    subgraph server[sim_server]
        direction TB
        ws[ws::handler]
        http[http::api + admin]
        engine[engine tick loop<br/>exclusive &mut AgentStore]
        snap[(SnapshotCache<br/>DashMap, lock-free)]
        pw[PersistenceWorker<br/>5s batch, mpsc dedup]
        db[(SQLite WAL)]
    end
    subgraph core[sim_core — pure]
        store[AgentStore = hecs::World + ContractBoard]
        cmds[CommandBuffer]
        ai[ai: BT + utility + considerations]
        eco[economy: prices, recipes, contracts, missions]
    end

    gd <-->|JSON WS/HTTP| ws
    gd <-->|HTTP| http
    engine --> store
    engine --> cmds
    engine --> snap
    engine -->|DbWrite mpsc| pw --> db
    ws -->|read only| snap
    http -->|read only| snap
    http -->|SimCommand| engine
    store -.uses.- ai
    store -.uses.- eco
```

### 5.3 Ship decision stack

```mermaid
flowchart TD
    tick[decide_and_act per active ship]
    snaps[build per-tick snapshots:<br/>loc→system, dock congestion, shipyard stock]

    plan[plan_goal — priority waterfall]
    rest{crew morale<br/>below rest trigger?}
    fuel{fuel<br/>critical?}
    sell{cargo<br/>onboard?}
    retro{retrofit points<br/>+ reachable yard?}
    elective[elective band:<br/>score fulfill_delivery vs trade_run<br/>via ln profit × 1+prefer_goals]
    idle[smart idle:<br/>explore or station-seek or hold]

    bt[[build BtNode ShipAction tree]]
    exec[execute_ship_action via closure dispatch]
    emit[emit SimCommand<br/>cross-entity effects only]

    tick --> snaps --> plan
    plan --> rest --yes--> bt
    rest --no--> fuel --yes--> bt
    fuel --no--> sell --yes--> bt
    sell --no--> retro --yes--> bt
    retro --no--> elective --> bt
    plan -.fallback.-> idle --> bt
    bt --> exec --> emit
    emit -->|applied next phase| plan
```

### 5.4 Economic feedback loop

```mermaid
flowchart LR
    body[celestial body<br/>resources regen]
    mine[mining_rig facility]
    mkt[local market<br/>supply → coverage → price]
    short[shortage_ticks++<br/>when coverage < 0.1]
    facPost[facility posts<br/>Delivery contract]
    popPost[population posts<br/>Passenger / Food contract]
    sub[faction posts<br/>Subsidy 1.25× – 3×]
    cons[construction:<br/>new facility spawned]
    board[ContractBoard]
    ship[ship plan_goal picks contract<br/>gated by rep + sensor range]
    deliver[deliver → pay + supply bump<br/>via SimCommand apply phase]
    recipe[facility recipes consume supply]

    body --> mine --> mkt
    recipe --> mkt
    mkt --> short
    short --> facPost --> board
    short --> popPost --> board
    short -.600 ticks.-> sub --> board
    short -.very long.-> cons
    board --> ship --> deliver --> mkt
    deliver --> recipe
```

### 5.5 Contract lifecycle

```mermaid
stateDiagram-v2
    [*] --> Posted: facility/pop/faction posts
    Posted --> Posted: age_escalate_payment<br/>+5%/50 ticks, cap +100%
    Posted --> Posted: age_open_reputation<br/>-10 rep/100 ticks → public
    Posted --> Accepted: ship meets rep + sensor gate +<br/>profit > cost estimate
    Posted --> Expired: TTL lapses without renewal
    Expired --> Posted: renew (≤3 times, +25% pay, -15 rep)
    Accepted --> PickedUp: cargo loaded at source
    PickedUp --> Delivered: cargo unloaded at dest
    Delivered --> Paid: apply phase pays ship + bumps supply
    Paid --> [*]
    Accepted --> Posted: ship dies / re-plans → orphan release
```

### 5.6 Market 8-phase tick

```mermaid
flowchart LR
    p1[produce<br/>MarketFlow.production]
    p2[consume<br/>update consumption_window]
    p3[emergency orders<br/>low supply + positive demand]
    p4[surplus orders<br/>supply > demand × 5]
    p5[match orders<br/>midpoint - spread/2]
    p6[update demand<br/>rolling window]
    p7[track shortage<br/>shortage_ticks++]
    p8[price recalc<br/>coverage × elasticity + urgency]

    p1 --> p2 --> p3 --> p4 --> p5 --> p6 --> p7 --> p8
```

### 5.7 LOD gating (ship-only today)

```mermaid
flowchart TD
    obs[observer positions<br/>from WS hello]
    dist[distance² to nearest observer]
    tier[divisor ∈ 1,2,5,10,20,50]
    fire{tick >= next_tick?}
    skip[skip this tick]
    run[run ship phases<br/>scale fuel burn + crew needs by skipped_ticks]
    fac[facilities + populations<br/>carry AgentLod but NOT gated<br/>— Bundle 1.5 closes this]
    mkt[markets<br/>never LOD'd — ordering risk]

    obs --> dist --> tier --> fire
    fire --no--> skip
    fire --yes--> run
    fac -.unused.-> tier
    mkt -.excluded by design.-> tier
```

### 5.8 Persistence + command flow

```mermaid
flowchart LR
    phase[tick phase writes SimCommand<br/>to CommandBuffer]
    apply[apply phase drains buffer,<br/>executes cross-entity effects]
    dirty[dirty agents → DbWrite]
    ch[mpsc channel]
    pw[PersistenceWorker]
    dedup[dedup by namespace+id]
    flush[5s batch flush<br/>one tx per sweep]
    sqlite[(SQLite WAL)]

    phase --> apply --> dirty --> ch --> pw --> dedup --> flush --> sqlite
```

---

## Part 6 — What's good that we should preserve

When any of these bundles touch core systems, these properties must survive.

- Strategic-vs-tactical AI split (utility picks *which*, BT handles *how*).
- `BtNode<A>` generic action type — no fn-pointer capture problem.
- Command buffer: same-entity mutations inline, cross-entity via `SimCommand`.
- hecs single-writer tick — no locks on agent state.
- Coverage-model pricing with urgency multiplier.
- Reputation gating + age-decay — natural on-ramp for new ships.
- Congestion-aware rest (Phase 18L) and multi-facility dock fallback (Phase 18k).
- Deterministic replay (no wall-clock reads in sim_core).

---

## Part 7 — Generic verification checklist

For every bundle:

- `scripts/verify.sh --strict` clean (155 tests pass + clippy strict).
- `WORLD_SPEED=4 scripts/smoke.sh 60` runs without economic regression (no runaway inflation / mass starvation / stuck contracts).
- `/api/health` p50 tick compute within 200 µs of baseline (~1 ms).
- For AI changes: ship-list panel shows visible diversity in goal selection after 2000 ticks.
- For economy changes: contract board panel shows healthy turnover (no contracts stuck > 5000 ticks).

---

## Part 8 — Pickup instructions for next session

1. `git status` / `git diff` — see what the other Claude changed.
2. Reconcile any conflicts between this plan and current head. Symbol names are stable; line numbers may have moved.
3. Pick a bundle (recommend **3 → 1 → 2 → 4**).
4. For Bundle 1 and 2, produce a per-item implementation sub-plan before coding (one file per item, e.g. `.claude/plans/bundle-1-item-R-causal-trace.md`).
5. For Bundle 3, just do it — ~30 min of file moves.

Session boundaries are natural per-item. Don't try to do more than one Bundle-1 item per session unless they're obviously trivial.
