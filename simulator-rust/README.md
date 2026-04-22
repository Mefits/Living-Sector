# simulator-rust

A space-economy simulation engine written in Rust. Replaces the Elixir/Phoenix
version for native Windows/Linux performance. Ships today at 800 agents with
room to scale to 100k+. Godot is the sole client.

> **Status**: Phases 1–15 complete. Phase 13 brought Godot-side inspector
> panels (events ticker, contract board, faction ledger, population browser,
> perf overlay), broadcast handlers for population/faction/contract/events
> streams, step-debug (`/api/sim/step`), rolling perf metrics on `/api/health`,
> and an inspect-trail on the details panel. Prior: Feature parity with the Elixir sim across
> the full agent catalog — ship dock-dwell, crew task/skills/hunger, facility
> autonomy (degradation/self-repair/restock/contract posting/leveling/abandonment),
> population urgency bids + passenger transport, faction tax + subsidy, body
> biome + resource regen, 6 contract kinds, **rep-gated + age-opening
> subsidies**, **9 crew-mission templates**, event stream, full admin HTTP
> endpoints (**including runtime ship/facility spawn**), and **facility /
> population / body persistence** on top of ships/markets/factions/tick.
> See `~/.claude/plans/welcome-to-the-space-wobbly-wirth.md` for the audit.

## Quick start

```bash
# from simulator-rust/
scripts/verify.sh          # cargo check + test + clippy  (95 tests)
scripts/smoke.sh 10        # build, boot sim for 10s, print log + DB counts
scripts/ws-test.sh 6       # boot + exercise every HTTP endpoint
scripts/persist-test.sh    # boot, kill, reboot — verify tick resumes
```

Then with the sim running:

```bash
curl localhost:8080/api/health
curl localhost:8080/api/ships | jq '.data[0]'
curl localhost:8080/api/markets | jq '.data[0].prices'
curl -X POST localhost:8080/api/sim/pause
curl -X POST localhost:8080/api/sim/resume
```

## Environment variables

| Var | Default | Effect |
|---|---|---|
| `RUST_LOG` | `simulator=info,sim_core=info` | Tracing filter (use `trace` for sqlx query logs) |
| `WORLD_SPEED` | `0.25` | Game-time multiplier at startup. `0.25` = chill play pace (Earth↔Mars ≈ 4 min). `4.0`+ for smoke tests. Adjustable at runtime via `POST /api/sim/speed {world_speed: N}`. |
| `BIND_ADDR` | `127.0.0.1:8080` | HTTP/WS bind address |
| `DATABASE_PATH` | `./sim.db` next to binary | SQLite path. Use `mktemp` for ephemeral tests. |
| `DATA_DIR` | auto-resolved | World JSON root (dev: `../../priv/data`; release: `./priv/data`) |

## Architecture

- **sim_core** — pure Rust, no async, no I/O. hecs ECS, all tick logic. Trivially
  unit-testable because it doesn't need tokio.
- **sim_server** — tokio runtime, axum HTTP+WebSocket, sqlx SQLite. Thin glue
  layer that wraps `sim_core::AgentStore` in a tick-loop task and exposes
  snapshots to Godot.
- **hecs** for entity/component storage. Every agent type is a bundle of small
  components split by access pattern, so tick phases only load what they touch.
- **Command buffer** (`SimCommand`) for all cross-phase effects. Phases read
  world state, write commands, and never mutate mid-phase. Deterministic.
- **SnapshotCache** (`DashMap`) for HTTP/WS reads — tick loop publishes
  at the end of each tick; handlers read without touching live `AgentStore`.

### Tick phase order (125 ms)

