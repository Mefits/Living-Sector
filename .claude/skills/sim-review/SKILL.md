---
name: sim-review
description: Review the Rust space-sim's health using its HTTP API. Use when asked to check on the sim, look for anomalies, diagnose economy issues, or when running in a self-review loop.
user-invocable: true
---

# Simulation Review (Rust port)

Check the running sim via its HTTP API on `localhost:8080` and flag anomalies.
Assume the sim is already running — if `curl -s localhost:8080/api/health`
returns nothing, say so and stop (don't auto-start one; that would trample
the user's running instance).

## The two flavours (this matters)

The simulator now ships in two flavours:

1. **`client_bevy` (canonical)** — Bevy + egui app that **embeds `sim_core`
   directly**. Same process, same memory, **no HTTP, no WebSocket, no
   network.** Tick loop runs on Bevy `FixedUpdate`. Inspector + admin
   actions are direct function calls on the `Sim` Resource. Old Godot
   client at `../../client/` is archived as a parity reference and is no
   longer canonical.
2. **`sim_server` (headless)** — the original `simulator` binary with the
   HTTP/WS server on port 8080. Used for CI smokes, scripted external
   tools, and **this skill**.

**Implication for sim-review:** the curl-based checks below ONLY work
against `cargo run --bin simulator`. If the user is running the Bevy
client, there is no HTTP endpoint — they're already inside the inspector
and should look at the egui panels (Ships / Markets / Factions / Pops /
Contracts / Construction / Retired / Events / Perf, plus per-entity
detail panels) instead. If you're in a self-review loop or asked to
"review the sim" with no context: try `curl -s localhost:8080/api/health`
first; if it fails, ask whether the headless binary is up, and stop.

## What's running today (snapshot of the sim's shape)

After Phases 1–20c + Bundles 1–2 + GOAP arc + Bundle-4 tranche:

- **485 agents** total (282 ships + 95 facilities + 27 pops + 60 bodies + 8 factions).
- **6 star systems**: Sol, Alpha Centauri, Tau Ceti (inner) + Vega, Barnard, Lalande (outer).
- **GOAP planner** synthesises every BT (delivery, trade-run, passenger, courier,
  retrofit, crew_mission, rest_crew, plus combined `*_with_retrofit` plans).
  No hand-authored fallbacks left.
- **Adaptive fleet**: ships earn broke/hoard strikes, decommission at 3 strikes,
  respawn replacement 300–600 base ticks later with randomised class/faction/location.
- **Dock queue** FIFO with zombie sweep + broke-head eviction.
- **Construction sites** materialise from chronic-shortage demand.
- **Faction treasuries** sit $5.5k–$10k post-rebalance (10k working-capital
  floor + 5k subsidy floor); seeing them at $2k means bailout-floor regression.
- **Inflation anchor**: 30% of every dock fee is burned to the void (Bundle G).
- **Crisis events**: `market_crisis` / `market_recovered` /
  `facility_starving` / `facility_recovered` fire with hysteresis when
  things spiral or recover (Bundle S).
- **WorldTuning** constants live-loaded from `priv/data/tuning.json` and
  inspectable via `GET /api/admin/tuning`.

## Endpoints cheat sheet

```bash
# Overview
curl -s localhost:8080/api/health           # tick, running, world_speed, perf (p50/p99 µs, LOD dist), agent_count, world_seed
curl -s localhost:8080/api/report           # rolled-up snapshot (tick + metrics + sample of each kind + construction_sites + world_seed)

# Agents (full snapshots — pipe through python/jq)
curl -s localhost:8080/api/ships
curl -s localhost:8080/api/facilities       # includes dock_queue per facility
curl -s localhost:8080/api/markets
curl -s localhost:8080/api/populations      # total_wealth tracks production−consumption (Bundle K)
curl -s localhost:8080/api/factions
curl -s localhost:8080/api/positions        # every entity's world coord (ship/body/facility/site)
curl -s localhost:8080/api/contracts
curl -s localhost:8080/api/observers
curl -s localhost:8080/api/construction_sites   # in-flight sites with progress 0..1.0
curl -s localhost:8080/api/retirements          # historical decommission ledger (newest first)

# Single agent by id
curl -s localhost:8080/api/agent/ship-artemis-7

# Debug (Phase 20a)
curl -s 'localhost:8080/api/debug/agent/ship-artemis-7/trace?limit=40'   # last N ship-originated SimCommands

# Tuning (Bundle Q)
curl -s localhost:8080/api/admin/tuning     # live constants (recipe margin, dock-fee burn, etc.)

# Sim control (won't usually need these for a review)
curl -sX POST localhost:8080/api/sim/pause
curl -sX POST localhost:8080/api/sim/resume
curl -sX POST -H 'content-type: application/json' -d '{"world_speed": 2.5}' localhost:8080/api/sim/speed
curl -sX POST -H 'content-type: application/json' -d '{"ticks": 100}' localhost:8080/api/sim/step
```

## What to check

### 0. Is the sim alive?
- `running: true` in `/api/health`?
- Tick advancing? Sample twice ~2s apart and compare.
- `tick_compute_p99_us` over **50ms** is a red flag at 485 agents post-Bundle-M
  (debug build; release build is lower). Budget is 125ms (8 tps).

### 1. Ship economy
Query `/api/ships` and look for:
- **Credits spread**: ships routinely hit $1M+ in mature runs thanks to
  bounty + comms-bonus accumulation. Old "100k = hoarding" threshold is
  obsolete. The right signal is the *strikes* counter — if `hoard_strikes >= 1`
  the sim itself flagged the ship.
- **Goals**: distribution. With GOAP + utility scoring, expect a healthy mix
  of `trade_run`, `fulfill_delivery`, `rest_crew`, `refuel`, `sell_cargo`,
  `seek_retrofit`, `explore`, `do_crew_mission`, `fulfill_passenger_transport`.
  Trade_run share rises in early ticks (fresh crew, no fatigue) — see "young
  vs mature" note below. **All-`idle` is the real red flag.**
- **Transit vs docked vs in-queue vs stuck**:
  - `docked: true` — at a station.
  - `transit` non-null — moving.
  - In a facility's `dock_queue` — waiting for a slot (find by scanning
    `facilities[*].dock_queue` for the ship id).
  - **Stuck** = has a `location`, no `docked`, no `transit`, not in any
    queue, `idle_ticks > 50`. This shouldn't happen post-zombie-sweep.
