extends RefCounted
## Frozen Rust agents/faction/relief.rs: transfers EXISTING credits, never mints.
const INTERVAL_BASE := 25
const MAX_SPEND := 12000
const HOUSEHOLD_MINIMUM := 300
const HOUSEHOLD_TARGET := 120
const COLONY_EMERGENCY_TARGET := 4000
const MARKET_MINIMUM := 600
const MARKET_TARGET := 3000
const PRODUCER_MINIMUM := 20
const PRODUCER_TARGET := 160

static func due(tick: int, multiplier: int) -> bool:
	var cadence := INTERVAL_BASE * max(multiplier, 0)
	return tick > 0 and cadence > 0 and tick % cadence == 0

## Input dictionaries are deep-copied. Keys: factions by id {treasury},
## households [{id,faction_id,location,wealth,food_satisfaction}],
## markets [{id,faction_id,location,credits,food,water}],
## producers [{id,faction_id,location,type,credits}].
## faction_floor is sourced from faction.rs, not an invented relief constant.
static func apply(snapshot: Dictionary, tick: int, multiplier: int, faction_floor: int) -> Dictionary:
	var state: Dictionary = snapshot.duplicate(true)
	var events: Array = []
	if not due(tick, multiplier):
		return {"state": state, "events": events}
	var factions: Dictionary = state.get("factions", {})
	var households: Array = state.get("households", [])
	var markets: Array = state.get("markets", [])
	var producers: Array = state.get("producers", [])
	var requests: Array = []
	var market_by_location: Dictionary = {}
	for i in range(households.size()):
		var h: Dictionary = households[i]
		var faction := str(h.get("faction_id", ""))
		var wealth := int(h.get("wealth", -1))
		if not factions.has(faction) or wealth < 0 or wealth >= HOUSEHOLD_MINIMUM:
			continue
		var starving := int(h.get("food_satisfaction", 100)) < 40
		var target := COLONY_EMERGENCY_TARGET if starving and str(h.get("location", "")).ends_with("-colony") else HOUSEHOLD_TARGET
		requests.append(_request(0 if starving else 1, faction, str(h.get("location", "")), str(h.get("id", "")), "households", i, target - wealth))
	for i in range(markets.size()):
		var m: Dictionary = markets[i]
		var faction := str(m.get("faction_id", ""))
		var loc := str(m.get("location", ""))
		market_by_location[loc] = m
		var cash := int(m.get("credits", -1))
		if factions.has(faction) and cash >= 0 and cash < MARKET_MINIMUM:
			var emergency := float(m.get("food", 0)) < 20.0 or float(m.get("water", 0)) < 20.0
			requests.append(_request(2 if emergency else 3, faction, loc, str(m.get("id", "")), "markets", i, MARKET_TARGET - cash))
	for i in range(producers.size()):
		var p: Dictionary = producers[i]
		var faction := str(p.get("faction_id", ""))
		var loc := str(p.get("location", ""))
		var cash := int(p.get("credits", -1))
		if not factions.has(faction) or cash < 0 or cash >= PRODUCER_MINIMUM or not market_by_location.has(loc):
			continue
		var m: Dictionary = market_by_location[loc]
		if str(m.get("faction_id", "")) != faction:
			continue
		var essential := (str(p.get("type", "")) == "farm" and float(m.get("food", 0)) < 20.0) or (str(p.get("type", "")) == "refinery" and float(m.get("water", 0)) < 20.0)
		if essential:
			requests.append(_request(4, faction, loc, str(p.get("id", "")), "producers", i, PRODUCER_TARGET - cash))
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for key in ["priority", "faction", "location", "id"]:
			if a[key] != b[key]:
				return a[key] < b[key]
		return false
	)
	var spent: Dictionary = {}
	for req in requests:
		var faction: String = req["faction"]
		var wallet: Dictionary = factions[faction]
		var available: int = max(0, int(wallet.get("treasury", 0)) - faction_floor)
		var allowance: int = max(0, MAX_SPEND - int(spent.get(faction, 0)))
		var amount: int = mini(int(req["needed"]), mini(available, allowance))
		if amount <= 0:
			continue
		var group: Array = state[req["group"]]
		var recipient: Dictionary = group[req["index"]]
		var key := "wealth" if req["group"] == "households" else "credits"
		var balance: int = int(recipient.get(key, 0))
		if balance > 9223372036854775807 - amount:
			continue
		wallet["treasury"] = int(wallet["treasury"]) - amount
		recipient[key] = balance + amount
		spent[faction] = int(spent.get(faction, 0)) + amount
		events.append({"kind": "faction_relief_transfer", "tick": tick, "faction_id": faction, "recipient_id": req["id"], "location": req["location"], "recipient_kind": "household" if req["group"] == "households" else "facility", "amount": amount})
	return {"state": state, "events": events}

static func _request(priority: int, faction: String, location: String, id: String, group: String, index: int, needed: int) -> Dictionary:
	return {"priority": priority, "faction": faction, "location": location, "id": id, "group": group, "index": index, "needed": needed}
