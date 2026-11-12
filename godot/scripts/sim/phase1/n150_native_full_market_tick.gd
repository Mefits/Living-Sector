extends RefCounted
## N150: frozen sim_core/agents/market.rs::tick_markets/tick_one_market.
## Full native P1 SOURCE market phase, pure staged result, NO invented
## production, buyerless orders, free stock, reservation TTL or cash.
## Pricing argument is the existing N131 native price_engine.recalculate
## Callable; it is deliberately NOT duplicated in this branch.

const MAX_U32: int = 4294967295
const DEMAND_WINDOW_BASE: int = 100
const DEMAND_WARMUP_BASE: int = 50
const PRICE_HISTORY_KEEP: int = 100 # constant unused by frozen tick
const MARKET_TREND_SAMPLE_INTERVAL_BASE: int = 16
const MARKET_TREND_KEEP: int = 200
const SHORTAGE_SUPPLY_RATIO: float = 0.1
const SHORTAGE_MIN_FLOOR: float = 10.0
const ORDER_EXPIRY_MIN: int = 50

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _num(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _valid_quantity_map(data: Dictionary) -> bool:
	for k in data:
		if not (k is String) or not _num(data[k]):
			return false
	return true

static func _validate(market: Dictionary) -> String:
	# Canonical source read-only snapshot input, not N124 simplified
	# flattened field names and not mutable N68 owner state.
	for k in ["id", "facility_location", "pricing", "flow", "orders", "history"]:
		if not market.has(k):
			return "missing_market:" + k
	if not (market["id"] is String) or str(market["id"]).is_empty() or 			not (market["facility_location"] is String) or 			not (market["pricing"] is Dictionary) or 			not (market["flow"] is Dictionary) or 			not (market["orders"] is Dictionary) or 			not (market["history"] is Dictionary):
		return "invalid_market_components"
	var p: Dictionary = market["pricing"]
	var f: Dictionary = market["flow"]
	var o: Dictionary = market["orders"]
	var h: Dictionary = market["history"]
	for k in ["prices", "supply", "demand"]:
		if not (p.get(k) is Dictionary) or not _valid_quantity_map(p[k]):
			return "invalid_market_pricing:" + k
	if not _num(p.get("price_elasticity")) or not _num(p.get("spread")):
		return "invalid_market_parameters"
	for k in ["seed_demand", "consumption_window"]:
		if not (f.get(k) is Dictionary):
			return "invalid_market_flow:" + k
	if not _valid_quantity_map(f["seed_demand"]):
		return "invalid_market_seed_demand"
	for k in ["pending_buys", "pending_sells", "reserved"]:
		if not o.has(k):
			return "missing_market_orders:" + k
	if not (o["pending_buys"] is Array and o["pending_sells"] is Array and o["reserved"] is Dictionary):
		return "invalid_market_orders"
	if typeof(o.get("order_expiry_ticks")) != TYPE_INT or int(o["order_expiry_ticks"]) < 0:
		return "invalid_order_expiry"
	for k in ["shortage_ticks", "trend_samples", "spawned_at_tick", "last_tick"]:
		if not h.has(k):
			return "missing_market_history:" + k
	if not (h["shortage_ticks"] is Dictionary and h["trend_samples"] is Array):
		return "invalid_market_history"
	if h["spawned_at_tick"] != null and (typeof(h["spawned_at_tick"]) != TYPE_INT or int(h["spawned_at_tick"]) < 0):
		return "invalid_spawn_tick"
	if typeof(h["last_tick"]) != TYPE_INT or int(h["last_tick"]) < 0:
		return "invalid_market_last_tick"
	for slug in h["shortage_ticks"]:
		if not (slug is String) or typeof(h["shortage_ticks"][slug]) != TYPE_INT or 				int(h["shortage_ticks"][slug]) < 0 or int(h["shortage_ticks"][slug]) > MAX_U32:
			return "invalid_shortage_counter"
	return ""

static func record_consumption(flow: Dictionary, commodity: String, quantity: float, tick: int) -> Dictionary:
	## Original::record_consumption ignores qty <= 0 and puts (tick, qty)
	## in rolling MarketFlow.consumption_window. No market inventory
	## mutation — payment / physical consume is an external world Apply.
	if commodity.is_empty() or tick < 0 or not is_finite(quantity):
		return _fail("invalid_consumption")
	var next := flow.duplicate(true)
	if not (next.get("consumption_window") is Dictionary):
		return _fail("missing_consumption_window")
	if quantity <= 0.0:
		return {"ok": true, "flow": next}
	var window: Dictionary = next["consumption_window"]
	var entries: Array = window.get(commodity, []).duplicate(true)
	entries.append({"tick": tick, "qty": quantity})
	window[commodity] = entries
	return {"ok": true, "flow": next}

static func _retain_orders(orders: Array, tick: int, expiry: int) -> Dictionary:
	var remaining: Array = []
	for order in orders:
		if not (order is Dictionary) or not (order.get("agent_id") is String) or 				typeof(order.get("placed_at_tick")) != TYPE_INT:
			return _fail("invalid_actual_order")
		if str(order["agent_id"]).begins_with("market-"):
			continue # original buyerless/ownerless legacy orders removed
		var placed: int = int(order["placed_at_tick"])
		if placed < 0:
			return _fail("invalid_order_placed_at_tick")
		# Rust u64 tick < (placed + expiry). Clamp before adding to avoid
		# Godot int64 overflow in pathological malformed snapshots.
		var age: int = tick - placed
		if age < 0 or age < expiry:
			remaining.append(order.duplicate(true))
	return {"ok": true, "orders": remaining}

static func tick_one_market(market: Dictionary, tick: int, tick_multiplier: int,
		native_price_recalculate: Callable) -> Dictionary:
	## Callable points to N131 ::recalculate(current_price, stock,
	## observed_demand, elasticity, shortage) in the actual composed world.
	## Requires real price source, not fictitious internal price updates.
	var problem := _validate(market)
	if problem != "":
		return _fail(problem)
	if tick < 0 or tick_multiplier < 0:
		return _fail("invalid_market_tick")
	if not native_price_recalculate.is_valid():
		return _fail("missing_original_price_engine")
	var result: Dictionary = market.duplicate(true)
	var pricing: Dictionary = result["pricing"]
	var flow: Dictionary = result["flow"]
	var orders: Dictionary = result["orders"]
	var history: Dictionary = result["history"]
	# Rust spawned_at_tick, seed_demand initialised ONLY on first tick.
	if history["spawned_at_tick"] == null:
		history["spawned_at_tick"] = tick
		if flow["seed_demand"].is_empty():
			flow["seed_demand"] = pricing["demand"].duplicate(true)
	history["last_tick"] = tick
	# No production/consumption or speculative market order matching:
	# those operations were removed from actual frozen Rust runtime.
	var demand_window: int = DEMAND_WINDOW_BASE * tick_multiplier
	var demand_warmup: int = DEMAND_WARMUP_BASE * tick_multiplier
	var cutoff: int = maxi(0, tick - demand_window)
	var warming: bool = tick - int(history["spawned_at_tick"]) < demand_warmup
	var observed := {}
	var windows: Dictionary = flow["consumption_window"]
	var window_slugs := windows.keys()
	window_slugs.sort()
	for slug in window_slugs:
		var entries = windows[slug]
		if not (entries is Array):
			return _fail("invalid_native_consumption_window")
		var kept: Array = []
		var amount: float = 0.0
		for entry in entries:
			# Native source stores (tick, quantity) tuple. Adapter projects
			# {tick:int,qty:float} without fabricating history entries.
			if not (entry is Dictionary) or typeof(entry.get("tick")) != TYPE_INT or 					not _num(entry.get("qty")):
				return _fail("invalid_consumption_sample")
			if int(entry["tick"]) < cutoff:
				continue
			kept.append(entry.duplicate(true))
			amount += float(entry["qty"])
		windows[slug] = kept
		if amount > 0.0:
			observed[slug] = amount
	var all_commodities := {}
	for slug in flow["seed_demand"]:
		all_commodities[slug] = true
	for slug in observed:
		all_commodities[slug] = true
	var demand := {}
	for slug in all_commodities:
		var obs: float = float(observed.get(slug, 0.0))
		var seed: float = float(flow["seed_demand"].get(slug, 0.0))
		demand[slug] = maxf(obs, seed) if warming else (obs if obs > 0.0 else seed)
	pricing["demand"] = demand
	# Frozen shortage and PriceEngine normalize to every GAME second.
	# History trend sampling is independent and remains every 16 RAW ticks.
	var should_reprice: bool = tick % maxi(tick_multiplier, 1) == 0
	if should_reprice:
		var shortages: Dictionary = history["shortage_ticks"]
		var prices: Dictionary = pricing["prices"]
		var slugs := prices.keys()
		slugs.sort()
		for slug in slugs:
			var supply: float = float(pricing["supply"].get(slug, 0.0))
			var need: float = float(demand.get(slug, 0.0))
			if not is_finite(supply) or not is_finite(need):
				return _fail("nonfinite_stock_or_demand")
			var threshold: float = maxf(need * SHORTAGE_SUPPLY_RATIO, SHORTAGE_MIN_FLOOR)
			var prev: int = int(shortages.get(slug, 0))
			shortages[slug] = mini(MAX_U32, prev + 1) if supply < threshold and need > 0.0 else 0
		for slug in slugs:
			var price: float = float(prices[slug])
			var next_price: Variant = native_price_recalculate.call(
				price, float(pricing["supply"].get(slug, 0.0)),
				float(demand.get(slug, 0.0)), float(pricing["price_elasticity"]),
				int(shortages.get(slug, 0)))
			if not _num(next_price) or float(next_price) < 1.0 or float(next_price) > 500.0:
				return _fail("invalid_native_price_result")
			prices[slug] = float(next_price)
	if tick % MARKET_TREND_SAMPLE_INTERVAL_BASE == 0:
		var trends: Array = history["trend_samples"]
		trends.append({"tick": tick, "prices": pricing["prices"].duplicate(true),
			"supply": pricing["supply"].duplicate(true)})
		while trends.size() > MARKET_TREND_KEEP:
			trends.pop_front()
	var expiry: int = maxi(ORDER_EXPIRY_MIN, int(orders["order_expiry_ticks"]))
	for side in ["pending_buys", "pending_sells"]:
		var filtered := _retain_orders(orders[side], tick, expiry)
		if not bool(filtered.get("ok", false)):
			return filtered
		orders[side] = filtered["orders"]
	# Original does NOT release reservations: reserve TTL is explicitly
	# a frozen Rust placeholder. Keep exact existing reserved map.
	history["dirty"] = true
	return {"ok": true, "market": result, "reprice_due": should_reprice,
		"trend_due": tick % MARKET_TREND_SAMPLE_INTERVAL_BASE == 0,
		"effects": {"inventory_delta": 0, "credits_delta": 0,
			"fictitious_market_orders_settled": 0}}

static func tick_markets(markets: Dictionary, tick: int, multiplier: int,
		native_price_recalculate: Callable) -> Dictionary:
	## Atomic staged multi-market projection; snapshot commit remains ECS
	## exclusive. Original Rust serial over real MarketIdentity entities.
	var proposed := {}
	var ids := markets.keys()
	ids.sort()
	for id in ids:
		if not (id is String) or not (markets[id] is Dictionary):
			return _fail("invalid_real_market_registry")
		var m: Dictionary = markets[id]
		if str(m.get("id", "")) != str(id):
			return _fail("market_identity_mismatch")
		var changed := tick_one_market(m, tick, multiplier, native_price_recalculate)
		if not bool(changed.get("ok", false)):
			return _fail(str(id) + ":" + str(changed.get("reason", "")))
		proposed[id] = changed["market"]
	return {"ok": true, "markets": proposed,
		"market_count": proposed.size(), "authority": "one_native_market_ecs_commit"}

static func wire_snapshot(market: Dictionary) -> Dictionary:
	## Frozen MarketSnapshot::build read-only; never persist this as
	## MarketHistory or recreate stock from 200 displayed trend samples.
	var problem := _validate(market)
	if problem != "":
		return _fail(problem)
	var pricing: Dictionary = market["pricing"]
	var history: Dictionary = market["history"]
	var trends: Array = []
	for item in history["trend_samples"]:
		if not (item is Dictionary):
			return _fail("invalid_trend_sample")
		trends.append(item.duplicate(true))
	return {"ok": true, "snapshot": {
		"id": market["id"], "facility_location": market["facility_location"],
		"prices": pricing["prices"].duplicate(true),
		"supply": pricing["supply"].duplicate(true),
		"demand": pricing["demand"].duplicate(true),
		"shortage_ticks": history["shortage_ticks"].duplicate(true),
		"trend_samples": trends}}