- **Fuel**: any ship at 0 with no transit and not docked → stranded.
- **Strikes**: `broke_strikes >= 2` or `hoard_strikes >= 2` → about to retire.
  Count `broke_strikes` across the fleet — a sudden spike is an economy
  early-warning.

### 1b. Adaptive fleet activity
- `/api/retirements` rate per 1000 ticks. Steady 0–3 / 1k ticks is healthy
  churn. Spike = something killing ships en masse (failed economy /
  starving fleet).
- Reasons distribution: `bankruptcy` vs `stagnation` vs `admin`. All-`admin`
  means strike system isn't firing; lots of `bankruptcy` with no
  `stagnation` means the broke side dominates (consider raising income
  somewhere).
- New respawn ships have `idle_ticks=0`, fresh crew, low XP — when you see
  a cluster of fresh ships at one faction's home station, the strike system
  recently kicked.

### 2. Positional sanity (regression tests — we've had bugs here)
- **Ships must be near their system's universe_offset** — Sol ~(0,0), AC ~(20,5), TC ~(40,−10),
  Vega/Barnard/Lalande further out. If all ships cluster at (0,0), the
  seed/loader isn't applying offsets. (Old regression — keep watching.)
- **Zero "direct" cross-system single-leg transits** — a ship with
  `transit.from` in one system and `transit.to` in another means the
  pathfinder fell back to direct Travel. Should always go through a gate.
- **Waiting ships pin to their station** — a ship in a `dock_queue` should
  have its `position` ≈ the primary facility's position at that location.
  If it's drifting elsewhere, the station-pin from `74a31cd` regressed.

### 3. Market balance
- Prices at floor (~1) or ceiling (500) **across all markets** = broken
  coverage math. Local floors/ceilings are fine for individual commodities.
- Any commodity with supply=0 at every market = supply crisis (broken
  recipe chain or no miners producing). Should fire a `market_crisis` event
  via Bundle S — cross-check with the events stream.
