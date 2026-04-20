# simulator-rust

A space-economy simulation engine written in Rust. Replaces the Elixir/Phoenix
version for native Windows/Linux performance, targeting 800 agents today and
100k+ long-term. Godot is the sole client.

> **Status**: Phases 1–6 complete, Phase 7 hardening in progress. See
> [`PLAN.md`](./PLAN.md) for session log and remaining work.

## Quick start

```bash
# from simulator-rust/
scripts/verify.sh          # cargo check + test + clippy
scripts/smoke.sh 10        # build, boot sim for 10s, print log + DB counts
scripts/ws-test.sh 6       # launch sim, hit HTTP endpoints, verify API
```

Then with the sim running:

```bash
curl localhost:8080/api/health
curl localhost:8080/api/ships | jq '.data[0]'
curl -X POST localhost:8080/api/sim/pause
curl -X POST localhost:8080/api/sim/resume
```

## Environment variables

| Var | Default | Effect |
|---|---|---|
| `RUST_LOG` | `simulator=info,sim_core=info` | Tracing filter (use `trace` for sqlx query logs) |
| `WORLD_SPEED` | `0.25` | Game-time multiplier. Higher = faster travel. Try `4.0` for demos. |
| `BIND_ADDR` | `127.0.0.1:8080` | HTTP/WS bind address |
| `DATABASE_PATH` | `./sim.db` | SQLite DB path. Ephemeral: use `mktemp` for tests. |
| `DATA_DIR` | `priv/data` | World JSON + migrations root |

## Architecture

- **sim_core**: pure Rust (no async), hecs ECS, all tick logic. Testable without tokio.
- **sim_server**: tokio runtime, axum HTTP+WebSocket, sqlx SQLite. Thin glue.
- **hecs** for entity/component storage. Every agent type is a bundle of small
  components split by access pattern, so tick phases only load what they need.
- **Command buffer** for cross-phase effects. Phases read world state, write
  `SimCommand` intents, and never mutate mid-phase → deterministic replay.
- **Tick phase order**: bodies → ships → apply-supply-commands → facilities →
  populations → markets → snapshot-write.

## Agents (at current seed)

| Type | Count | Notes |
|---|---|---|
| Ships | 223 | 5 classes (courier/freighter/hauler/tanker/miner), 6 factions |
| Facilities | 56 | Mining rigs, refineries, factories, stations, farms |
| Markets | 23 | One per station/outpost, 13 commodities |
| Populations | 19 | Per-facility demographic blocs (workers, merchants, scientists) |
| Factions | 6 | Terran, Mars, Belt, Frontier Ventures, Crucible, Doughtys |
| Celestial bodies | 23 | Planets, moons, belts across Sol / Alpha Centauri / Tau Ceti |
| Travel routes | 68 | Bidirectional pairs |

## Godot client integration (pending)

The WS server is ready. The Godot client's `network_manager.gd` needs updating
to speak the new plain-JSON protocol (see
[`crates/sim_server/src/ws/protocol.rs`](crates/sim_server/src/ws/protocol.rs))
instead of the old Phoenix channel envelope. Simulator prints
`sim:ready ws=ws://...` to stdout so Godot can wait before connecting.

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

## License

Same as the parent spaceproject repo.
