# simulator-rust — faction interaction + combat roadmap

## Context

The previous plan's Bundles 1–4 are all landed, plus the full GOAP arc, Bundle 4 tranche (S/H/G/Q/K/M/J/P with rep-tier), and the spatial grid (`sim_core::spatial::UniformGrid`, combat-ready). 209 tests, strict clean, fleet behaviour healthy at ~500 agents. See `simulator-rust/CLAUDE.md` for the up-to-date status.

The next arc is **faction interactions** — moving from "factions are economic tax pools" to "factions are political agents with relationships, treaties, rivalries, and (eventually) open warfare." You want the system to support:

- **Allies** — treaty-level friendship that unlocks access and reduces friction.
- **Trade deals** — bilateral agreements that shift pricing, fees, contract visibility.
- **Competing pricing** — markets and contracts that reflect the controlling faction's posture toward the buyer.
- **Competing resources** — contested bodies / stations / systems where multiple factions have interests.
- **Warfare** — full hostile state that triggers combat, blockades, fleet redirection.

This plan is a ramp: each bundle is shippable on its own, establishes primitives the next bundle reuses, and keeps the sim playable throughout. Combat is the final payoff but it's built on the relations/claims substrate below it, not bolted on.

> **Concurrent-edit caveat** still applies. Symbol names (`FactionData`, `SimCommand`, `plan_goal`, `UniformGrid`) are durable anchors; line numbers drift.
> **This file will be copied to `simulator-rust/plan.md`** as the first step of Bundle A.

---

## What's already in place (reuse these)

- **`FactionData`** (`sim_core/src/agents/faction.rs`): treasury, tax + subsidy cycles, construction decisions. Per-faction tick already exists.
- **Per-ship reputation** (`ShipEconomy.faction_reputation: HashMap<String, u8>`, 0..=100): grows on delivery, gates contracts. Ready to inform interaction penalties too.
- **Contract `faction_id` tag** + rep-gated access via `posted_by_faction` rep-tier sub-buckets (committed earlier).
- **`Personality.aggression`** axis on ships (0..=1): currently unused. Perfect input for combat behaviour selection.
- **`SimCommand` buffer**: handles every cross-entity effect atomically. New combat/diplomacy events (DamageShip, DeclareWar, SignTreaty) slot in as new variants.
- **`UniformGrid<T>`** (`sim_core::spatial::UniformGrid`): O(cells) proximity queries. The foundation for "ships within weapon range," "who's in our claim zone," "nearest hostile."
- **GOAP planner** (`sim_core/src/ai/planner.rs`): new operators (Attack, Flee, Patrol) extend it cleanly without touching the search.
- **Event stream** (`ws::protocol::Events`): ship_spawned, contract_delivered, etc. New events (treaty_signed, war_declared, ship_damaged, ship_destroyed) broadcast the same way.

---

## Bundles at a glance

| # | Bundle | Theme | Effort | Risk |
|---|---|---|---|---|
| A | Relations matrix | Data model for inter-faction standing + treaty state | 1 session | Low |
| B | Trade pacts | Treaty-driven pricing + visibility effects | 1 session | Low |
| C | Market posture | Faction-controlled markets charge/discount based on buyer's rep | 1 session | Low-Med |
| D | Territorial claims | Per-body controlling-faction + contested-zone mechanics | 1-2 sessions | Med |
| E | Hostile posture | RelationState::Hostile with refusal-to-dock + surcharges | 1 session | Med |
| F | Combat primitives | HP, weapons, Attack/Flee BT actions, damage events | 2 sessions | High |
| G | Full warfare | War declaration, fleet redirection, truce + capitulation | 2-3 sessions | High |

Recommended order: **A → B → C → D → E → F → G**. A is load-bearing — everything else reads the relations matrix. B/C/D are parallel economic pressure experiments; F/G are the combat escalation.

**Shippable checkpoints:** after A+B you have visibly richer diplomacy with no new UI panels needed. After D you have contested-zone gameplay without combat. After F you have skirmishes between hostile ships. After G you have genuine warfare.

---

## Bundle A — Relations matrix (MVP foundation)

**Goal.** Give every pair of factions a standing score and a treaty state. Every subsequent bundle reads from this one struct.

**Data model** (new file `sim_core/src/agents/faction/relations.rs` or inline in `agents/faction.rs`):