- Meaningful price differentials between markets means GOAP's trade_run
  catalog has bait to work with. Flat prices everywhere = converged
  monoculture, expect ships idle.

### 4. Facility health
- `condition < 0.3` → failing infrastructure (will abandon at 0.1 after
  200-tick countdown). Should fire `facility_starving` event.
- `reserves.fuel / food / water / tools` low? Means ships can't refuel /
  crew can't eat / self-repair stalls.
- `docked_ships` empty across all facilities for extended periods →
  nobody's trading.
- Gate facilities: `reserves.fuel` should stay topped (5000 seed); if
  draining, too many ships refueling at gates.
- **Dock queues**: `len(facility.dock_queue) > 1` is fine (FIFO works); a
  facility with `len(dock_queue) > 3 AND len(docked_ships) < capacity` for
  many ticks means the queue is wedged (broke head not evicting properly).
- **Construction sites** at `progress < 0.1` for hundreds of ticks means
  the contract supplying it is unfulfilled — check `/api/contracts` for
  the matching `type=construction`.

### 5. Contracts
- `/api/contracts` by status: healthy mix of `posted`, `accepted`, `paid`.
  Stuck `posted` means nothing can fulfill (rep gating too tight, or no
  ship in range with capacity).
- By kind: `delivery / courier / passenger / subsidy / crew_mission /
  construction` all represented. One kind dominating means something else
  is broken.
- **Auto-renewal counters**: `contract.renewal_count >= 1` is a sign of
  unloved postings. Subsidy contracts get exactly 1 "desperate bounty"
  renewal that resets `min_reputation` to 0 — count subsidies with
  `renewal_count > 0` to gauge how often loyal ships are absent.

### 6. Faction treasuries (post-tuning)
- Healthy range: $5.5k–$10k for active factions (the working-capital floor
  is $10k for bailouts, $5k for subsidy posts).
- All factions pinned at exactly $2k = bailout-floor regression (the
  pre-rebalance state).
- One faction at $0 with `active_subsidies > 0` = drained; tax cycle
  isn't keeping up.

### 7. Population wealth (Bundle K)
- `population.total_wealth` should drift *up* at producer pops (Veritas,
  Yeoman) and *down* at consumer pops (Earth, Mars stations) over time,
  reflecting trade flow. Flat across all pops = the wealth wiring isn't
  firing.

### 8. Crisis events stream (Bundle S)
- `market_crisis` events fire when shortage_ticks > 200; `market_recovered`
  fires after a 50-tick hysteresis under threshold. A live sim with
  none of these for 10k ticks usually means everything is too placid
  (or the events aren't being broadcast — check the `/api/report` events
  array).
- `facility_starving` / `facility_recovered` for condition <0.3 / >0.5.

### 9. LOD and perf
- `health.perf.lod` dict shows ship distribution across divisor tiers. With
  one observer, expect d1 cluster near observer, d5/d10 mid-distance, d50
  at edges. All d1 means LOD isn't firing (no observer attached).
- `p50_us` and `p99_us`: at 485 agents debug build expect p50 ~10–20ms,
  p99 ~30–50ms. Release build is roughly 2-4× faster. Anything sustained
  above 80ms = perf regression (the snapshot throttle from Bundle M
  should keep it well under).

### 10. GOAP planner sanity (post-arc)
- Every ship's `current_bt` should resolve to a planner-derived sequence.
  Sample a ship via `/api/agent/ship-X` and `/api/debug/agent/ship-X/trace`
  — the action chain should look like
  `Travel → Dock → DockDwell → (Refuel|Buy) → Undock → Travel → ...` and
  end in `DeliverCargo` or `SellAll` or `Refit`.
- A ship stuck in the `Idle` action with no goal change for >50 ticks
  means the planner returned `None` and the wrapper fell back to
  Idle-and-replan-next-tick. Expected for genuinely-broke ships, not
  for normal ones.

### 11. Mid-action replan (Bundle 2.2)
- Ships ratcheting between two goals every ~20 ticks indicates replan
  thrashing (ratio threshold should prevent this). Easy proxy: count
  unique `current_goal` values seen for the same ship in a 200-tick
  window via repeated `/api/agent/ship-X` polls.

## Thresholds (flag if true)

