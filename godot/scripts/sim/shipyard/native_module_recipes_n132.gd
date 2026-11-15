extends RefCounted
## Exact catalog: frozen native/crates/sim_core/src/economy/module_production.rs.
## No tier-1 recipe. No free module creation: return a proposed stock delta only.
const SHIPYARD_STOCK_TARGET := 2
const RECIPES := {
	"engine_t2": {"inputs": {"metals": 3, "electronics": 2, "tools": 1}, "cost": 8000},
	"engine_t3": {"inputs": {"metals": 5, "electronics": 4, "tools": 2, "components": 1}, "cost": 22000},
	"cargo_bay_t2": {"inputs": {"metals": 4, "polymers": 2}, "cost": 6000},
	"cargo_bay_t3": {"inputs": {"metals": 7, "polymers": 3}, "cost": 16000},
	"sensors_t2": {"inputs": {"electronics": 2, "components": 2, "tools": 1}, "cost": 7500},
	"sensors_t3": {"inputs": {"electronics": 4, "components": 3, "tools": 2}, "cost": 20000},
	"reactor_t2": {"inputs": {"metals": 4, "electronics": 3, "components": 2}, "cost": 10000},
	"reactor_t3": {"inputs": {"metals": 7, "electronics": 5, "components": 3}, "cost": 28000},
	"comms_t2": {"inputs": {"electronics": 2, "components": 1}, "cost": 5500},
	"comms_t3": {"inputs": {"electronics": 4, "components": 2}, "cost": 14000}
}

static func get_recipe(slug: String) -> Dictionary:
	return RECIPES.get(slug, {}).duplicate(true)

static func inputs_available(slug: String, supply: Dictionary) -> bool:
	if not RECIPES.has(slug):
		return false
	for commodity in RECIPES[slug]["inputs"]:
		if float(supply.get(commodity, 0.0)) < float(RECIPES[slug]["inputs"][commodity]):
			return false
	return true

static func propose_batch(slug: String, supply: Dictionary, module_stock: Dictionary) -> Dictionary:
	## Pure proposed delta; authoritative market/stock commit must be atomic.
	if not RECIPES.has(slug):
		return {"ok": false, "reason": "unknown_module"}
	if int(module_stock.get(slug, 0)) >= SHIPYARD_STOCK_TARGET:
		return {"ok": false, "reason": "target_reached"}
	if not inputs_available(slug, supply):
		return {"ok": false, "reason": "insufficient_inputs"}
	var next_supply := supply.duplicate(true)
	var next_stock := module_stock.duplicate(true)
	for commodity in RECIPES[slug]["inputs"]:
		next_supply[commodity] = maxf(0.0, float(next_supply.get(commodity, 0.0)) - float(RECIPES[slug]["inputs"][commodity]))
	next_stock[slug] = int(next_stock.get(slug, 0)) + 1
	return {"ok": true, "supply": next_supply, "module_stock": next_stock, "installation_cost": RECIPES[slug]["cost"]}
