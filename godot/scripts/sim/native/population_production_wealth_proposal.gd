extends RefCounted
## N127. Frozen Rust agents/population.rs::tick_populations production/wealth slice.
## Output is an intent: only authoritative market+population Apply may mutate.
const PRODUCTION_INTERVAL_BASE := 5
const MONETISATION_RATE := 0.10
const MAX_I64 := 9223372036854775807

static func propose(population: Dictionary, market: Dictionary, tick: int, tick_multiplier: int, lod_fires: bool = true) -> Dictionary:
	if tick < 0 or tick_multiplier <= 0 or tick % (PRODUCTION_INTERVAL_BASE * tick_multiplier) != 0 or not lod_fires:
		return {"ok": false, "reason": "cadence_or_lod"}
	if str(population.get("location", "")).is_empty() or str(population.get("location", "")) != str(market.get("location", "")):
		return {"ok": false, "reason": "missing_local_market"}
	var commodity := str(population.get("production_commodity", ""))
	var amount := float(population.get("production_amount", 0.0))
	if commodity.is_empty() or not is_finite(amount) or amount <= 0.0:
		return {"ok": false, "reason": "no_positive_production"}
	var prices: Dictionary = market.get("prices", {})
	var supplies: Dictionary = market.get("supply", {})
	var before := float(supplies.get(commodity, 0.0))
	if not is_finite(before) or before < 0.0 or before + amount < before:
		return {"ok": false, "reason": "invalid_market_supply"}
	var price := float(prices.get(commodity, 0.0))
	if not is_finite(price) or price < 0.0:
		return {"ok": false, "reason": "invalid_market_price"}
	var wealth_before := int(population.get("total_wealth", 0))
	if wealth_before < 0:
		return {"ok": false, "reason": "negative_wealth"}
	# Rust f32 multiplication then round() as i64; positive finite values.
	var raw_delta := floorf(price * amount * MONETISATION_RATE + 0.5)
	if not is_finite(raw_delta) or raw_delta > float(MAX_I64 - wealth_before):
		return {"ok": false, "reason": "wealth_overflow"}
	var delta := int(raw_delta)
	return {
		"ok": true, "kind": "population_production",
		"population_id": str(population.get("id", "")),
		"location": str(population.get("location", "")),
		"commodity": commodity, "supply_before": before,
		"supply_delta": amount, "supply_after": before + amount,
		"wealth_before": wealth_before, "wealth_delta": delta,
		"wealth_after": wealth_before + delta,
		"tick": tick, "requires_authoritative_apply": true,
		"requires_once_per_tick": true
	}

static func combine_consumption_wealth(production_delta: int, consumption_delta: int, wealth_before: int) -> Dictionary:
	# Rust accumulates production + consumed-goods outflow once, then clamps wealth >= 0.
	# The consumption delta must come from ACTUALLY consumed market units.
	if wealth_before < 0 or (production_delta > 0 and consumption_delta > MAX_I64 - production_delta):
		return {"ok": false, "reason": "invalid_wealth"}
	var net := production_delta + consumption_delta
	return {"ok": true, "net_wealth_delta": net, "wealth_after": maxi(0, wealth_before + net)}