| Condition | Meaning |
|---|---|
| `running: false` | Sim paused |
| Same tick value on two samples 2s apart | Sim frozen |
| `p99_us > 80000` (debug build) | Perf regression |
| Ship fuel = 0, not docked, not in queue | Stranded |
| `idle_ticks > 50` on any ship + no queue presence | Stuck (zombie sweep regression) |
| `broke_strikes ≥ 2` on > 5% of fleet | Mass economy collapse incoming |
| Cross-system single-leg transit count > 0 | Pathfinder bug |
| Ships cluster at (0,0) regardless of system | Seed/loader bug (regression) |
| Any commodity supply = 0 at all markets | Supply crisis (cross-check market_crisis event) |
| All prices ≤ 1.0 or ≥ 499 *across all markets* | Price engine broken |
| Facility condition < 0.3 | Failing infrastructure (cross-check facility_starving event) |
| Any faction treasury at exactly $2k | Bailout-floor regression (pre-tuning state) |
| Contracts `posted` count rising with no `paid` | Nothing fulfilling |
| Subsidy `renewal_count > 0` on > 50% of subsidies | Loyal ships not engaging |
| `dock_queue` size > 3 with `docked_ships` < capacity for > 50 ticks | Queue wedged (broke head not evicting) |
| Construction site `progress < 0.1` for > 1000 ticks | Demand-analyzer contract unfulfilled |
| Retirement rate > 5 per 1000 ticks | Adaptive-fleet over-firing |

## Young-sim vs mature-sim

A common false positive: a fresh-DB sim shows ~90%+ `trade_run` share for
the first ~10k ticks because crew are fresh (morale ~70, fatigue ~12),
nobody needs `rest_crew`, and contracts haven't aged enough for rep gates
to fully open. As the sim matures (>50k ticks) `rest_crew` rises to
20–30% naturally as crew fatigue oscillates. Don't flag goal monoculture
on young sims unless the share is *literally* 100% on one goal.

## How to run a sweep

Use python for the math — `curl | jq` hits its limits quickly with six
systems and the new endpoints.

