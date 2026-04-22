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

## Endpoints cheat sheet

```bash
# Overview
curl -s localhost:8080/api/health           # tick, running, world_speed, perf (p50/p99 µs, LOD dist), agent_count
curl -s localhost:8080/api/report           # rolled-up snapshot (tick + metrics + sample of each kind)

# Agents (full snapshots — pipe through jq)
curl -s localhost:8080/api/ships
curl -s localhost:8080/api/facilities
curl -s localhost:8080/api/markets
curl -s localhost:8080/api/populations
curl -s localhost:8080/api/factions
curl -s localhost:8080/api/positions        # every entity's world coord (ship/body/facility)
curl -s localhost:8080/api/contracts
curl -s localhost:8080/api/observers

# Single agent by id
curl -s localhost:8080/api/agent/ship-artemis-7

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
- `tick_compute_p99_us` over ~20ms is a red flag (should be low single-digit ms at 800 agents).

### 1. Ship economy
Query `/api/ships` and look for:
- **Credits spread**: min/median/max. Anyone at < 500 ("broke") or > 100k ("hoarding").
- **Goals**: what's the distribution? Healthy sim shows a mix of `trade_run`, `fulfill_delivery`, `rest_crew`, `refuel`, `sell_cargo`. All-`idle` or all-`in_transit` is suspicious.
- **Transit vs docked vs stuck**: "stuck" = has a `location` but no `docked`, no `transit`, and `idle_ticks` rising. A few ticks of idle is normal (replanning), >50 is bad.
- **Fuel**: any ship at 0? Usually means stranded (no facility at current location has fuel, or ship has no credits to refuel).
- **Cargo vs capacity**: haulers/freighters consistently empty means the contract/trade-run side isn't feeding them work.
- **Strikes**: `broke_strikes >= 2` or `hoard_strikes >= 2` means the lifecycle cycle is about to recycle the ship.

### 2. Positional sanity (regression tests — we've had bugs here)
- **Ships must be near their system's universe_offset** — Sol ~(0,0), AC ~(20,5), TC ~(40,-10). If all ships cluster at (0,0), the seed/loader isn't applying offsets. (We fixed this, so this is a regression test.)
- **Zero "direct" cross-system single-leg transits** — a ship with `transit.from` in one system and `transit.to` in another means the pathfinder fell back to direct Travel. Should always go through a gate. Enumerate `from/to` pairs against the known system→locations mapping.
- **Ships currently in "open space"**: every in-transit ship's position should be in the plausible bubble around its from/to system. A ship in transit between two TC stations should NOT have position near (0,0).

### 3. Market balance
- Prices at floor (~1) or ceiling (500) across all markets = broken coverage math.
- Any commodity with supply=0 at every market = supply crisis (usually a broken recipe chain or no miners producing).
- Meaningful price differentials between markets means trade_run planner has bait to work with.

### 4. Facility health
- `condition < 0.3` → failing infrastructure (will abandon at 0.1 after 200-tick countdown).
- `reserves.fuel / food / water / tools` low? Means ships can't refuel / crew can't eat / self-repair stalls.
- `docked_ships` empty across all facilities for extended periods → nobody's trading.
- Gate facilities: `reserves.fuel` should stay topped (5000 seed); if draining, too many ships refueling at gates.

### 5. Contracts
- `/api/contracts` by status: healthy mix of `posted`, `accepted`, `paid`. Stuck `posted` means nothing can fulfill (rep gating too tight, or no ship in range with capacity).
- By kind: delivery / courier / passenger / subsidy / crew_mission / supply all represented. One kind dominating means something else is broken.

### 6. LOD and perf
- `health.perf.lod` dict shows ship distribution across divisor tiers. With one observer, expect d1 cluster near observer, d5/d10 mid-distance, d50 at edges. All d1 means LOD isn't firing.
- `p50_us` and `p99_us`: at 800 agents, p50 should be ~0.5–2ms, p99 under 10ms. Anything higher = performance regression.

### 7. Events / activity
- `/api/report` carries a slice of recent events. Healthy sim has a steady mix of `ship_docked`, `contract_delivered`, `passengers_arrived`, `market_supply_adjusted`. All-empty or all-one-kind is a red flag.

## Thresholds (flag if true)

| Condition | Meaning |
|---|---|
| `running: false` | Sim paused |
| Same tick value on two samples 2s apart | Sim frozen |
| `p99_us > 20000` | Perf regression |
| Ship credits < 500 | Broke |
| Ship credits > 100k | Hoarding |
| Ship fuel = 0, not docked | Stranded |
| `idle_ticks > 50` on any ship | Stuck |
| `broke_strikes ≥ 2` | About to recycle |
| Cross-system single-leg transit count > 0 | Pathfinder bug |
| Ships cluster at (0,0) regardless of system | Seed/loader bug (regression) |
| Any commodity supply = 0 at all markets | Supply crisis |
| All prices ≤ 1.0 or ≥ 499 | Price engine broken |
| Facility condition < 0.3 | Failing infrastructure |
| > 30% of ships same goal | Monoculture (trade planner rut) |
| Contracts `posted` count rising with no `paid` | Nothing fulfilling |

## How to run a sweep

Use python for the math — `curl | jq` hits its limits quickly with three systems of data.

```bash
python3 <<'EOF'
import json, urllib.request, collections, statistics

