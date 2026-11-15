extends RefCounted
## Frozen Rust: sim_core/src/agents/faction.rs::run_tax_cycle and run_bailout_cycle.
## Pure state-in/state-out; caller owns exclusive ledger commit.
const TAX_INTERVAL_BASE := 200
const TAX_RATE := 0.025
const TAX_BUFFER := 1000

static func due(tick: int, multiplier: int) -> bool:
	return multiplier > 0 and tick >= 0 and tick % (TAX_INTERVAL_BASE * multiplier) == 0

static func tax_cycle(facilities: Dictionary, factions: Dictionary) -> Dictionary:
	var next_fac := facilities.duplicate(true)
	var next_factions := factions.duplicate(true)
	var transfers: Array = []
	var ids := next_fac.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = next_fac[id]
		var faction_id := str(f.get("faction_id", ""))
		if faction_id.is_empty() or not next_factions.has(faction_id):
			continue
		var balance := int(f.get("credits", 0))
		if balance <= TAX_BUFFER:
			continue
		var tax := int(floor(float(balance - TAX_BUFFER) * TAX_RATE))
		if tax <= 0:
			continue
		var treasury := int(next_factions[faction_id].get("treasury", 0))
		if treasury > 9223372036854775807 - tax:
			return {"ok": false, "reason": "treasury_overflow"}
		f["credits"] = balance - tax
		f["dirty"] = true
		next_fac[id] = f
		var faction: Dictionary = next_factions[faction_id]
		faction["treasury"] = treasury + tax
		faction["dirty"] = true
		next_factions[faction_id] = faction
		transfers.append({"from": id, "to": faction_id, "amount": tax})
	return {"ok": true, "facilities": next_fac, "factions": next_factions, "transfers": transfers}

static func bailout_cycle(facilities: Dictionary, factions: Dictionary, floor_credits: int, target_credits: int, treasury_floor: int, dock_type: String) -> Dictionary:
	var next_fac := facilities.duplicate(true)
	var next_factions := factions.duplicate(true)
	var transfers: Array = []
	var ids := next_fac.keys()
	ids.sort()
	for id in ids:
		var fac: Dictionary = next_fac[id]
		var owner := str(fac.get("faction_id", ""))
		if owner.is_empty() or not next_factions.has(owner) or str(fac.get("facility_type", "")) == dock_type:
			continue
		var credits := int(fac.get("credits", 0))
		if credits >= floor_credits:
			continue
		var faction: Dictionary = next_factions[owner]
		var available := maxi(0, int(faction.get("treasury", 0)) - treasury_floor)
		var amount := mini(maxi(0, target_credits - credits), available)
		if amount <= 0:
			continue
		fac["credits"] = credits + amount
		fac["dirty"] = true
		faction["treasury"] = int(faction["treasury"]) - amount
		faction["dirty"] = true
		next_fac[id] = fac
		next_factions[owner] = faction
		transfers.append({"from": owner, "to": id, "amount": amount})
	return {"ok": true, "facilities": next_fac, "factions": next_factions, "transfers": transfers}
