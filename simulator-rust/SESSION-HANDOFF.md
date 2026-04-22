# Session Handoff — Fresh Claude Start Here

A one-pager so a new Claude session can pick up this project without
reading the full history. Read this first, then `CLAUDE.md`, then
anything else as you need it.

## Where we are

**Phases 1–17 shipped.** 100 tests passing, strict clippy clean. Sim
runs 806 agents (223 ships + 62 facilities including 6 gates + 23
markets + 19 pops + 6 factions + 23 bodies) at p50 ≈ 0.5 ms / p99 ≈
2 ms per tick on an M1 Mac. Full economic loop, per-faction rep-gated
contracts, observer-driven spatial LOD for ships, facility autonomy
with abandonment, admin CRUD including runtime spawn, SQLite
persistence that round-trips ships / markets / factions / facilities /
populations / bodies / tick counter across restart. Godot client has
13 toggle-able inspector panels. Phase 17 added inter-system jump
gates: no direct cross-system routes, all cross-system travel routes
through a gate, each jump pays a fee (flat + per-cargo). Transit lines
now converge into gate highways instead of scattering across the
galaxy.

The user said **"things seem to be running well"** — no bugs
blocking. Feature work is paused. **Next session owner is taking
this over for agent stats/systems work (ships → facilities → crews).
See the dedicated section at the bottom of this file.**

## What just shipped (most recent first)