```rust
pub struct FactionRelations {
    /// (faction_a_id, faction_b_id) with a_id < b_id lexically to
    /// canonicalise pairs. Stored as a flat HashMap for O(1) lookup.
    pub by_pair: HashMap<(String, String), RelationState>,
}

pub struct RelationState {
    pub standing: i32,        // -100..=100; 0 = neutral
    pub treaty: TreatyKind,
    pub since_tick: u64,
    pub last_event_tick: u64,
}

pub enum TreatyKind {
    Neutral,
    TradePact,   // bundle B consumes this
    Allied,      // strongest positive (eventually bundle G: forced mutual-aid on war)
    Tense,       // -50 < standing < -20 (no formal hostility yet)
    Hostile,     // bundle E
    War,         // bundle G
}
```

Store one `FactionRelations` entity-resource (use a `hecs::World` resource-like singleton via a top-level struct on `AgentStore`). One entity, all pairs.

**Tick updates.** In `agents/faction::tick_factions` (new sub-pass):

1. Standing drift toward 0 over time (decay constant per 1000 ticks) — old grudges fade.
2. Delivery events trigger standing bumps: a ship delivering for faction X from source-faction Y's market → small +standing between X and Y (mutual trade benefit).
3. Contract theft / breach fires a minus (reputation breach path in `DeliverContract` apply already knows the penalty amount — mirror it to faction relations).
4. Treaty transitions gated by thresholds:
    - standing ≥ +50 sustained 500 ticks → auto-upgrade Neutral → TradePact.
    - standing ≥ +75 sustained 1000 ticks → TradePact → Allied.
    - standing ≤ −50 → Neutral/TradePact → Tense.
    - standing ≤ −70 → Tense → Hostile (requires bundle E live).
    - War is never auto-entered; needs an explicit declaration (bundle G).

**Events + API.**

- Emit `faction_standing_changed`, `treaty_signed`, `treaty_broken` into the engine event Vec.
- `GET /api/factions/relations` returns the matrix.
- `POST /api/admin/factions/:a/relations/:b` sets standing / treaty for debug.

**Files to modify.**

- `sim_core/src/agents/faction.rs` — add `FactionRelations` struct + `tick_relations` sub-pass.
- `sim_core/src/simulation/spawner.rs` — initialise empty relations on world load.
- `sim_server/src/engine.rs` — wire `tick_relations` into the tick loop between `tick_factions` and snapshot.
- `sim_server/src/http/api.rs` — new `factions_relations` handler.
- `sim_server/src/http/admin.rs` — admin override.
- `sim_server/src/snapshot.rs` — publish relations matrix each tick (throttled per Bundle M).

**Verification.**

- Unit tests on `tick_relations`: simulated deliveries move standing; decay returns it to 0; threshold crossings fire the right treaty transitions.
- `/api/factions/relations` returns the matrix; `/api/admin/factions/:a/relations/:b` adjusts it live.
- Smoke: run 2000 ticks, inspect relations matrix at tick 2000; expect some pacts to have formed between high-trade faction pairs.

---

## Bundle B — Trade pacts (treaty-driven economics)

**Goal.** Make `TreatyKind::TradePact` and `Allied` mean something concrete in the economy.

**Effects, all gated on the relations matrix.**

1. **Docking fee discount.** When a ship docks at a facility whose owning faction has a TradePact (or Allied) with the ship's faction, the `DOCK_FEE_BURN_PCT` burn is halved AND the ship pays a reduced base fee. Same code path as the Bundle (G) burn — just a relations lookup at `commit_dock` time.
2. **Contract visibility unlock.** In `ContractBoard::posted_for_ship`, treat the ship as having baseline rep with every TradePact-faction even if no explicit entry exists. Concretely: walk ally factions' buckets even when the ship has no `ship_reputation[fac]` entry.
3. **Payment bonus.** Delivery contract payments scaled +10% when requestor-faction has TradePact with ship's faction. Applied in the `DeliverContract` apply phase.

**Where it plugs in.**

- `engine::commit_dock` — reads ship's faction + facility's owning faction, looks up `FactionRelations`, applies fee modifier.
- `sim_core/src/economy/contracts.rs::posted_for_ship` — extends the iteration with ally-faction buckets.
- `sim_server/src/engine.rs` DeliverContract apply — multiplies payment.

