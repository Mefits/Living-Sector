# Space Simulation Engine

An agent-driven space simulation where ships, facilities, populations, and markets are autonomous BEAM processes making decisions, trading, and shaping a dynamic economy across multiple star systems. Built on Elixir/OTP + Phoenix 1.8.

Think Dwarf Fortress meets Eve Online, set in space, built on the BEAM.

## Quick Start

```bash
# Start Postgres
docker compose up -d

# Install deps, create DB, migrate, seed world data, build assets
mix setup

# Start the simulation
iex -S mix phx.server
```

Or use the Makefile:
```bash
make setup    # docker + deps + DB + assets
make dev      # start dev server with IEx shell
make reset    # drop DB, recreate, migrate, seed from JSON
make test     # run all tests
make check    # full pre-commit (compile strict + format + test)
```

Visit:
- **Dashboard:** [localhost:4000/dashboard](http://localhost:4000/dashboard) — pan/zoom star map, markets, fleet, agent inspector
- **API:** [localhost:4000/api/health](http://localhost:4000/api/health) — JSON health check
- **LiveDashboard:** [localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard) — BEAM observability

## What's Running

The simulation boots from JSON seed files (`priv/data/worlds/*.json`) with:

- **3 star systems** — Sol (8 planets), Alpha Centauri (3 planets), Tau Ceti (4 planets, mining frontier)
- **22 facilities** — stations, refineries, factories, farms, mining rigs
- **15 markets** — trading 13 commodities across 4 tiers (raw → refined → manufactured → consumer)
- **190 ships** — couriers, freighters, haulers, tankers with personality-driven AI
- **19 populations** — demographic blocs consuming goods, producing labor, posting contracts
- **5 factions** — Terran Authority, Mars Syndicate, Belt Coalition, Frontier Ventures, Crucible Mining Corp

Ships use hybrid Utility AI + Behavior Trees to select goals and execute multi-step plans. Facilities run production recipes (ore + fuel → metals). Contracts emerge from agent needs — desperate populations bid higher for food deliveries. Factions control contract access via reputation.

~250 agents running at 1.3ms/tick on a single BEAM node.

## API Endpoints

```bash
curl localhost:4000/api/health          # health check
curl localhost:4000/api/report          # full simulation snapshot
curl localhost:4000/api/markets         # all market states
curl localhost:4000/api/ships           # all ship states
curl localhost:4000/api/agent/ship-artemis-7  # single agent
curl -X POST localhost:4000/api/sim/pause     # pause
curl -X POST localhost:4000/api/sim/resume    # resume
```

## Adding Content

World data is JSON-driven. To add a new star system:

1. Create `priv/data/worlds/barnards_star.json` (see existing files for structure)
2. Run `mix seed` (idempotent upsert — safe to re-run)
3. Restart the server

No code changes needed. Factions go in `priv/data/factions.json`.

## Development

```bash
mix test              # 244 tests
mix precommit         # compile strict + format + test
mix credo             # linting
mix docs              # generate ExDoc documentation
mix seed              # reload world data from JSON
```

## Architecture

All modules have `@moduledoc` and `@doc` — run `mix docs` for full API documentation.

```
JSON Seed Files (priv/data/)
  ↓ mix seed (upsert)
Postgres (source of truth)
  ↓ Spawner (boot)
GenServer Agents
  ├── SystemAgent (3)    — orbital mechanics, travel times
  ├── FacilityAgent (22) — docking, recipes, reserves, contracts
  ├── MarketAgent (15)   — order book, price engine, supply/demand
  ├── ShipAgent (190)    — AI goals, behavior trees, cargo, contracts
  └── PopAgent (19)      — consumption, sentiment, labor, contracts

Decision System
  ├── Utility AI         — personality-weighted goal scoring
  ├── Behavior Trees     — tactical execution (sequence/selector/action)
  └── Considerations     — pure functions evaluating state → 0.0-1.0

Economy
  ├── 13 Commodities     — 4 tiers (raw/refined/manufactured/consumer)
  ├── 9 Recipes          — ore+fuel→metals, water→food, etc.
  ├── ContractBoard      — ETS-indexed contract discovery
  ├── Reputation         — per-faction, drives contract access
  └── Price Engine       — coverage-based (supply/demand ratio → slow drift)

Spatial
  ├── ChunkManager       — tick-resolution gradient from observers
  ├── Quadtree           — spatial indexing for proximity queries
  └── WorldRegistry      — DB-loaded system/location/route lookups

PubSub Event Bus → LiveView Dashboard (browser)
                 → Phoenix Channels (WebSocket / Godot)
                 → JSON API (curl / tools)
```

## Scale

Tested at 1300 agents (before crew complement optimization) at 4.1ms/tick.
Current 250 agents at 1.3ms/tick with 99.87% tick budget remaining.
Architecture supports 10,000+ agents with chunk-based tick resolution scaling.
