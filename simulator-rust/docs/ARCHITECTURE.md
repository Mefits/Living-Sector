# simulator-rust architecture

Living diagrams of the Rust space-economy simulator. For the per-system behavior table, see the "Systems wired" section of [CLAUDE.md](../CLAUDE.md). For the current improvement backlog, see [plan.md](../plan.md).

> Update rule: when a phase is added to the tick loop, a new contract kind is added, or a new agent type is introduced, update the affected diagram below in the same PR.

---

## 1. Tick loop phase graph

The tick is a fixed sequence of phases with exclusive mutable access to `AgentStore`. No locks, no intra-tick async. Order is hardcoded in `engine::run_tick_loop` and must not be reordered casually — several phases depend on the previous phase's apply step (e.g. markets tick *after* ships+facilities so this tick's supply changes land before price recalc).

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

---

## 2. Runtime data ownership

`sim_core` is pure (no tokio/sqlx/axum). `sim_server` bridges async IO to the pure world. The tick loop owns `&mut AgentStore` exclusively; HTTP and WS handlers only read from `SnapshotCache`. Persistence is a sibling tokio task consuming a buffered mpsc channel so disk IO never stalls the tick.

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

---

## 3. Ship decision stack

Strategic layer (utility + priority waterfall in `plan_goal`) picks *which* goal. Tactical layer (`BtNode<ShipAction>` resumable tree) handles *how* to execute it. Dispatch is via a closure in `execute_ship_action` that holds the mutable component borrows for this ship, keeping the BT engine generic and reusable.

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

---

## 4. Economic feedback loop

The living-economy loop is genuinely closed: shortages propagate to contracts, contracts pull ships, deliveries restore supply, and factions step in (subsidies then construction) when market incentives alone can't close the gap.

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

---

## 5. Contract lifecycle

All six contract kinds (Delivery / Courier / Passenger / Subsidy / Supply / CrewMission) share this lifecycle. Reputation gates start at 0 / 50 / 70 depending on kind and decay −10 rep per 100 ticks until public. Payment escalates +5% per 50 ticks (cap +100%) to incentivise fulfilment of stale demand.

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

---

## 6. Market 8-phase tick

Each market runs eight ordered sub-phases per tick. The coverage model treats supply as a *buffer* (not a ratio) so stockpiles stabilise prices rather than depress them. Urgency multiplier ramps 1.0 → 2.5 over a 50-tick shortage window so persistent scarcity keeps pressure climbing.

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

---

## 7. LOD gating

Observer-driven distance tiers assign each agent a tick divisor (1, 2, 5, 10, 20, 50). A ship outside all observer radii fires every 50 ticks; per-tick accumulators (fuel burn, crew hunger) scale by `skipped_ticks` so total state change over wall-clock matches. Facilities and populations carry `AgentLod` but their tick phases don't gate on it yet — see plan.md Bundle 1.5. Markets are never LOD'd because ordering sensitivity makes skipped ticks unsafe there.

```mermaid
flowchart TD
    obs[observer positions<br/>from WS hello]
    dist[distance² to nearest observer]
    tier[divisor ∈ 1,2,5,10,20,50]
    fire{tick >= next_tick?}
    skip[skip this tick]
    run[run ship phases<br/>scale fuel burn + crew needs by skipped_ticks]
    fac[facilities + populations<br/>carry AgentLod but NOT gated]
    mkt[markets<br/>never LOD'd — ordering risk]

    obs --> dist --> tier --> fire
    fire --no--> skip
    fire --yes--> run
    fac -.unused.-> tier
    mkt -.excluded by design.-> tier
```

---

## 8. Persistence + command flow

Cross-entity effects go through `SimCommand` (enum, ~40 variants) collected into a `CommandBuffer` per tick. The apply phase drains the buffer and executes atomically. Dirty agents emit `DbWrite` to an mpsc channel; the persistence worker dedups by (namespace, id) and flushes to SQLite every 5 s (or on-demand via admin save).

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

## Cross-references

- [CLAUDE.md](../CLAUDE.md) — Systems wired table (behavior-per-module), crate layout, conventions.
- [SESSION-HANDOFF.md](../SESSION-HANDOFF.md) — fresh-session orientation.
- [plan.md](../plan.md) — bundled improvement roadmap.
