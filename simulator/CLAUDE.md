# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent-driven space simulation engine on Elixir/OTP + Phoenix 1.8. Three star systems (Sol, Alpha Centauri, Tau Ceti) with 190 ships, 22 facilities, 15 markets, 19 populations — ~250 autonomous GenServer agents running a self-sustaining economy with supply chains, contracts, factions, and reputation. 244 tests.

World data is JSON-driven: `priv/data/worlds/*.json` → SQLite via `mix seed` → agents boot from DB.

## Commands

- **Dev server:** `iex -S mix phx.server` or `make dev` (localhost:4000)
- **Setup:** `mix setup` (deps + DB create/migrate/seed + assets — no Docker needed)
- **Reset DB + seed:** `make reset` (deletes `priv/sim_dev.db`, recreates, migrates, seeds from JSON)
- **Seed only:** `mix run priv/repo/seeds.exs` (idempotent upsert)
- **Tests:** `mix test` (348 tests)
- **Single test:** `mix test test/path/to_test.exs`
- **Pre-commit:** `mix precommit` (compile --warnings-as-errors, format, test)
- **Lint:** `mix credo`
- **Docs:** `mix docs`

Always run `mix precommit` before finalizing changes.

## Release Builds

- **Build:** `make release` → `_build/prod/rel/simulator/` (~40 MB, ERTS bundled)
- **Run:** `make release.run` (binds 127.0.0.1:4000 by default)
- **Stop:** `make release.stop` or SIGTERM

First boot auto-runs migrations and seeds from the bundled JSON. Set `DATABASE_PATH` to point at a stable user-data dir (desktop bundle scenario); otherwise the DB lands under `$TMPDIR/simulator/sim.db` by default. Secret key base auto-generates and persists next to the DB on first run — no env vars required.

## Self-Review

Use the `/sim-review` skill or curl the API directly:

```bash
curl -s localhost:4000/api/health        # quick pass/fail
curl -s localhost:4000/api/report | jq . # full snapshot (tick, metrics, ships, markets)
curl -s localhost:4000/api/ships | jq .  # all ship states
curl -s localhost:4000/api/markets | jq . # all market prices/supply
curl -s localhost:4000/api/agent/ship-artemis-7 | jq .  # single agent
```

## Architecture

- **Database:** SQLite via `ecto_sqlite3` + Ecto. DB file is `priv/sim_dev.db` (dev) / `priv/sim_test*.db` (test). No external service. WAL mode + single-writer batching via `PersistenceManager` keeps contention to zero.
- **Data pipeline:** JSON files (`priv/data/`) → `Simulator.Seed` → SQLite → `Spawner` → GenServer agents
- **Simulation core:** `lib/simulator/`
  - `agents/` — GenServer agents: ShipAgent, MarketAgent, FacilityAgent, PopAgent
  - `agents/crew_complement.ex` — Aggregate crew stats (not individual agents — saves ~800 processes)
  - `agents/ship_agent/` — Actions (BT-compatible), Goals (utility scoring), Planner (trade routes), Plan/PlanStep
  - `agents/agent.ex` — Common behaviour with Registry registration, tick dispatch, persistence
  - `ai/` — Hybrid decision system:
    - `utility.ex` — Weighted action scoring against personality
    - `behavior_tree.ex` — Sequence/Selector/Condition/Action nodes for tactical execution
    - `considerations.ex` — Pure functions evaluating agent state → 0.0-1.0
    - `personality.ex` — Archetypes (cautious_trader, aggressive_trader, explorer, etc.)
  - `economy/` — Commodities (13, 4 tiers), Recipes (9 transformations), OrderBook, ContractBoard, ContractLifecycle, Reputation
  - `spatial/` — ChunkManager (tick-resolution scaling), Quadtree, Observer, PositionTracker
  - `world/` — SystemAgent (orbital mechanics), Body, Travel, Registry (DB-loaded lookups)
  - `simulation/` — Config (ship classes, tick interval), Spawner (boots from DB), PriorityManager
  - `seed.ex` — JSON → SQLite upsert logic
  - `schemas/` — 13 Ecto schemas (factions, star_systems, ships, facilities, markets, etc.)
- **Web layer:** `lib/simulator_web/`
  - Dashboard: `live/dashboard_live.ex` — pan/zoom star map, chunk overlay, markets by tier, fleet, facilities, agent inspector
  - Channels: `channels/simulation_channel.ex` — WebSocket event relay
  - API: `controllers/api_controller.ex` — JSON endpoints for health, report, agents, sim control

## Key Systems

- **Utility AI + Behavior Trees:** Ships select goals (trade_run, fulfill_contract, refuel, sell_cargo, explore) via personality-weighted scoring, then execute via BT sequences
- **Contracts + Escrow:** Facilities/populations auto-post delivery contracts. Ships accept and fulfill for escrowed payment. Prices escalate for unfilled contracts.
- **Factions + Reputation:** 5 factions own facilities/ships. Reputation (0-100) controls contract access. Contracts age-open from faction-only → allied → public.
- **Supply Chain:** 13 commodities across 4 tiers (raw→refined→manufactured→consumer). Facilities execute recipes (ore+fuel→metals). Mining rigs extract from body resources.
- **Spatial Chunks:** Unified coordinate space with tick-resolution gradient from observers. ETS-backed O(1) tick gating.
- **Ship Lifecycle:** Ships that go broke 3 times get recycled with new personality + location. Natural selection for the economy.

## Adding Content

To add a new star system, create `priv/data/worlds/new_system.json` and run `mix seed`. No code changes needed. See existing JSON files for structure.

## Guidelines

See `AGENTS.md` for Phoenix 1.8, LiveView, Ecto, HEEx conventions. Key points:

- Always run `mix precommit` before finalizing changes
- Use `Req` for HTTP requests — no httpoison, tesla, or httpc
- Ecto timestamps use `:utc_datetime`
- Max line length: 120 chars (credo)
- Every module gets `@moduledoc`, every public function gets `@doc`
- Lean on ExDoc — `mix docs` generates full API docs
- Price memory uses stamped format: `%{commodity => %{price: float, tick: int}}`
- Agent state uses a JSON-serialized `state` column (Ecto `:map`) for volatile data + indexed relational columns