**Verification.**

- Unit test: post a subsidy from faction X, ship is faction-Y with zero rep, Y has TradePact with X → ship can see + accept.
- Smoke: manually set a TradePact via admin endpoint; confirm docking-fee events show reduced burn, contract payments are higher.

---

## Bundle C — Market posture (buyer rep affects price)

**Goal.** Every market has a controlling faction (derived from its primary facility). Ships transacting at that market pay different prices based on their rep with the controller.

**Effects.**

- Buy price paid by ship = `base_price × (1 + (50 - ship_rep_with_controller) × 0.005)`. Range: friend (rep=100) pays 0.75×, stranger (rep=50) pays 1.0×, enemy (rep=0) pays 1.25×.
- Sell price received by ship = inverse curve.
- If relations matrix puts ship_faction and controller at Hostile, surcharge doubles OR the market refuses the transaction (latter is Bundle E's job, keep it soft here).

**Where it plugs in.**

- `sim_core/src/economy/price_engine.rs` — new `posture_multiplier(ship_rep, controller_rep_signal)` that modifies the spread at buy/sell time.
- `agents/ship/actions.rs` — Buy and SellAll actions resolve the controlling faction and apply the multiplier. Currently they just use `pricing.buy_price` etc.

**Verification.**

- Unit tests on `posture_multiplier` bounds + symmetry.
- Smoke: ship with high rep trades at a market; watch credits gained vs base price. Spawn a fresh ship with rep=0, verify it pays more at the same market.

---

## Bundle D — Territorial claims (contested resources)

**Goal.** Model "whose system/body is this?" so contested zones can produce emergent pressure.

**Data model.**

- Each **body** has a `controlling_faction: Option<String>` derived from majority facility ownership (tiebreak: highest total facility credits).
- Each **system** has a `controlling_faction` derived from body majority.
- **Contested flag** on a body: true when ≥2 factions each own ≥1 facility there.

**Emergent effects.**

- Contested body markets get increased shortage urgency + subsidy multipliers (existing Phase 19 subsidy system) — incumbent faction "fights back" by posting better-paid contracts to starve out rivals.
- Ship planner's strategic tier gets a new signal: `in_contested_zone(current_loc) × personality.aggression` feeds into contract score. Aggressive ships gravitate toward contested areas.
- `UniformGrid::query_radius` used here to "find all ships near contested body X" for future territorial pressure calc.

**Snapshot + UI.**

- `/api/bodies/:id` exposes `controlling_faction` + `contested`.
- Godot body highlight color reflects faction palette (cyan/amber/red).

**Files.**

- `sim_core/src/agents/celestial_body.rs` — add `controlling_faction` + `contested` fields; `derive_territorial_control` pass in `tick_factions`.
- `sim_core/src/agents/ship/mod.rs::plan_goal` strategic tier — score bump for contested-zone contracts when personality.aggression > threshold.

**Verification.**

- Unit test: a body with 3 faction-X facilities and 1 faction-Y facility is `controlling_faction = X`, `contested = true`.
- Smoke: seed a contested system (manually spawn cross-faction facilities); observe higher subsidy post rate there vs a single-faction body.

---

## Bundle E — Hostile posture (soft refusal)

**Goal.** `TreatyKind::Hostile` meaningfully changes behaviour without yet introducing weapons.

**Effects.**

- Hostile ships are refused docking at facilities whose owning faction they're hostile with (`commit_dock` returns false with a `refused_hostile` event).
- Hostile ships trigger "wanted" status at that facility → other ships get a warning event, and any active contracts between them auto-cancel.
- Ship planner's `rest_crew` viability check (already exists) treats hostile-faction stations as ineligible. Forces ships to route home or to ally stations.
- Gate fees between hostile factions double (soft blockade). Gate code is in `sim_core/src/world/pathfinder.rs` — add a fee multiplier resolver hook.

**Files.**

- `sim_server/src/engine.rs::commit_dock` — hostile refusal branch + event.
- `sim_core/src/agents/ship/mod.rs::any_rest_destination_viable` — skip hostile-faction stations.
- `sim_core/src/world/pathfinder.rs` — gate-fee multiplier.

**Verification.**

- Set two factions hostile via admin; spawn a ship of faction A, try to dock at faction B station → refused event in log.
- rest_crew planner routes the ship to a non-hostile station instead of piling up at the refused one.

---

## Bundle F — Combat primitives

**Goal.** Ships can shoot each other. Damage accumulates. Destroyed ships get decommissioned with a wreck event.

**Data model additions.**

```rust
pub struct ShipCombat {
    pub hp: f32,              // 0..=100
    pub shields: f32,         // 0..=100
    pub weapon_slug: &'static str,
    pub last_shot_tick: u64,
}

// ShipAction additions:
Attack { target: hecs::Entity },
Flee { away_from: (f32, f32) },
```

**Weapons catalog** (new `sim_core/src/modules/weapons.rs` — mirrors `modules/` subsystem pattern):

- `laser_t1`: 5 damage, 10-unit range, 30-tick cooldown.
- `missile_t1`: 15 damage, 30-unit range, 100-tick cooldown.
- `pd_t1`: 3 damage, 5-unit range, 10-tick cooldown (defensive).

**Combat tick phase** (runs after `decide_and_act`):

1. Build `UniformGrid<Entity>` from ship positions once per tick.
2. For each ship with `ShipAction::Attack { target }`: check range via `grid.query_radius(my_pos, weapon_range)`; if target present, fire weapon, emit `SimCommand::DamageShip { target, dmg }`.
3. Apply phase: deduct shields first then HP; emit `ship_damaged` event; if HP ≤ 0, emit `ship_destroyed` + chain to existing `DecommissionShip`.

**AI integration.**

- `plan_goal` gets new biological-tier-like consideration: if hostile-faction ship in sensor range AND my aggression > 0.5, generate Attack candidate. Score = `ln(target_value) × personality.aggression × HOSTILE_BONUS`.
- If under fire (recently damaged), generate Flee candidate with higher priority for low-aggression personalities.

**Files.**

- `sim_core/src/agents/ship/mod.rs` — `ShipCombat` component, BT action, planner considerations.
- `sim_core/src/agents/combat.rs` (new) — `tick_combat` phase using `UniformGrid`.
- `sim_server/src/engine.rs` — wire combat phase, `DamageShip` / `DestroyShip` SimCommand apply.
- `sim_core/src/modules/weapons.rs` (new) — weapon catalog.
- Migration: add `ships.weapon_slug` column persisted like fitting slots.

**Verification.**

- Unit test: two ships, one Hostile to the other, spawn 8 units apart with `aggression=0.9` → Attack fires, target HP drops, eventually destroyed.
- Smoke: set two factions Hostile via admin, spawn aggressive ships at common system → observe `ship_damaged` and `ship_destroyed` events in the ticker.

**NOTES**
What breaks Rayon: hecs::World allows concurrent reads OR exclusive write, never mixed. If ship A's decide_and_act holds a mut-borrow
  of A's components AND wants to read B's position (to decide "am I in weapon range?"), B can't simultaneously be mutating its own      
  components on another thread. Any live cross-entity read kills parallelism.                                                           
                                                  
  The existing sim already solves this pattern — look at dock_congestion and location_to_system in decide_and_act. They're snapshot maps
   built ONCE at the top of tick_ships (serial, O(n) read pass), then passed into per-ship planning as read-only &HashMap. Per-ship
  threads never touch live world state for cross-entity info.                                                                           
                                                             
  The three rules to encode in Bundle F so combat doesn't become un-parallelizable:                                                     
                                                                                
  1. Build a combat snapshot at the top of the tick, serial. Something like combat_targets: HashMap<Loc, Vec<(Entity, faction_id, hp,   
  position)>>. All targeting decisions read this, not live world components. Same pattern as dock_congestion.
  2. Attack is a command, not a direct mutation. ShipAction::Attack emits SimCommand::RequestAttack { attacker, target, weapon }. The   
  serial apply phase is where range re-check + HP deduction + destroy chain happens. Never write to another ship's components from
  inside a per-ship plan closure.                                                                                                       
  3. Combat tick phase runs AFTER decide_and_act, in its own pass. Per my plan already — but the discipline matters: the combat phase 
  itself iterates sequentially (over the commands buffer), so it's not where parallelism lives. Parallelism lives in decide_and_act     
  deciding which command to emit. The combat phase applying commands is inherently serial because it writes to arbitrary target
  entities.                                                                                                                             
                                                                                
  The subtle one that's easy to miss: "reply" events like "I was just shot, I should flee." The temptation is for the combat phase to   
  directly set the victim's under_fire_until: tick + 100 field. That's fine serial, but if we ever want the victim's next-tick          
  decide_and_act to pick up on it in parallel, the component must already carry that state when the tick begins. So combat-phase writes
  land in components → next tick's snapshot includes them → per-ship threads read from snapshot. Round trip is one tick. 

---

## Bundle G — Full warfare (state machine)

**Goal.** Factions can declare war. War triggers fleet behaviour changes, economic blockades, and can end in truce or capitulation.

**State + transitions.**

- Declare war: `POST /api/admin/factions/:a/declare-war/:b` or AI-driven when standing ≤ −90 and treasury > threshold (willing to fund conflict).
- During War: all contracts between the two factions auto-Expire; subsidy cycles double for home-faction members; gate fees between them 4×; ships of one treat the other as Hostile (auto-target).
- End conditions:
    - **Truce** — both factions' treasuries drop below a floor (can't afford conflict).
    - **Capitulation** — one faction loses ≥75% of its ships within a 5000-tick window.
    - **Treaty** — admin or AI signs a ceasefire (standing snaps to −50, treaty → Tense, 3000-tick cooldown before any escalation).

