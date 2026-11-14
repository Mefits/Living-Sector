extends RefCounted
## V3/N38: one timeline for the frozen N150 MarketHistory, physical N15/N21
## receipts and source ship transit. This is read-only checkpoint preflight;
## the only actual clock/tick owner remains N1 TickRunner.
##
## IMPORTANT: an arrival_tick or an order expiry is a FUTURE DEADLINE,
## not a completed event. Native ticks/calendar units are also not
## interchangeable when speed changes. Never derive elapsed time from
## tick * current world_speed.
const MAX_EXACT_TICK: float = 9007199254740991.0
const MARKET_TREND_HISTORY_LIMIT: int = 200

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _native_tick(value: Variant, last: int) -> bool:
    if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
        return false
    var n: float = float(value)
    return is_finite(n) and n >= 0.0 and n <= MAX_EXACT_TICK and (
        n == floorf(n)) and n <= float(last)

static func _required_tick(row: Dictionary, key: String, committed: int,
        trace: String) -> String:
    if not _native_tick(row.get(key, null), committed):
        return trace + "/" + key + ":future_or_invalid"
    return ""

static func validate(checkpoint: Dictionary) -> Dictionary:
    if not checkpoint.has("native_production"):
        return {"ok": true, "scope": "legacy_no_native_world"}
    var native: Variant = checkpoint["native_production"]
    var current: Variant = checkpoint.get("tick", null)
    if not (native is Dictionary) or not _native_tick(current, 9007199254740991):
        return _reject("missing_or_invalid_canonical_tick")
    var tick: int = int(current)
    if not _native_tick(native.get("tick", null), tick) or int(native["tick"]) != tick:
        return _reject("world_and_checkpoint_tick_diverged")
    var world: Variant = native.get("world", null)
    if not (world is Dictionary):
        return _reject("missing_single_native_world")
    if not (world.get("markets") is Dictionary):
        return _reject("missing_native_markets")
    var checked_markets: int = 0
    var checked_trends: int = 0
    var checked_receipts: int = 0
    for location in world["markets"]:
        if not (location is String) or not (world["markets"][location] is Dictionary):
            return _reject("invalid_market_identity")
        var market: Dictionary = world["markets"][location]
        # Old P1 production saves did not yet carry N150 MarketHistory.
        # Do not invent absent history, but validate every persisted row.
        if market.has("history"):
            if not (market["history"] is Dictionary):
                return _reject("invalid_market_history:" + str(location))
            var history: Dictionary = market["history"]
            if history.has("last_tick"):
                var problem: String = _required_tick(history, "last_tick", tick,
                    "market:" + str(location))
                if not problem.is_empty():
                    return _reject(problem)
            if history.has("spawned_at_tick") and history["spawned_at_tick"] != null:
                var bound: int = tick
                if history.has("last_tick") and _native_tick(history["last_tick"], tick):
                    bound = int(history["last_tick"])
                if not _native_tick(history["spawned_at_tick"], bound):
                    return _reject("market:" + str(location) + "/spawned_at_tick:future")
            if history.has("trend_samples"):
                if not (history["trend_samples"] is Array) or (
                        history["trend_samples"].size() > MARKET_TREND_HISTORY_LIMIT):
                    return _reject("market:" + str(location) + "/trend_history_invalid")
                var last_sample: int = -1
                var bound: int = tick
                if history.has("last_tick"):
                    bound = int(history["last_tick"])
                for sample in history["trend_samples"]:
                    if not (sample is Dictionary) or not _native_tick(
                            sample.get("tick", null), bound):
                        return _reject("market:" + str(location) + "/trend_in_future")
                    var sample_tick: int = int(sample["tick"])
                    if sample_tick <= last_sample:
                        return _reject("market:" + str(location) + "/trend_not_chronological")
                    last_sample = sample_tick
                    checked_trends += 1
        if market.has("consumption_window"):
            if not (market["consumption_window"] is Dictionary):
                return _reject("invalid_consumption_window:" + str(location))
            for commodity in market["consumption_window"]:
                var series: Variant = market["consumption_window"][commodity]
                if not (series is Array):
                    return _reject("invalid_consumption_series:" + str(location))
                for sample in series:
                    if not (sample is Dictionary) or not _native_tick(
                            sample.get("tick", null), tick):
                        return _reject("future_or_invalid_consumption:" +
                            str(location) + "/" + str(commodity))
        checked_markets += 1
    # These are already executed physical events, NOT future intentions.
    # Historical receipts can outlive a decommissioned ship or facility.
    for collection in ["dock_receipts", "cargo_receipts",
            "native_gate_jump_receipts"]:
        if not world.has(collection):
            continue
        if not (world[collection] is Dictionary):
            return _reject("invalid_physical_receipt_collection:" + collection)
        for operation_id in world[collection]:
            var record: Variant = world[collection][operation_id]
            if not (record is Dictionary) or not _native_tick(
                    record.get("tick", null), tick):
                return _reject("future_physical_receipt:" + collection +
                    "/" + str(operation_id))
            checked_receipts += 1
    # Transit.last_tick and departure_tick describe *observed* progress.
    # Transit.arrival_tick is an expected future deadline: do not cap it.
    if world.has("ships"):
        if not (world["ships"] is Dictionary):
            return _reject("invalid_single_world_fleet")
        for ship_id in world["ships"]:
            var ship: Variant = world["ships"][ship_id]
            if not (ship is Dictionary):
                return _reject("invalid_fleet_actor")
            var transit: Variant = ship.get("transit", {})
            if not (transit is Dictionary):
                return _reject("invalid_ship_transit")
            if transit.is_empty():
                continue
            for field in ["departure_tick", "last_tick"]:
                if not _native_tick(transit.get(field, null), tick):
                    return _reject("ship:" + str(ship_id) + "/" + field +
                        ":future_or_invalid")
            var departure: int = int(transit["departure_tick"])
            if int(transit["last_tick"]) < departure:
                return _reject("ship:" + str(ship_id) + "/last_before_departure")
            if not _native_tick(transit.get("arrival_tick", null), 9007199254740991):
                return _reject("ship:" + str(ship_id) + "/invalid_arrival_deadline")
            if int(transit["arrival_tick"]) < departure:
                return _reject("ship:" + str(ship_id) + "/arrival_before_departure")
    return {"ok": true, "scope": "one_N38_N39_N150_source_timeline",
        "markets": checked_markets, "trend_samples": checked_trends,
        "physical_receipts": checked_receipts}
