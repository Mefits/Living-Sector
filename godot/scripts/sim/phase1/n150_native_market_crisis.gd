extends RefCounted
## N150 native sim_server/src/engine.rs::scan_crisis_events MARKET branch.
## Facility starvation is macro #1, not silently included in this scope.
## No direct events/world edits: returns stage-only MarketHistory and event
## projection from actual ECS shortage and current N140 WorldTuning.

const DEFAULT_CRISIS_TICKS: int = 200
const DEFAULT_RECOVERY_TICKS: int = 50

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func scan(markets: Dictionary, shortage_crisis_ticks: int,
		shortage_recovery_ticks: int) -> Dictionary:
	## Source uses WorldTuning::current(), not a new hardcoded setting.
	if shortage_crisis_ticks < 1 or shortage_recovery_ticks < 0:
		return _fail("invalid_world_tuning_shortage_threshold")
	var next := markets.duplicate(true)
	var emitted: Array[Dictionary] = []
	var ids := next.keys()
	ids.sort()
	for market_id in ids:
		var market = next[market_id]
		if not (market is Dictionary) or not (market.get("history") is Dictionary) or 				not (market.get("facility_location") is String):
			return _fail("invalid_actual_market")
		var history: Dictionary = market["history"]
		if not (history.get("shortage_ticks") is Dictionary) or 				not (history.get("crisis_notified") is Dictionary):
			return _fail("missing_market_history_crisis_flags")
		var notified: Dictionary = history["crisis_notified"]
		var shortage: Dictionary = history["shortage_ticks"]
		var slugs := shortage.keys()
		slugs.sort()
		for commodity in slugs:
			var count = shortage[commodity]
			if not (commodity is String) or typeof(count) != TYPE_INT or int(count) < 0:
				return _fail("invalid_market_shortage_counter")
			var was_notified: bool = bool(notified.get(commodity,false))
			if int(count) >= shortage_crisis_ticks and not was_notified:
				emitted.append({"kind":"market_crisis","market_id":str(market_id),
					"location":market["facility_location"],
					"commodity":commodity, "shortage_ticks":int(count)})
				notified[commodity] = true
			elif int(count) <= shortage_recovery_ticks and was_notified:
				emitted.append({"kind":"market_recovered","market_id":str(market_id),
					"location":market["facility_location"], "commodity":commodity})
				notified[commodity] = false
		history["crisis_notified"] = notified
		market["history"] = history
		next[market_id] = market
	return {"ok": true, "markets": next, "events": emitted,
		"authority": "exclusive_native_crisis_scan_then_event_bus"}
