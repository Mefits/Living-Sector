extends RefCounted
## N110: strategy/progression.rs station tier domain + physical upgrade preflight.
## Pure staged changes: world owner applies atomic debits and receipts externally.
const TIERS := ["t1", "t2", "t3"]
const CAPACITIES := {"t1": 4, "t2": 5, "t3": 6}
const GATES := {"t2": "structuretech2", "t3": "structuretech3"}
const BILLS := {"t1": {}, "t2": {"metals": 240, "components": 100, "alloys": 40},
	"t3": {"alloys": 160, "electronics": 80, "quantum_cores": 36}}
const WORK := {"t1": 0, "t2": 150, "t3": 250}
const CAMPAIGN := [
	{"milestone":"alloytech2","must_follow":["automation"],"tier":"t2","native":false},
	{"milestone":"drilltech2","must_follow":["alloytech2"],"tier":"t2","native":false},
	{"milestone":"rare_ore","must_follow":["drilltech2","survey2"],"tier":"t2","native":false},
	{"milestone":"alloys","must_follow":["rare_ore","alloyplant2"],"tier":"t2","native":false},
	{"milestone":"station2","must_follow":["alloys","structuretech2"],"tier":"t2","native":false},
	{"milestone":"crystal_ore","must_follow":["drill3","survey3"],"tier":"t3","native":false},
	{"milestone":"quantum_cores","must_follow":["crystal_ore","qfab3"],"tier":"t3","native":false},
	{"milestone":"station3","must_follow":["quantum_cores","structuretech3"],"tier":"t3","native":false}
]

static func default_state() -> Dictionary:
	return {"tier":"t1", "target":"", "materials_installed":false,
		"labor_completed":0, "last_labor_tick":-1, "last_receipt_tick":-1, "blocked_reason":""}

static func next_tier(tier: String) -> String:
	var idx := TIERS.find(tier)
	return TIERS[idx + 1] if idx >= 0 and idx < 2 else ""

static func available_slot(tier: String, built: int, in_progress: int) -> Dictionary:
	if not CAPACITIES.has(tier) or built < 0 or in_progress < 0:
		return {"status":"invalid_counts"}
	var cap: int = CAPACITIES[tier]
	if built > cap or in_progress > cap or built + in_progress >= cap:
		return {"status":"full","capacity":cap}
	return {"status":"available","remaining":cap - built - in_progress}

static func research_ready(current: String, target: String, completed: Array) -> bool:
	return next_tier(current) == target and completed.has(GATES.get(target, ""))

static func material_preflight(state: Dictionary, target: String, supply: Dictionary, prices: Dictionary, treasury: int, owner_credits: int) -> Dictionary:
	if next_tier(str(state.get("tier", "t1"))) != target:
		return {"error":"invalid_tier_transition"}
	if bool(state.get("materials_installed", false)):
		return {"error":"materials_already_installed"}
	var bill: Dictionary = BILLS[target]
	var total := 0
	for commodity in bill:
		var have := float(supply.get(commodity, 0.0))
		if not is_finite(have) or have < float(bill[commodity]):
			return {"error":"awaiting_" + commodity}
		var price := float(prices.get(commodity, -1.0))
		if not is_finite(price) or price < 0.0 or price > 10000.0:
			return {"error":"invalid_price"}
		var charge := int(ceil(price * float(bill[commodity])))
		if charge < 0 or charge > 9223372036854775807 - total:
			return {"error":"price_overflow"}
		total += charge
	if treasury < total or treasury - total < 10000:
		return {"error":"insufficient_project_budget"}
	if owner_credits > 9223372036854775807 - total:
		return {"error":"owner_credit_overflow"}
	var next_supply := supply.duplicate(true)
	for commodity in bill:
		next_supply[commodity] = float(next_supply[commodity]) - float(bill[commodity])
	var next := state.duplicate(true)
	next["target"] = target
	next["materials_installed"] = true
	next["blocked_reason"] = ""
	return {"state":next,"supply":next_supply,"treasury":treasury-total,
		"owner_credits":owner_credits+total,"credits_transferred":total}
	# Caller commits ALL fields atomically, and stamps last_receipt_tick.

static func labor_preflight(state: Dictionary, tick: int, treasury: int, worker_wallet: int, available_workers: int) -> Dictionary:
	var tier := str(state.get("tier", "t1"))
	var target := next_tier(tier)
	if target == "" or not bool(state.get("materials_installed", false)) or str(state.get("target", "")) != target:
		return {"error":"materials_not_installed"}
	if int(state.get("last_labor_tick", -1)) >= tick:
		return {"error":"shift_already_processed"}
	if treasury < 10010:
		return {"error":"insufficient_payroll_budget"}
	if available_workers < 10:
		return {"error":"insufficient_workers"}
	if worker_wallet > 9223372036854775807 - 10:
		return {"error":"worker_wallet_overflow"}
	var next := state.duplicate(true)
	next["labor_completed"] = min(2147483647, int(next.get("labor_completed",0)) + 10)
	next["last_labor_tick"] = tick
	next["last_receipt_tick"] = tick
	next["blocked_reason"] = ""
	var done := int(next["labor_completed"]) >= int(WORK[target])
	if done:
		next["tier"] = target
		next["target"] = ""
		next["materials_installed"] = false
		next["labor_completed"] = 0
	return {"state":next,"treasury":treasury-10,"worker_wallet":worker_wallet+10,
		"wages_paid":10,"upgraded":done}
	# Real worker occupancy, owner, crisis, cadence and tech gates are caller checks.

static func due(tick: int, multiplier: int) -> bool:
	return tick > 0 and tick % (60 * max(1,multiplier)) == 0