```bash
python3 <<'EOF'
import json, urllib.request, collections, statistics

def j(path):
    return json.loads(urllib.request.urlopen(f'http://localhost:8080{path}').read())

h = j('/api/health')
print(f"tick={h['tick']} ws={h['world_speed']} running={h['running']} "
      f"p50={h['perf']['tick_compute_p50_us']}µs p99={h['perf']['tick_compute_p99_us']}µs "
      f"agents={h['agent_count']}")
print(f"LOD: {h['perf']['lod']}")

ships = j('/api/ships')['data']
creds = [s['credits'] for s in ships]
print(f"ships={len(ships)} credits min={min(creds)} med={statistics.median(creds):.0f} max={max(creds):,}")
print('goals:', dict(collections.Counter(s.get('current_goal','?') for s in ships).most_common(8)))

# State mix
docked = sum(1 for s in ships if s.get('docked'))
in_transit = sum(1 for s in ships if s.get('transit'))
in_queue_ids = set()
fac = j('/api/facilities')['data']
for f in fac:
    for sid in f.get('dock_queue', []):
        in_queue_ids.add(sid)
in_queue = sum(1 for s in ships if s['id'] in in_queue_ids)
stuck = sum(
    1 for s in ships
    if not s.get('docked') and not s.get('transit')
    and s.get('location') and s['id'] not in in_queue_ids
    and s.get('idle_ticks', 0) > 50
)
print(f"state: docked={docked} in_transit={in_transit} in_queue={in_queue} "
      f"stuck={stuck} broke≥2={sum(1 for s in ships if s.get('broke_strikes',0)>=2)} "
      f"hoard≥2={sum(1 for s in ships if s.get('hoard_strikes',0)>=2)}")

# Cross-system single-leg (should always be 0). Locations per system:
sol = {'mercury-station','venus-station','earth-station','luna-base','mars-station',
       'belt-outpost','jupiter-station','saturn-station','trojan-outpost','hilda-outpost',
       'near-earth-station','kuiper-station','sol-ac-gate','sol-tc-gate'}
ac = {'haven-station','proxima-outpost','refuge-station','ac-belt-station',
      'outer-rocks-station','ac-sol-gate','ac-tc-gate'}
tc = {'anvil-depot','forge-smelter','crucible-mine','frostheim-station','deep-ice-station',
      'slag-mine','tc-ac-gate','tc-sol-gate','tc-vega-gate'}
vega = {'orison-factory','orison-refinery','vega-barnard-gate','vega-ice-field-station',
        'vega-lalande-gate','vega-rim-mine','vega-tc-gate','veritas-farm','veritas-station'}
barnard = {'barnard-belt-mine','barnard-deep-mine','barnard-lalande-gate','barnard-vega-gate',
           'outpost-gamma-refinery','yeoman-farm','yeoman-station'}
lalande = {'kinship-farm','kinship-station','lalande-barnard-gate','lalande-belt-mine',
           'lalande-drift-mine','lalande-outer-harvester','lalande-vega-gate'}
def sys_of(l):
    if l in sol: return 'sol'
    if l in ac: return 'ac'
    if l in tc: return 'tc'
    if l in vega: return 'vega'
    if l in barnard: return 'barnard'
    if l in lalande: return 'lalande'
    return '?'
bad = [s for s in ships if s.get('transit') and sys_of(s['transit']['from']) != sys_of(s['transit']['to'])]
print(f"cross-system single-leg transits (MUST be 0): {len(bad)}")

markets = j('/api/markets')['data']
all_prices = [p for m in markets for p in m.get('prices',{}).values()]
print(f"markets={len(markets)} price_range=[{min(all_prices):.1f},{max(all_prices):.1f}]")
commodities = set(c for m in markets for c in m.get('supply',{}))
dead = [c for c in commodities if all(m.get('supply',{}).get(c,0)==0 for m in markets)]
print(f"supply-zero commodities: {dead or 'none'}")

contracts = j('/api/contracts').get('data',[])
by_status = collections.Counter(c.get('status','?') for c in contracts)
by_kind = collections.Counter(c.get('contract_type','?') for c in contracts)
print(f"contracts={len(contracts)} by_status={dict(by_status)} by_kind={dict(by_kind)}")
renewed = [c for c in contracts if c.get('renewal_count',0) > 0]
print(f"  contracts with renewal_count>0: {len(renewed)}")

low_cond = [f['id'] for f in fac if f.get('condition',1.0) < 0.3]
queued = [f for f in fac if f.get('dock_queue')]
wedged = [f for f in queued if len(f['dock_queue']) > 3
          and len(f.get('docked_ships', [])) < f.get('docking_capacity', 0)]
print(f"facilities={len(fac)} low_condition={len(low_cond)} {low_cond[:3]}")
print(f"  with dock_queue={len(queued)} wedged(>3+free_cap)={len(wedged)}")

factions = j('/api/factions')['data']
treasuries = [(f['id'], f['treasury']) for f in factions]
floor_pin = [f for f in factions if f['treasury'] == 2000]
print(f"factions: " + " ".join(f"{i}:{t}" for i,t in treasuries))
if floor_pin:
    print(f"  WARN: {len(floor_pin)} factions at exact $2k (bailout-floor regression?)")

# Construction sites
sites = j('/api/construction_sites').get('data', [])
stale = [s for s in sites if s.get('progress', 0) < 0.1]
print(f"construction_sites={len(sites)} stale_under_0.1_progress={len(stale)}")

# Retirements rate (rough — needs two samples to compute /1000 ticks)
rets = j('/api/retirements').get('data', [])
recent = [r for r in rets if r.get('retired_at_tick', 0) > h['tick'] - 1000]
reasons = collections.Counter(r.get('reason','?') for r in recent)
print(f"retirements_last_1000_ticks={len(recent)} reasons={dict(reasons)}")
EOF
```

## Output format

If called manually, respond directly to the user with findings. If called in
a `/loop` context, append to `tmp/self-review-notes.md` with timestamp and
tick.

```
## Review at tick [N] — [ISO timestamp]
**Status**: OK | ISSUES FOUND
- [one-line summary per problem, with value + threshold]
- [likely cause if identifiable]
- [suggested next check or file to inspect]
```

Keep findings terse — the user is watching a live sim and doesn't want a wall of text.
For a deep-dive on a specific ship, drop the full
`/api/debug/agent/<id>/trace` output into the report; for facility issues,
point at the relevant `/api/agent/facility-<id>` snapshot.
