# simulator-rust

A space-economy simulation engine written in Rust. Replaces the Elixir/Phoenix
version for native Windows/Linux performance. Ships today at 800 agents with
room to scale to 100k+. Godot is the sole client.

> **Status**: Phases 1–10 complete. Full feature parity with the Elixir sim
> for the core economy loop (mining → refining → manufacturing → consumption,
> plus population-posted contracts and faction treasuries). State persists
> across restarts. Godot WebSocket client updated. See [`PLAN.md`](./PLAN.md)
> for the session log.

## Quick start

```bash
# from simulator-rust/
scripts/verify.sh          # cargo check + test + clippy  (64 tests)
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

1. Drain control channel (pause/resume/speed from HTTP/WS)
2. Celestial bodies — orbital angles advance
3. Ships — observe prices, decide goal, execute one BT step, emit commands
4. Apply ship commands (supply deltas at markets)
5. Facilities — run recipes, mine from bodies
6. Populations — consume/produce, post food contracts when stressed
7. Markets — 8 sub-phases (produce/consume/orders/match/prices)
8. Apply market commands (spread revenue → facility)
9. Faction tick (every 50 base ticks) — 5% tax on owned facility credits
10. SnapshotCache update + broadcast (positions every tick, ships every 8, markets every 16)
11. Emit dirty-entity DbWrites → persistence worker

Tick cost at 800 agents: ~3–5 ms on M1 Mac. 125 ms budget → 96%+ headroom.

## What the simulator does

| System | Behavior |
|---|---|
| **Trade** | Ships scan known prices, pick the highest-margin route, travel buy→sell; cargo leaves/arrives at market supply |
| **Contracts** | Populations post food-delivery contracts when satisfaction <40; ships fulfill them (accept → buy at source → deliver at destination → collect payment) |
| **Recipes** | Refineries smelt ore+fuel→metals, process ice→water+fuel etc.; factories build components/electronics/tools/medical/luxury; farms grow food |
| **Mining** | `mining_rig` facilities extract commodities from their body's resources into the local market |
| **Populations** | Consume food/fuel from local market, produce labor commodity, track food_satisfaction → overall_sentiment |
| **Crew** | Per-ship aggregate morale + fatigue. Fatigue rises in transit/work; morale drops when over-fatigued; drives `ShipEconomy.efficiency`. Ships below 35 morale take shore leave. |
| **Factions** | 5% tax on every owned facility's credits flows into faction treasury every 50 base-ticks |
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

- **Admin HTTP endpoints** — god-mode ship/facility CRUD, save-as, market
  supply delta. The Elixir sim had these; the Godot client still tries to
  call them (404s gracefully). One evening per endpoint class to port.
- **Windows native build** — cross-compile is set up (`rustup target add
  x86_64-pc-windows-gnu`) but we haven't validated on a Windows box. The
  binary is single-file with bundled SQLite; should Just Work.
- **Rayon parallelism** — dependency is in, never called. Unnecessary until
  10k+ agents. Architecture is designed for it (no shared mutable state
  between ships in a phase).
- **Facility / population persistence** — only ships, markets, factions,
  and the tick counter flush today. Other agents fall back to seed state
  on restart. Sim re-converges within seconds.
- **Per-faction contract posting** — factions just collect tax; they don't
  spend yet. Would give us faction-driven economic pressure.
- **Contract reputation gating** — contracts are open to all ships; a
  faction-reputation filter would add texture.

## License

Same as the parent spaceproject repo.
