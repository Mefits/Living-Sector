extends RefCounted
## N135 cheap pure contract checks; not run until Phase-2 Godot integration.
const Core = preload("res://scripts/sim/n135_station_orders_core.gd")
const Dispatch = preload("res://scripts/sim/n135_station_orders_dispatch.gd")

static func _ship(id: String, sensors: float = 2.0) -> Dictionary:
	return {"id": id, "faction": "civ", "class": "freighter", "location": "home",
		"cargo_used": 0, "cargo_free": 100, "credits": 1000,
		"fuel_fraction": 0.9, "speed": 1.0, "in_transit": false,
		"active_contract_id": "", "transaction_pending": false,
		"reputation": {"civ": 100}, "sensors": sensors, "comms_bonus": 0.0,
		"passenger_capacity": 0, "crew_roles": ["engineer"]}

static func _contract(id: String = "c1") -> Dictionary:
	return {"id": id, "status": "Posted", "contract_type": "Delivery",
		"faction_id": "civ", "requestor_id": "fac", "fulfiller_id": "",
		"source_location": "mine", "destination_location": "port",
		"commodity": "ore", "quantity": 50, "payment": 1600,
		"initial_payment": 1600, "posted_at_tick": 0, "min_reputation": 0,
		"mission_category": "strategy.logistics.v1",
		"funding": {"source": "Faction", "reserved": 1600, "station_order": null}}

static func _snapshot() -> Dictionary:
	return {"executing": true, "galaxy": true, "tick": 1, "multiplier": 1,
		"contracts": [_contract()], "sites": [], "ships": [_ship("a"), _ship("b")],
		"owners": {"mine": "civ", "port": "civ"},
		"markets": {"mine": {"supply": {"ore": 100.0}, "prices": {"ore": 15.0}}},
		"facility_payers": {"fac": 900},
		"relations": {},
		"locations": {"home": {"system": "sol"}, "mine": {"system": "sol"},
			"port": {"system": "sol"}},
		"orbits": {},
		"distances": {"home": {"mine": 1, "port": 2},
			"mine": {"port": 1}, "port": {"mine": 1}}}

static func check() -> Dictionary:
	var failures: Array[String] = []
	var state := _snapshot()
	var staged := Dispatch.run(state)
	var c: Dictionary = staged["contracts"][0]
	if not bool(staged["staged"]) or str(Core.order_of(c).get("executor_id", "")) != "a":
		failures.append("contract assignment / lexical tie")
	if int(Core.order_of(c).get("attempt", 0)) != 1:
		failures.append("assignment counter")
	if int(staged["contracts"][0]["funding"]["reserved"]) != 1600 or state["contracts"][0]["funding"]["station_order"] != null:
		failures.append("money/source mutated")
	var replay := state.duplicate(true)
	replay["contracts"] = staged["contracts"].duplicate(true)
	var again := Dispatch.run(replay)
	if int(Core.order_of(again["contracts"][0]).get("attempt", 0)) != 1:
		failures.append("posted lease should be idempotent")
	var shadow := _snapshot()
	shadow["executing"] = false
	if not Core.order_of(Dispatch.run(shadow)["contracts"][0]).is_empty():
		failures.append("shadow dispatched")
	var denied := _snapshot()
	denied["ships"] = [_ship("a", 1.0)]
	denied["tick"] = 180
	var public_c := _contract()
	public_c["mission_category"] = ""
	public_c["funding"] = {"source": "Facility", "reserved": 100, "station_order": null}
	public_c["payment"] = 1000
	public_c["initial_payment"] = 0
	denied["contracts"] = [public_c]
	denied["locations"]["port"]["system"] = "other"
	var blocked := Dispatch.run(denied)
	if str(Core.order_of(blocked["contracts"][0]).get("blocked_reason", "")) != "no_sensor_qualified_carrier":
		failures.append("T1 sensors bypass")
	denied["tick"] = 181
	denied["ships"] = [_ship("a", 2.0)]
	denied["contracts"] = blocked["contracts"]
	denied["tick"] = 211 # Wait for 30 tick blocked cooldown.
	var qualified := Dispatch.run(denied)
	if str(Core.order_of(qualified["contracts"][0]).get("executor_id", "")) != "a":
		failures.append("T2 rescue on paid facility order")
	var building := _snapshot()
	building["contracts"] = []
	building["sites"] = [{"id": "site", "faction_id": "civ", "location_name": "port",
		"completed": false, "remaining": 0, "labor": {"required": 150,
		"completed": 0, "station_order": null, "colony_source": ""}}]
	var builder := Dispatch.run(building)
	if str(builder["sites"][0]["labor"]["station_order"].get("executor_id", "")) != "a":
		failures.append("builder receives material-ready site")
	return {"ok": failures.is_empty(), "failures": failures}