1. Drain control channel (pause/resume/speed/step + admin spawn/remove + observer updates)
2. Celestial bodies — orbital angles advance
3. Body resource regen (every 5 ticks × mult) — mined resources grow back toward seed caps
4. LOD recompute (every 50 ticks × mult) — per-agent `AgentLod.divisor` from nearest observer
5. Ships — LOD-gated 4 passes: advance transits → observe prices → tick crew → decide + BT step (rate-scaled by skipped_ticks)
6. Apply ship commands (supply deltas at markets; dock fees; facility refuel drains; events)
7. Facilities — condition degrade every tick; self-repair / abandonment / restock / recipes / contract posting on their own intervals
8. Populations — consume/produce, urgency bids, post food + passenger contracts, sentiment inertia
9. Markets — 8 sub-phases (produce/consume/emergency/surplus/match/demand/shortage/prices)
10. Apply market commands (spread revenue → facility)
11. Factions — tax (every 200 ticks × mult, 0.5% above 1000-credit buffer) + subsidy posting (every 30 ticks × mult)
12. SnapshotCache update (ships/markets/facilities/pops/factions/contracts/positions)
13. Broadcast: `positions` every tick, `ship_states` every 8, `market_states`/`facility_states`/`population_states` every 16, `faction_states`/`contract_states` every 32, `events` every tick when non-empty
14. Emit dirty-entity DbWrites → persistence worker (ships every tick; facilities/pops every 16; bodies every 40; tick counter every 8)

Tick cost at 800 agents: p50 ≈ 0.5 ms, p99 ≈ 2 ms on M1 Mac. 125 ms budget → 99%+ headroom.

## What the simulator does

| System | Behavior |
|---|---|
| **Trade** | Ships scan known prices, pick the highest-margin route, travel buy→sell; cargo leaves/arrives at market supply |
| **Dock dwell** | Ships request docking (fee scales with occupancy × condition), refuel draws from facility reserves over ~20 ticks, unload one commodity per tick. Crews take shore leave when morale <35 and dwell until 100. |
| **Contracts** | 6 kinds: Delivery / Courier / Passenger / Subsidy / Supply / CrewMission. Populations post food-delivery when satisfaction <40 (with urgency-scaled payment), and passenger contracts when happy + populous. Facilities post delivery + courier when chronically short. Factions post subsidy contracts for member-market shortages. |
| **Recipes** | Refineries smelt ore+fuel→metals, process ice→water+fuel etc.; factories build components/electronics/tools/medical/luxury; farms grow food. Higher facility level = more batches per cycle. |
| **Mining** | `mining_rig` facilities extract commodities from their body's resources; those resources regen each 5-tick cycle toward their seeded ceilings. |
| **Facilities** | Condition drifts down every tick; self-repair costs tools; reserves are restocked from local market when low; posted contracts pull supply from afar; XP accumulates per recipe → level 1–10. After 200 ticks of broke + no-tools + low-condition, facilities flip `abandoned` and go dormant. |
| **Populations** | Consume food/fuel (with emergency water buffer under satisfaction<30), produce labor commodity, sentiment inertia (0.9^tick_scale smoothing), grow on delivered passengers. |
| **Crew** | Aggregate `current_task` (piloting / engineering / trading / eating / resting) displayed per-ship. Hunger rises, eating consumes food from cargo. Skills (nav / eng / trade / combat) earn XP on trades + deliveries, capped 100. Unpaid wages drop morale. |
| **Factions** | 0.5% tax on facility credits above a 1000-credit buffer every 200 base-ticks → treasury. Subsidy contracts posted when ≥2 member facilities chronically short (1.25× → 3.0× payment ramp); max 3 active per faction. |
| **Bodies** | Orbit advances each tick. `BodyBiome` exposes a food-availability multiplier (0.1–1.5) read by pop growth. `BodyResources` regen toward `max_resources` every 5 ticks. |
| **Reputation** | Contracts tagged with posting faction; ships earn +1 rep per delivery to that faction (0–100). |
| **Events** | Per-tick broadcast of notable moments: `ship_docked`, `contract_delivered`, `passengers_arrived`, `market_supply_adjusted`, etc. Godot's HUD subscribes for toasts. |
| **Admin endpoints** | Godot god-mode: POST spawn ships + facilities (INSERT + hand off to engine → 201 with new id), DELETE by id, adjust market supply, save / save-as DB snapshots (VACUUM INTO). |
| **Spatial LOD** | Ships throttle based on distance to the camera observer. Tier table 1 / 2 / 5 / 10 / 20 / 50 — distant ships still tick, just less often, with state changes rate-scaled by `skipped_ticks`. Godot sends `move_observer` from the camera every 50 ms; radius scales with zoom. |
| **Inspector panels** | Godot-side debug UI: events ticker, contract board, faction ledger, population browser, perf overlay (p50/p99 tick time + LOD tier breakdown + FPS sparkline). All toggle from HUD buttons. |
| **Persistence** | Every 5s, dirty ship/market/faction state + tick counter flushes to SQLite. Sim resumes from persisted tick on restart. |

