extends RefCounted
## N143: exact native director.rs::research_ready and research() domain,
## after Director.observe selected a target.
## Side effect free: produces a single authoritative atomic mutation intent.
## This module NEVER commits a second ledger, prints money or creates
## electronics. N45 native credits/market/worker authority owns actual APPLY.
const Policy = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const MAX_I64: int = 9223372036854775807
const WORKERS: int = 10
const PAID_WORK: int = 10
const PAYROLL_CR: int = 10
const RESERVE_CR: int = 10000

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _research_id(commander: Dictionary) -> String:
	var v = commander.get("research", null)
	return v if v is String else ""

static func _valid_price(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and 		float(value) >= 0.0 and float(value) <= 10000.0

static func _market_sort(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("location", "")) != str(b.get("location", "")):
		return str(a.get("location", "")) < str(b.get("location", ""))
	return int(a.get("_source_index", 0)) < int(b.get("_source_index", 0))

static func _person_sort(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != str(b.get("id", "")):
		return str(a.get("id", "")) < str(b.get("id", ""))
	return int(a.get("_source_index", 0)) < int(b.get("_source_index", 0))

static func _valid_input(input: Dictionary) -> String:
	for key in ["commander", "markets", "people", "faction_id", "tick", "treasury"]:
		if not input.has(key):
			return "missing_research_input:" + key
	if not (input["commander"] is Dictionary) or not (input["markets"] is Array) or not (input["people"] is Array):
		return "invalid_research_collection"
	if not (input["faction_id"] is String) or str(input["faction_id"]).is_empty():
		return "invalid_faction_id"
	if typeof(input["tick"]) != TYPE_INT or int(input["tick"]) < 0:
		return "invalid_tick"
	if typeof(input["treasury"]) != TYPE_INT or int(input["treasury"]) < 0:
		return "invalid_treasury"
	if not (input.get("mandate", {}) is Dictionary) or not (input.get("charter", {}) is Dictionary):
		return "invalid_research_policy"
	return ""

static func _ordered_markets(markets: Array) -> Array:
	var result: Array = []
	for i in range(markets.size()):
		if not (markets[i] is Dictionary):
			return []
		var item: Dictionary = markets[i].duplicate(true)
		item["_source_index"] = i
		result.append(item)
	result.sort_custom(_market_sort)
	return result

static func _ordered_people(people: Array) -> Array:
	var result: Array = []
	for i in range(people.size()):
		if not (people[i] is Dictionary):
			return []
		var item: Dictionary = people[i].duplicate(true)
		item["_source_index"] = i
		result.append(item)
	result.sort_custom(_person_sort)
	return result

static func _workers_available(person: Dictionary, tick: int) -> int:
	## Native facility/workforce.rs::occupied_workers(world,tick) is owned
	## by N141; this method receives its exact read-only result.
	## No workers are reserved or double-allocated by N143.
	var population = person.get("population_count", null)
	var occupied = person.get("occupied_workers", null)
	if typeof(population) != TYPE_INT or typeof(occupied) != TYPE_INT:
		return -1
	if int(population) < 0 or int(occupied) < 0 or int(population) > 1000000000:
		return -1
	return int(int(population) * 3 / 5) - int(occupied)

static func _eligible_person(person: Dictionary, faction: String, location: String, tick: int) -> bool:
	return str(person.get("faction_id", "")) == faction and 		str(person.get("location", "")) == location and 		_workers_available(person, tick) >= WORKERS

static func _station_for_faction(market: Dictionary, faction: String) -> bool:
	## Caller derives owner_faction / facility_type from the actual
	## FacilityIdentity associated with MarketIdentity.facility. They are
	## NOT guessed from system naming or visual location markers.
	return str(market.get("owner_faction", "")) == faction and 		str(market.get("facility_type", "")) == "station"

static func research_ready(input: Dictionary, catalogue_rows: Array) -> Dictionary:
	## Mirrors director.rs::research_ready, NOT research() preflight.
	## Native readiness lacks last_research_tick check and uses *strict*
	## treasury > ceil(price) + 10010, while actual shift accepts treasury
	## >= ceil(price) + 10010. Keep this intentional asymmetry.
	var bad := _valid_input(input)
	if bad != "":
		return _fail(bad)
	var commander: Dictionary = input["commander"]
	var id := _research_id(commander)
	if id == "" or bool(commander.get("crisis", false)):
		return {"ok": true, "ready": false, "reason": "research_missing_or_crisis"}
	var catalogue := Policy.catalogue_map(catalogue_rows)
	if catalogue.is_empty():
		return _fail("invalid_catalogue")
	var mandate: Dictionary = input.get("mandate", {})
	var charter: Dictionary = input.get("charter", {})
	var completed: Array = commander.get("technologies", [])
	if not mandate.is_empty() and Policy._active_mandate(mandate, completed) and str(mandate.get("mode", "")) == "hold":
		return {"ok": true, "ready": false, "reason": "player_research_hold"}
	var treasury: int = int(input["treasury"])
	var faction: String = str(input["faction_id"])
	var people: Array = input["people"]
	for market in input["markets"]:
		if not (market is Dictionary) or not _station_for_faction(market, faction):
			continue
		var supply: float = float(market.get("electronics_supply", 0.0))
		var price: float = float(market.get("electronics_price", 0.0))
		if not is_finite(supply) or supply < 1.0 or not is_finite(price):
			continue
		var quote: int = int(ceil(price))
		if treasury <= quote + 10010:
			continue
		var authorization := Policy.authorize_research(commander, mandate, charter, catalogue, quote + PAYROLL_CR, treasury)
		if not bool(authorization.get("ok", false)):
			continue
		for person in people:
			if person is Dictionary and _eligible_person(person, faction, str(market.get("location", "")), int(input["tick"])):
				return {"ok": true, "ready": true, "reason": ""}
	return {"ok": true, "ready": false, "reason": "not_ready"}

static func prepare_paid_shift(input: Dictionary, catalogue_rows: Array) -> Dictionary:
	## Mirrors Rust director.rs::research and its exact short-circuit order.
	## Returns a full one-shot *intent*, not a committed world. Phase-2 owner
	## must validate the receipt and apply ALL changes in one native tick.
	var bad := _valid_input(input)
	if bad != "":
		return _fail(bad)
	var faction: String = str(input["faction_id"])
	var tick: int = int(input["tick"])
	var commander: Dictionary = input["commander"]
	if commander.is_empty():
		return _fail("missing_commander")
	var last: Variant = commander.get("last_research_tick", null)
	if last != null and int(last) >= tick:
		return _fail("already_researched")
	var target := _research_id(commander)
	if target == "":
		return _fail("research_complete")
	if bool(commander.get("crisis", false)):
		return _fail("survival_first")
	var catalogue := Policy.catalogue_map(catalogue_rows)
	if catalogue.is_empty() or not catalogue.has(target):
		return _fail("unknown_research_target")
	var treasury: int = int(input["treasury"])
	var markets := _ordered_markets(input["markets"])
	var people := _ordered_people(input["people"])
	var mandate: Dictionary = input.get("mandate", {})
	var charter: Dictionary = input.get("charter", {})
	for market in markets:
		if not _station_for_faction(market, faction):
			continue
		var supply: float = float(market.get("electronics_supply", -1.0))
		if not is_finite(supply) or supply < 1.0:
			continue
		var price_v = market.get("electronics_price")
		if not _valid_price(price_v):
			continue
		var cost: int = int(ceil(float(price_v))) + PAYROLL_CR
		# Source returns immediately if first eligible market cannot be
		# funded, rather than testing a cheaper station later.
		if treasury < cost + RESERVE_CR:
			return _fail("research_reserve")
		var auth := Policy.authorize_research(commander, mandate, charter, catalogue, cost, treasury)
		if not bool(auth.get("ok", false)):
			return _fail(str(auth.get("reason", "authorization_failed")))
		for person in people:
			if not _eligible_person(person, faction, str(market.get("location", "")), tick):
				continue
			if typeof(person.get("wealth")) != TYPE_INT or int(person["wealth"]) > MAX_I64 - PAYROLL_CR:
				continue
			if typeof(market.get("facility_credits")) != TYPE_INT:
				continue
			if int(market["facility_credits"]) > MAX_I64 - (cost - PAYROLL_CR):
				continue
			if typeof(commander.get("progress", 0)) != TYPE_INT or typeof(commander.get("research_required", 0)) != TYPE_INT:
				return _fail("invalid_research_progress")
			var work_after: int = int(commander.get("progress", 0)) + PAID_WORK
			var completed: bool = work_after >= int(commander.get("research_required", 0))
			var updated_c: Dictionary = commander.duplicate(true)
			updated_c["progress"] = work_after
			updated_c["last_research_tick"] = tick
			updated_c["last_shift"] = {"tick": tick, "workers": [[person["id"], WORKERS]],
				"wages": PAYROLL_CR, "input_payment": cost - PAYROLL_CR,
				"processing_fee": 0, "last_recipe_ticks": {}, "produced_outputs": {}}
			var unlocked: Variant = null
			if completed:
				unlocked = target
				updated_c["research"] = null
				var techs: Array = updated_c.get("technologies", []).duplicate()
				techs.append(target)
				updated_c["technologies"] = techs
				var history: Array = updated_c.get("history", []).duplicate(true)
				var record := {"tick": tick, "action": "technology_completed",
					"reason": target, "outcome": "completed"}
				if history.is_empty() or history[-1].get("action") != record["action"] or 						history[-1].get("reason") != record["reason"] or 						history[-1].get("outcome") != record["outcome"]:
					history.append(record)
					if history.size() > 100:
						history.pop_front()
				updated_c["history"] = history
			var after := Policy.paid_after_receipt(mandate, charter, cost, bool(auth.get("mandated_shift", false)))
			if not bool(after.get("ok", false)):
				return _fail("invalid_research_receipt_policy")
			var id: String = "native_research:" + faction + ":" + str(tick)
			return {"ok": true, "reason": "", "faction_id": faction, "tick": tick,
				"receipt_id": id, "technology": target, "completed_technology": unlocked,
				"market_id": market.get("id", null), "facility_id": market.get("facility_id", null),
				"population_id": person.get("id", null),
				"location": market.get("location", null),
				"cost": cost, "payroll": PAYROLL_CR, "electronics": 1.0,
				"work_added": PAID_WORK, "mandated_shift": bool(auth.get("mandated_shift", false)),
				# All four actual mutations must share one authoritative transaction.
				"effects": {"faction_treasury_delta": -cost, "market_electronics_delta": -1.0,
					"facility_credits_delta": cost - PAYROLL_CR,
					"population_wealth_delta": PAYROLL_CR},
				"preconditions": {"treasury": treasury, "market_electronics": supply,
					"facility_credits": market["facility_credits"],
					"population_wealth": person["wealth"],
					"last_research_tick": last, "research": target},
				"commander_after": updated_c, "mandate_after": after["mandate"],
				"charter_after": after["charter"]}
	# No verified local electronics+staff action was possible.
	return _fail("needs_local_electronics_and_free_workers")

static func verify_authoritative_receipt(proposal: Dictionary, paid_receipt: Dictionary) -> Dictionary:
	## Boundary of Phase-1 code and real engine commit. This function DOES
	## NOT cause effects. The trusted authoritative world must provide a
	## single receipt AFTER it has atomically debited real faction CR,
	## credited facility+worker and consumed one electronics.
	## Do not accept a matching human-supplied dict as proof of payment.
	if not bool(proposal.get("ok", false)) or not bool(paid_receipt.get("authoritative", false)):
		return _fail("native_paid_receipt_required")
	for field in ["receipt_id", "faction_id", "tick", "market_id", "facility_id", "population_id"]:
		if proposal.get(field) != paid_receipt.get(field):
			return _fail("paid_research_receipt_mismatch:" + field)
	if paid_receipt.get("effects") != proposal.get("effects"):
		return _fail("paid_research_effect_mismatch")
	if paid_receipt.get("technology") != proposal.get("technology"):
		return _fail("paid_research_technology_mismatch")
	return {"ok": true, "reason": "", "commander": proposal.get("commander_after", {}).duplicate(true),
		"mandate": proposal.get("mandate_after", {}).duplicate(true),
		"charter": proposal.get("charter_after", {}).duplicate(true),
		"receipt_id": paid_receipt["receipt_id"]}