def j(path):
    return json.loads(urllib.request.urlopen(f'http://localhost:8080{path}').read())

h = j('/api/health')
print(f"tick={h['tick']} ws={h['world_speed']} running={h['running']} p50={h['perf']['tick_compute_p50_us']}µs p99={h['perf']['tick_compute_p99_us']}µs")
print(f"LOD: {h['perf']['lod']}")

ships = j('/api/ships')['data']
creds = [s['credits'] for s in ships]
print(f"ships={len(ships)} credits min={min(creds)} med={statistics.median(creds):.0f} max={max(creds)}")
print('goals:', dict(collections.Counter(s.get('current_goal','?') for s in ships).most_common(6)))

# State mix
docked = sum(1 for s in ships if s.get('docked'))
in_transit = sum(1 for s in ships if s.get('transit'))
stuck = sum(1 for s in ships if not s.get('docked') and not s.get('transit') and s.get('location'))
print(f"state: docked={docked} in_transit={in_transit} stuck={stuck} broke_strikes_ge2={sum(1 for s in ships if s.get('broke_strikes',0)>=2)}")

# Cross-system single-leg (should always be 0)
sol = {'mercury-station','venus-station','earth-station','luna-base','mars-station','belt-outpost','jupiter-station','saturn-station','trojan-outpost','hilda-outpost','near-earth-station','kuiper-station','sol-ac-gate','sol-tc-gate'}
ac  = {'haven-station','proxima-outpost','refuge-station','ac-belt-station','outer-rocks-station','ac-sol-gate','ac-tc-gate'}
tc  = {'anvil-depot','forge-smelter','crucible-mine','frostheim-station','deep-ice-station','slag-mine','tc-ac-gate','tc-sol-gate'}
def sys_of(l):
    return 'sol' if l in sol else 'ac' if l in ac else 'tc' if l in tc else '?'
bad = [s for s in ships if s.get('transit') and sys_of(s['transit']['from']) != sys_of(s['transit']['to'])]
print(f"cross-system single-leg transits (MUST be 0): {len(bad)}")

markets = j('/api/markets')['data']
all_prices = [p for m in markets for p in m.get('prices',{}).values()]
print(f"markets={len(markets)} price_range=[{min(all_prices):.1f},{max(all_prices):.1f}]")
# Commodities with 0 supply everywhere
commodities = set(c for m in markets for c in m.get('supply',{}))
dead = [c for c in commodities if all(m.get('supply',{}).get(c,0)==0 for m in markets)]
print(f"supply-zero commodities: {dead or 'none'}")

contracts = j('/api/contracts').get('data',[])
by_status = collections.Counter(c.get('status','?') for c in contracts)
by_kind = collections.Counter(c.get('contract_type','?') for c in contracts)
print(f"contracts={len(contracts)} by_status={dict(by_status)} by_kind={dict(by_kind)}")

fac = j('/api/facilities')['data']
low_cond = [f['id'] for f in fac if f.get('condition',1.0) < 0.3]
print(f"facilities={len(fac)} low_condition={len(low_cond)} {low_cond[:3]}")
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