- **Phase 17** — Inter-system jump gates. 6 gates (one per system-pair direction) seeded with `facility_type = "gate"` + a `GateLink` component (paired-id, flat fee 200cr, per-cargo 2cr, throughput cap 3 ships/tick — queue deferred). Removed direct cross-system `travel_routes` from world JSON. Added Dijkstra pathfinder (`world/pathfinder.rs`) over locations + gate-pair edges. Ship BT builders now call `route_actions(from, to)` which expands any destination into a `Travel → GateJump → Travel` chain as needed. `ShipAction::GateJump` emits a `RequestGateJump` command; apply phase checks the fee, credits the gate, teleports the ship to the paired gate's position. Contract planner rejects contracts where `buy_cost + gate_fees >= payment`. Godot renders gates with the heaviest station model at 2.4× scale + a cyan emissive torus ring + a soft idle pulse so they read as portals from a distance. **Live-verified**: 42 ships at/heading-to a gate in a 40s smoke, fees flowing into gate treasuries.
- **Phase 15g** — LOD tier distribution surfaced on `/api/health.perf.lod` and rendered in the perf HUD (`d1:215 d2:3 d10:5 d50:0`). Perf overlay polls `/api/health` once per second while open.
- **Phase 15a–f** — Observer-driven spatial LOD for ships. `AgentLod { divisor, next_tick }` component, tier table 1/2/5/10/20/50 by distance to nearest observer, `try_fire(tick) → Option<skipped_ticks>` cursor. Ships' fuel burn + crew hunger/fatigue scale by `skipped_ticks` so total state change over wall-clock is preserved. Godot sends a `"camera"` observer every 50 ms with radius scaling off zoom. **Facilities + pops carry `AgentLod` for stats but don't gate yet** — Phase 16 candidate.
- **Phase 14** — Market panel fix. Two bugs: (1) Godot read `market.facility_id` but Rust emits `facility_location`; (2) a `replace_all` Edit from my earlier session left an indent mismatch in `details_panel.gd` that parse-errored and cascaded through scene loading. Both fixed.
- **Phase 13a–g** — Godot inspector panels. Events ticker (filterable stream, click → focus camera), contract board (6-kind/6-status filter, sortable), faction ledger (treasury + active subsidies + ship/fac counts), population browser (count/sentiment/food_sat with colour coding), perf overlay (p50/p99 µs + FPS + 60-sample sparkline + LOD tiers). Rust side: `contract_states` broadcast, `/api/health.perf`, `POST /api/sim/step {ticks}` for stepping while paused. Details panel gets "Recent activity" from the events ring.
- **Phase 12a–d** — Runtime admin ship/facility spawn (replaces Phase 11g's 501 stubs); facility/pop/body persistence; crew mission catalog (9 Elixir templates ported to `economy/missions.rs`) with full ship BT flow + skill XP; contract rep gating (Subsidy=70, CrewMission=50, Delivery=0) with age-open decay 10 rep / 100 ticks.
- **Phase 11a–g** — Elixir-parity sweep. Crew `current_task` + skills + hunger, facility autonomy (degrade / self-repair / restock / post contracts / level / abandon), pop urgency bids + passenger contracts, faction subsidy (1.25× → 3.0× multiplier on chronic shortages), body biome + regen, 6 contract kinds, events broadcast, admin HTTP endpoints.

Earlier phases (1–10) are the pure-logic + server + persistence + Godot-protocol foundation. See [`PLAN.md`](./PLAN.md) for full detail.

## How to run it, today

```bash
# Terminal 1 — Rust sim
cd /Users/dclausen/code/spaceproject/simulator-rust
WORLD_SPEED=4.0 cargo run --bin simulator

# Terminal 2 — Godot (dev.env already has SPACESIM_USE_EXISTING_SERVER=1)
cd /Users/dclausen/code/spaceproject/client
godot project.godot
```

Or for a quick headless check:

```bash
cd simulator-rust
scripts/verify.sh --strict   # cargo check + test + clippy
scripts/smoke.sh 15          # boot 15 s with temp DB, print log tail
scripts/persist-test.sh      # confirm restart resumes from persisted tick
```

Default `WORLD_SPEED=0.25` is the "chill play" pace (Earth↔Mars ≈ 4 min).
`4.0` is the smoke-test default — economy converges in tens of seconds.

## Verification one-liners

```bash
# Against a running sim on :8080 (or :8091 for test runs)
curl -s localhost:8080/api/health | jq '.perf'
curl -s localhost:8080/api/contracts | jq '.data | length'
curl -s localhost:8080/api/observers | jq .

# Admin spawn smoke-test (Phase 12a):
curl -sS -X POST -H 'Content-Type: application/json' \
  -d '{"class":"freighter","faction_id":"terran-authority","location":"earth-station","credits":10000}' \
  localhost:8080/api/admin/ships | jq .

# Step-debug (Phase 13b):
curl -s -X POST localhost:8080/api/sim/pause
curl -s -X POST -H 'Content-Type: application/json' -d '{"ticks":8}' \
  localhost:8080/api/sim/step
```

## Open candidates (none urgent)

- **Phase 16 — facility + population LOD rate scaling.** They carry
  `AgentLod` for the stats readout but their per-tick phases don't
  gate on it. ~75 agents vs 223 ships, so small gain; recipe
  `max_batches` + sentiment inertia would need careful scaling.
- **Command trace / replay.** Server-side ring of every `SimCommand`
  per tick, `/api/debug/ship/:id/trace?ticks=100` filters by agent.
  Architecture supports it — commands are plain data. Build when a
  specific "I wish I could rewind this" bug shows up.
- **Windows native build validation.** Cross-compile is scaffolded
  (`x86_64-pc-windows-gnu` + bundled SQLite). Waiting on a Windows box.
- **Rayon parallelism.** Dependency is in, never called. Architecture
  has no cross-ship writes within a phase. Skip until 10k+ agents.
- **Spatial-LOD chunk ring overlay on minimap.** Visual "here's where
  the sim is giving you full fidelity vs throttling."

## Watch-outs / gotchas

- **Market snapshots key on `facility_location`, not `facility_id`** —
  Phase 14 bug. If Godot UI code ever grabs `m.facility_id`, it's stale.
- **"No observer" ≠ "LOD'd out"**. No observer → everything runs at
  divisor 1 (full fidelity). Tested in `simulation::lod`.
- **Editing a `.gd` file can cascade.** Godot's scene loader fails
  hard on a parse error in one script and silently wedges unrelated
  panels. After editing GDScript, reload the project in the editor
  (Ctrl+Shift+T or restart) to see the real errors. `market_overlay`
  has a `DEBUG` flag you can flip on.
- **The tick loop owns `hecs::World` exclusively.** HTTP / WS handlers
  read from `SnapshotCache` (DashMap), never touch the live world.
  Cross-entity state changes MUST go through `SimCommand` so they
  apply in a dedicated phase. Same-entity mutation is in-place and fine.
- **Ship LOD rate scaling depends on `skipped_ticks`.** If a ship
  hasn't fired for 10 real ticks and fires now, it burns 10× fuel in
  that one tick. If you add a new per-tick ship rate, multiply by
  `effective_scale = tick_scale × skipped_ticks`, not raw `tick_scale`.

## Critical files to read first

1. **`crates/sim_server/src/engine.rs`** — the tick loop. Phase order,
   LOD recompute, admin spawn dispatch, event drain. One file to
   read to understand how everything hangs together.
2. **`crates/sim_core/src/agents/ship.rs`** — most complex agent.
   LOD gate (`active` map), BT execution, ShipAction enum. Shows the
   canonical "pass tick_scale, rate-scale per-ship, emit SimCommands"
   pattern.
3. **`crates/sim_server/src/ws/protocol.rs`** — wire format truth.
   Every client/server message type lives here.
4. **`crates/sim_core/src/simulation/lod.rs`** — LOD math + tests.
   Small, self-contained, well-tested.
5. **`crates/sim_core/src/simulation/commands.rs`** — `SimCommand`
   enum. Every cross-entity effect goes through here. Read the
   variants to understand what the sim is even capable of.
6. **`client/scripts/autoload/network_manager.gd`** — Godot WS entry.
   Every message handler, every HTTP call.
7. **`client/CLAUDE.md`** — the client's own orientation doc, kept
   in sync with this one.

## Next session's first move

Read this doc + `CLAUDE.md`, then ask the user which open candidate
they want (or if they're mid-bug from their Godot testing). Don't
assume the audit plan in `~/.claude/plans/welcome-to-the-space-wobbly-wirth.md`
is still current — it's historical.

---

# 📋 Stats + systems work — briefing for next Claude

The user is handing off to a fresh session to build out **"stats"
and "systems" for agents, starting with ships → facilities →
crews.** What follows is context so you don't have to reverse-engineer
the current design. **Ask the user for their specific goals first**
— this is a sketch of what I think they might want based on our
conversation, not a committed scope.

## What "stats" probably means

The economic simulator today has these per-agent numbers:

- **Ship**: credits, fuel, cargo (13 commodities × qty), faction_reputation map, efficiency, broke_strikes, hoard_strikes, idle_ticks. Plus aggregate crew: morale, fatigue, hunger, health, wages, current_task, 4 skills (nav/eng/trade/combat), size.
- **Facility**: condition, reputation, credits, docking_capacity, reserves (13 commodities), level, xp, abandon_counter, abandoned flag. Plus gate link when applicable.
- **Crew** (aggregate on ship, not individual entities): the ship's `ShipCrew` fields above.

"Stats" in a sim-game context usually means **attributes that modify
behavior / outcomes** — think class-based RPG stats: attack, defense,
speed, charisma, etc. Today we have a few of those (skills on crew,
condition on facility) but they're each ad-hoc.

**What the user might want** (ask to confirm):

1. **Explicit stat blocks per agent type**, not scattered fields.
   E.g. `ShipStats { hull, shields, speed, maneuverability, sensor_range }`,
   `FacilityStats { manufacturing_efficiency, repair_rate, security, ... }`,
   `CrewStats { leadership, technical, combat, negotiation, ... }`. Each
   agent rolls up its crew's stats to modify its own.
2. **Derived outcomes** — stats should visibly affect what the agent
   can do. A high-combat crew wins a pirate encounter, a high-tech
   facility repairs faster, a sensor-heavy ship spots contracts
   others miss.
3. **Progression** — stats grow over time via activity (already have
   crew skill XP on Buy/Deliver; extend to ships + facilities).
4. **UI surfacing** — Godot details panel needs a "stats" section.

## What "systems" probably means

This is vaguer. "Systems" in Minecraft / EVE / factorio-speak usually
means *named mechanics the player has to learn* — e.g. "the piracy
system", "the contract system", "the reputation system".

**Likely work** given where we are:

1. **Pirate / combat system** — ships get attacked in certain
   sectors, can lose cargo, crew injury. Hooks into faction-security
   stats.
2. **Crew growth / promotion / turnover** — right now `ShipCrew` is
   static-sized. Could add hiring / firing / poaching, crew members
   get promoted when skilled enough.
3. **Ship upgrades / equipment slots** — engines, cargo-bay extensions,
   hull plating. Another stat multiplier layer.
4. **Facility upgrades** — bigger docking bays, better refineries,
   security drones.
5. **Mission types beyond the current 9 crew templates** — rescue,
   escort, bounty, scouting. Each exercises different stats.

## Architectural considerations for whoever builds this

These are hard-won constraints from phases 1–17. Don't fight them.

- **sim_core stays pure.** No tokio, no sqlx, no axum. Stats logic
  belongs in `sim_core/src/agents/*` or `sim_core/src/stats/*`
  (if you create a new module). Pure functions are trivially testable.
- **New component > new field on existing component.** hecs archetype
  storage means adding a field to e.g. `ShipCrew` re-allocates every
  ship's storage. A new `ShipStats` component is cleaner and lets
  ticks query only what they need. Same pattern as the
  `FacilityLifecycle` / `GateLink` split.
- **Cross-entity mutations go through `SimCommand`.** When stats
  modify the outcome of a cross-entity action (ship attacks ship,
  facility grants reputation), the outcome still goes through the
  command bus. Don't mutate another entity mid-tick.
- **Persistence is opt-in per field.** `DbWrite` variants in
  `sim_server/src/db/persistence.rs` explicitly list which fields
  flush. When you add a stat field, decide whether it's dynamic
  (flush) or static-at-spawn (don't — read from seed on each boot).
- **Snapshot vs component.** Internal stats live as components; the
  wire shape is the `*Snapshot` struct in the same file. Godot only
  sees what's in the snapshot. Don't expose internal-only fields.
- **Events.** Notable stat changes (level up, skill cap, crew
  promotion, pirate defeat) should emit an event via the existing
  events broadcast — that's what the Events ticker panel feeds on.
- **LOD awareness.** Ship-tick gating in `tick_ships` already filters
  by `active: ShipLodGate`. Any new stat-driven per-tick logic
  should respect that same gate to preserve the spatial LOD savings.
  If rates scale with `skipped_ticks`, do the multiplication
  consistently (see `advance_transits` fuel burn for the canonical
  pattern).
- **Reuse existing scaffolding.**
  - `ShipCrewSkills` already has skill XP + cap + `grant()`. Extend
    it rather than create a parallel system.
  - `FacilityLifecycle.level / xp` already supports progression.
    Extend its `grant_facility_xp` semantics for other activities.
  - `economy/missions.rs` is the catalog pattern — if you add ship
    upgrade types / crew roles / pirate encounter templates, follow
    that same "static catalog + lookup by slug" shape.
  - `economy/reputation.rs` exists (small today) — it's the natural
    home for cross-faction stat math.

## Questions to ask the user before building

1. **What's the playable verb?** Are ships combat-capable (so stats
   matter in encounters), or are stats purely economic modifiers?
2. **Individual crew vs aggregate?** Today crew is aggregated per ship.
   Moving to individuals would 4× the entity count (~3200 crew members).
   Worth the cost? Or keep aggregate + add a named-captain layer on top?
3. **Are stats rolls or modifiers?** "Attack = 15 + d20" (random) vs
   "this ship's trade skill gives +10% margin" (deterministic). Big
   architectural impact — rolls need a seeded RNG in sim_core.
4. **What surfaces do the stats drive?** Just the details panel?
   Combat outcomes? Contract eligibility? Employment market?
5. **How much retro-fit?** Do existing agents need new stats
   backfilled (migration + seed file edits), or only newly-spawned
   ones?

## Files to read first

1. `crates/sim_core/src/agents/ship.rs` — `ShipCrew` + `ShipCrewSkills`
   + `CrewTask` — the current crew-stats model.
2. `crates/sim_core/src/agents/facility.rs` — `FacilityOperations` +
   `FacilityLifecycle` + `GateLink` — the component-split pattern.
3. `crates/sim_core/src/economy/missions.rs` — static-catalog pattern
   that new "template" types should follow.
4. `crates/sim_core/src/simulation/commands.rs` — every cross-entity
   outcome goes through here. Adding stat-driven outcomes means adding
   variants here.
5. `crates/sim_server/src/ws/protocol.rs` — wire format. New stats
   visible to Godot need `*Snapshot` fields and usually their own
   broadcast cadence.
6. `client/scripts/ui/details_panel.gd` — where per-agent stats get
   rendered. The "Recent activity" section it has today is a useful
   precedent for how to fold new display sections in.

## Constraints to preserve

- `verify.sh --strict` should stay green. Add tests.
- No new heavy dependencies (no `bevy_ecs`, `actix`, `hyper` replacement).
  Stick to the existing stack.
- Don't break persistence round-trip. If you add a new persisted
  field, update `DbWrite` + the spawner's load path in the same PR.
- Don't regress tick budget. Watch p99 — stay under 5 ms at 800
  agents. Use LOD gating for anything rate-bearing.
