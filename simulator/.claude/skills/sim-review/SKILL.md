---
name: sim-review
description: Review simulation health using API endpoints and Postgres queries. Use when asked to check on the simulation or diagnose economy issues.
user-invocable: true
---

# Simulation Review

Review the space simulation's health by querying API endpoints and analyzing the results.

## Available Endpoints

```bash
curl -s localhost:4000/api/health           # quick pass/fail check
curl -s localhost:4000/api/ships            # all ship states (JSON)
curl -s localhost:4000/api/markets          # all market states
curl -s localhost:4000/api/agent/AGENT_ID   # single agent by ID
```

## What to Check

### 1. Ship Economy Health
Query `/api/ships` and check:
- **Credits**: any ship at 0? Any ship > 100K (hoarding)?
- **Goals**: are ships idle or actively trading/fulfilling contracts?
- **Location diversity**: are ships spread across locations or clustering?
- **Fuel**: any ship stranded with no fuel?
- **Cargo**: are ships carrying goods or always empty?

### 2. Market Balance
Query `/api/markets` and check:
- **Prices**: any commodity at floor (1.0) or ceiling (500)?
- **Supply**: any commodity at 0 across all markets?
- **Production/consumption**: are recipes producing? Is supply growing or shrinking?
- **Price differentials**: do different locations have meaningfully different prices?

### 3. Facility Health
Check facilities via `/api/agent/facility-*`:
- **Condition**: degrading below 0.5?
- **Credits**: growing or stagnant?
- **Reserves**: fuel/food/tools available?
- **Docked ships**: are facilities getting traffic?

### 4. Contract Board
Check if contracts are being posted and fulfilled — look at ship `active_contract` and `available_contracts` count.

### 5. Faction Dynamics
Check ship `faction_reputation` — is reputation changing? Are faction ships getting faction contracts?

## Thresholds (Flag if True)
- Ship credits < 500 → **broke**
- Ship credits > 100,000 → **hoarding**
- All prices at 1.0 → **price crash**
- Any commodity supply = 0 at all markets → **supply crisis**
- > 6 ships at same location → **clustering**
- All ships idle → **economy dead**
- Facility condition < 0.3 → **failing infrastructure**

## Output

Write a concise summary. If called manually, output directly to the user. If running in a loop, append to `tmp/self-review-notes.md`.

Format:
```
## Review at Tick [N] — [timestamp]
**Status**: OK / ISSUES FOUND
[Summary of economy: ship credits range, active goals, price range, supply status]
[If issues: specific problems with values and likely causes]
```