**AI decisions.**

- `FactionData` gets a `war_posture: WarPosture` field: Peaceful / Ready / Aggressive.
- New faction-tick sub-pass every 500 base-ticks: evaluate relations, treasury, recent losses; transition posture and potentially declare war.
- When at war, a faction biases its ship spawns toward combat-capable classes and directs their patrols via CrewMission-like directed contracts (`ContractType::WarPatrol`? or reuse CrewMission with a `mission_category`).

**Observability.**

- New events: `war_declared`, `truce_signed`, `capitulated`.
- Faction ledger panel in Godot adds a "War posture" column + active-wars list.

**Files.**

- `sim_core/src/agents/faction.rs` — war posture logic, declare/end helpers.
- `sim_core/src/economy/contracts.rs` — contract auto-expire when war declared between participants.
- `sim_server/src/http/admin.rs` — war declaration endpoint.

**Verification.**

- Admin-declare a war; watch contracts between the two factions auto-expire in the board panel. Ships of each start pursuing Attack goals on each other.
- Starve one faction's treasury (admin-adjust) → observe truce event fire.

---

## What to pick up first

Bundle **A** is prerequisite for everything else. If you want to validate the approach cheaply, do A + B together in one session — that's ~150 lines of Rust plus ~50 lines of Godot panel changes and gives you visible "ships of allied factions pay less at each other's stations" behaviour without any combat code.

