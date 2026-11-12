extends RefCounted
## Frozen Rust: agents/population.rs::run_population_migration.
## One pressure-triggered transfer per pass. Copies input; conserves headcount and wealth.
const PRESSURE_TRIGGER := 1.0
const HEAD_COUNT := 100
const MIN_DESTINATION_SENTIMENT := 50
const SENTIMENT_FLOOR := 30
const PRESSURE_RISE := 0.01
const PRESSURE_DECAY := 0.005
const CHECK_INTERVAL_BASE := 200

static func advance_pressure(pop: Dictionary, tick_scale: float) -> Dictionary:
	var out: Dictionary = pop.duplicate(true)
	if not is_finite(tick_scale) or tick_scale < 0.0:
		return out
	var delta: float = PRESSURE_RISE * tick_scale if int(out.get("overall_sentiment", 50)) < SENTIMENT_FLOOR else -PRESSURE_DECAY * tick_scale
	out["migration_pressure"] = clampf(float(out.get("migration_pressure", 0.0)) + delta, 0.0, 2.0)
	return out

static func migrate(populations: Array) -> Dictionary:
	var pops: Array = populations.duplicate(true)
	var source_index: int = -1
	var highest_pressure: float = -1.0
	for i in range(pops.size()):
		var p: Dictionary = pops[i]
		if p.get("is_dock", false) or int(p.get("population_count", 0)) <= HEAD_COUNT * 3:
			continue
		var pressure: float = float(p.get("migration_pressure", 0.0))
		if pressure >= PRESSURE_TRIGGER and pressure > highest_pressure:
			highest_pressure = pressure
			source_index = i
	if source_index < 0:
		return {"ok": true, "populations": pops, "moved": 0}
	var source: Dictionary = pops[source_index]
	var dest_index: int = -1
	var best_sentiment: int = -1
	for i in range(pops.size()):
		if i == source_index:
			continue
		var p: Dictionary = pops[i]
		if p.get("is_dock", false) or p.get("facility_location") == source.get("facility_location"):
			continue
		var sentiment: int = int(p.get("overall_sentiment", 0))
		if sentiment >= MIN_DESTINATION_SENTIMENT and sentiment > best_sentiment:
			best_sentiment = sentiment
			dest_index = i
	if dest_index < 0:
		return {"ok": true, "populations": pops, "moved": 0}
	var dest: Dictionary = pops[dest_index]
	var count: int = int(source["population_count"])
	var moved: int = mini(HEAD_COUNT, maxi(0, count - 100))
	var source_cash: int = int(source.get("total_wealth", 0))
	var dest_cash: int = int(dest.get("total_wealth", 0))
	if moved <= 0 or source_cash < 0 or dest_cash < 0:
		return {"ok": false, "reason": "invalid_population_or_cash"}
	var transfer: int = int(float(source_cash) * float(moved) / float(count))
	if transfer < 0 or dest_cash > 9223372036854775807 - transfer:
		return {"ok": false, "reason": "wealth_overflow"}
	source["population_count"] = count - moved
	dest["population_count"] = int(dest["population_count"]) + moved
	source["total_wealth"] = source_cash - transfer
	dest["total_wealth"] = dest_cash + transfer
	source["migration_pressure"] = 0.0
	source["dirty"] = true
	dest["dirty"] = true
	pops[source_index] = source
	pops[dest_index] = dest
	return {"ok": true, "populations": pops, "moved": moved, "wealth_transferred": transfer, "source_id": source.get("id"), "destination_id": dest.get("id")}