## Agents (at current seed)

| Type | Count | Notes |
|---|---|---|
| Ships | 223 | 5 classes (courier/freighter/hauler/tanker/miner), 6 factions |
| Facilities | 56 | Mining rigs, refineries, factories, stations, farms, outposts |
| Markets | 23 | One per station/outpost, 13 commodities |
| Populations | 19 | Per-facility demographic blocs (workers, merchants, scientists) |
| Factions | 6 | Terran, Mars, Belt, Frontier Ventures, Crucible, Doughtys |
| Celestial bodies | 23 | Planets, moons, belts across Sol / Alpha Centauri / Tau Ceti |
| Travel routes | 68 | Bidirectional pairs |

## Godot client integration

The Godot `client/` has been updated to speak the new plain-JSON WebSocket
protocol (see
[`crates/sim_server/src/ws/protocol.rs`](crates/sim_server/src/ws/protocol.rs)).
The previous Phoenix-Channels version is preserved as
`client/scripts/autoload/network_manager_phoenix.gd.bak`.

### Dev loop — Godot + Rust sim

```bash
# Terminal 1 — run the Rust simulator
cd simulator-rust
WORLD_SPEED=4.0 cargo run --bin simulator

# Terminal 2 — launch Godot
cd ../client
# dev.env already has SPACESIM_USE_EXISTING_SERVER=1, so Godot won't
# spawn a BEAM and will connect to localhost:8080 directly.
godot project.godot
```

### Fallback to legacy Elixir sim

If you want Godot on the old Elixir simulator, set
`SPACESIM_TARGET_ELIXIR=1` in `client/dev.env`. ServerManager will route to
port 4000. You'll also need to swap `network_manager.gd` for the `.bak` file
since the new one doesn't speak Phoenix Channels anymore.

## Adding content

Edit JSON in `priv/data/worlds/*.json` (star systems, bodies, locations,
facilities, markets, ships, populations) and `priv/data/factions.json`.
The seeder is idempotent — restart with a fresh DB (e.g. `mktemp -t *.db`)
to load changes.

## Dev scripts

| Script | Purpose |
|---|---|
| `scripts/verify.sh [--strict]` | cargo check + test + clippy (strict fails on warnings) |
| `scripts/smoke.sh [secs]` | Build, boot with temp DB, print log + DB counts |
| `scripts/ws-test.sh [secs]` | Smoke + exercise every HTTP endpoint |
| `scripts/check-api.sh` | Hit already-running sim's endpoints |
| `scripts/persist-test.sh` | Verify tick counter + agent state persist across restart |

## Not yet implemented

- **Windows native build** — cross-compile is set up (`rustup target add
  x86_64-pc-windows-gnu`) but we haven't validated on a Windows box. The
  binary is single-file with bundled SQLite; should Just Work.
- **Rayon parallelism** — dependency is in, never called. Unnecessary until
  10k+ agents. Architecture is designed for it (no shared mutable state
  between ships in a phase).
- **Spatial LOD for facilities + populations** — Phase 15 wired ships
  (the lion's share of the tick cost); facilities + pops carry an
  `AgentLod` for the debug views but their per-tick phases don't gate
  on it yet. ~75 agents, interval-driven phases, minor gain — Phase 16
  candidate if a 10k-agent push exposes them as a bottleneck.

## License

Same as the parent spaceproject repo.