Then D is probably the next big gameplay addition (contested zones feel emergent even without combat). E is a prerequisite for F (ships need a refusal-to-dock mechanic before they'll try Attack).

**Deferred to later sessions (noted in backlog for continuity):**

- **(N) Rayon on ship phase** — still the real 10k-ship unlock. Complementary to combat (Attack phase is cross-ship-write-heavy, so a rayon refactor would need to batch those commands carefully).
- **Fog-of-war / sensor-filtered observability** — combat wants "ship X saw Y jump" events, which the current LOD system doesn't model.
- **Pirates / third-party hostile factions** — once F + G are working, "no-faction" raider ships become cheap to add.

---

## Verification (session-level)

For each bundle:

- `scripts/verify.sh --strict` clean (all tests pass + clippy strict).
- `WORLD_SPEED=4 ./target/debug/simulator` smoke run to tick 2000+; confirm new behaviour via `/api/factions/relations`, `/api/contracts`, event ticker.
- Godot panels reflect new state without needing UI work in Bundle A (relations visible via admin endpoint for now; UI lands in a later pass).

---

## Pickup instructions for next session

1. `git status` / `git log --oneline -10` — confirm we're picking up from the spatial-grid / rep-tier commits.
2. Read `simulator-rust/CLAUDE.md` Status section to refresh on what's landed.
3. Start Bundle A. Draft the `FactionRelations` struct first; get it into `AgentStore` + one unit test; then wire the tick pass; then the API.
4. After A, commit. Pick B next in the same session if time permits.

Core principle throughout: **relations matrix is the single source of truth.** Every other bundle reads from it; no bundle introduces parallel per-faction state that could drift.
