## New stuff

| `do_crew_mission` | Longer themed mission posted by a facility — security detail, maintenance, harvest help, etc. Grows a crew skill on completion. |

## Crew Missions

Facilities periodically post themed missions that the ship's *whole
crew* (treated as a unit — no per-crew-member agents) takes on. Think
security detail at a station, heavy maintenance at a mining rig,
harvest help at a farm. The ship stays docked for the mission duration,
and on completion collects the payment, faction rep, and a small
skill-growth bump on the mission's required skill. This is distinct
from the existing `:station_job` broke-lifeline work — crew missions
pay much more (800–2000 cr vs 100–250) but take much longer.

### Mission Contract Shape

Crew missions appear on the regular ContractBoard with `contract_type:
"crew_mission"` and extra fields describing the work:

```json
{
  "id": "contract-981",
  "contract_type": "crew_mission",
  "requestor_type": "facility",
  "requestor_id": "facility-earth-station",
  "source_location": "earth-station",
  "destination_location": "earth-station",
  "mission_category": "security_detail",
  "display_name": "Security Detail",
  "required_skill": "combat",
  "duration_ticks": 30,
  "skill_gain": 3,
  "payment": 1500,
  "faction_id": "terran-authority",
  "min_reputation": 20
}
```

### Mission Catalog

Current catalog (tune freely; subject to change):

| Category | Posted By | Duration (base ticks) | Payment | Skill | Gain |
|---|---|---|---|---|---|
| `security_detail` | station | 30 | 1500 | combat | +3 |
| `vip_escort` | station | 20 | 1200 | navigation | +2 |
| `customs_assist` | station | 15 | 800 | trading | +2 |
| `heavy_maintenance` | mining_rig, refinery | 40 | 2000 | engineering | +3 |
| `salvage_operation` | mining_rig | 35 | 1800 | engineering | +2 |
| `production_assist` | factory | 25 | 1400 | engineering | +2 |
| `equipment_calibration` | factory, refinery | 20 | 1100 | engineering | +2 |
| `harvest_help` | farm | 30 | 1200 | general | +1 |
| `safety_audit` | refinery | 25 | 1500 | engineering | +2 |

Duration in the contract is expressed in *base* ticks — the sim scales
by `tick_multiplier` on the ship side. For client-side ETAs, multiply
the contract's `duration_ticks` by `config.tick_multiplier`
(available in `/api/report`) or use the contract's broadcast timestamp
as the reference.

### Crew Skill Growth

Crew skills were static before this phase. Now they grow on mission
completion — the `skills` map on crew state ticks up 1–3 points per
mission, capped at 100. For UI:

- Bar-style crew skill display (0–100 fill) is now meaningfully
  animated — show a delta flash on completion
- Compare `/api/agent/ship-veteran` vs `/api/agent/ship-rookie` to
  showcase progression

### Mission Completion Event

When a ship completes a crew mission, it broadcasts
`:crew_mission_completed` on `simulation:facility:<source_location>`:

```json
{
  "ship_id": "ship-artemis-7",
  "facility_location": "earth-station",
  "category": "security_detail",
  "payment": 1500,
  "tick": 5000
}
```

Useful for:

- Mission-complete notification pops on the facility's station UI
- Faction activity feed ("Terran Authority +1 reputation with
  Artemis-7")
- Highlighting the ship that just finished for a few seconds on the
  map

### Archetype Tip

No new archetype was added for crew missions — existing archetypes
score them via considerations. Expect these archetypes to gravitate
toward crew missions:

- `reliable_trucker` (high loyalty) — matches missions requiring
  trading or general skill
- `cautious_trader` (high safety) — low-risk docked work fits profile
- `courier` (Phase 5) — skill_fit on navigation makes VIP escort a
  natural pull
