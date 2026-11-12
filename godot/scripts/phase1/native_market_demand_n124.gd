extends RefCounted
## Frozen Rust: agents/market.rs::tick_one_market, demand/shortage/order cleanup.
## Pricing itself belongs to existing N68; this does not create anonymous trades.
const DEMAND_WINDOW_BASE := 100
const DEMAND_WARMUP_BASE := 50
const SHORTAGE_SUPPLY_RATIO := 0.1
const SHORTAGE_MIN_FLOOR := 10.0
const MARKET_CRISIS_SHORTAGE_TICKS := 200
const MARKET_CRISIS_RECOVERY_TICKS := 50

## market: {seed_demand, consumption_window, demand, supply, prices,
## shortage_ticks, crisis_notified, spawned_at_tick, pending_buys, pending_sells,
## order_expiry_ticks}. Returns new state and crisis events.
static func advance(market: Dictionary, tick: int, tick_multiplier: int) -> Dictionary:
	var next := market.duplicate(true)
	var mult := maxi(tick_multiplier, 1)
	var spawn_tick := int(next.get("spawned_at_tick", -1))
	if spawn_tick < 0:
		spawn_tick = tick
		next["spawned_at_tick"] = tick
	var seed: Dictionary = next.get("seed_demand", {})
	if seed.is_empty():
		seed = next.get("demand", {}).duplicate(true)
		next["seed_demand"] = seed
	var windows: Dictionary = next.get("consumption_window", {})
	var observed: Dictionary = {}
	var cutoff := maxi(0, tick - DEMAND_WINDOW_BASE * mult)
	for commodity in windows.keys():
		var kept: Array = []
		var sum_qty := 0.0
		for entry in windows[commodity]:
			if not entry is Dictionary or int(entry.get("tick", -1)) < cutoff:
				continue
			kept.append(entry)
			sum_qty += float(entry.get("qty", 0.0))
		windows[commodity] = kept
		if sum_qty > 0.0:
			observed[commodity] = sum_qty
	next["consumption_window"] = windows
	var demand: Dictionary = {}
	var all_commodities: Dictionary = {}
	for commodity in seed.keys():
		all_commodities[commodity] = true
	for commodity in observed.keys():
		all_commodities[commodity] = true
	var warm := tick - spawn_tick < DEMAND_WARMUP_BASE * mult
	for commodity in all_commodities.keys():
		var obs := float(observed.get(commodity, 0.0))
		var floor_value := float(seed.get(commodity, 0.0))
		demand[commodity] = maxf(obs, floor_value) if warm else (obs if obs > 0.0 else floor_value)
	next["demand"] = demand
	var shortage: Dictionary = next.get("shortage_ticks", {})
	var notified: Dictionary = next.get("crisis_notified", {})
	var events: Array = []
	if tick % mult == 0:
		var prices: Dictionary = next.get("prices", {})
		var supply: Dictionary = next.get("supply", {})
		for commodity in prices.keys():
			var need := float(demand.get(commodity, 0.0))
			var available := float(supply.get(commodity, 0.0))
			var threshold := maxf(need * SHORTAGE_SUPPLY_RATIO, SHORTAGE_MIN_FLOOR)
			var consecutive := int(shortage.get(commodity, 0))
			consecutive = consecutive + 1 if available < threshold and need > 0.0 else 0
			shortage[commodity] = consecutive
			if consecutive >= MARKET_CRISIS_SHORTAGE_TICKS and not bool(notified.get(commodity, false)):
				notified[commodity] = true
				events.append({"kind": "market_crisis", "commodity": commodity, "tick": tick})
			elif consecutive <= MARKET_CRISIS_RECOVERY_TICKS:
				notified[commodity] = false
	next["shortage_ticks"] = shortage
	next["crisis_notified"] = notified
	var expiry := maxi(int(next.get("order_expiry_ticks", 0)), 50)
	for side in ["pending_buys", "pending_sells"]:
		var valid: Array = []
		for order in next.get(side, []):
			if not order is Dictionary:
				continue
			if str(order.get("agent_id", "")).begins_with("market-"):
				continue
			if tick < int(order.get("placed_at_tick", 0)) + expiry:
				valid.append(order)
		next[side] = valid
	## Rust reserve TTL is deliberately unimplemented; never mint released supply.
	next["last_tick"] = tick
	return {"market": next, "events": events}
