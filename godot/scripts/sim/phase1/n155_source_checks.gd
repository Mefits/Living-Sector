extends RefCounted
## N155 Phase1 source-derived checks (AUTHORED, NOT EXECUTED). One runtime
## parser/parity suite for N93/N99/N100/N121 combined is deferred to Phase2.
const Native = preload("res://scripts/sim/phase1/n155_native_catalogue.gd")
const Domain = preload("res://scripts/sim/phase1/n155_native_domain.gd")
const Htn = preload("res://scripts/sim/phase1/n155_htn_methods.gd")
const Telic = preload("res://scripts/sim/phase1/n155_telic_goap_shadow.gd")
const Validate = preload("res://scripts/sim/phase1/n155_planning_validation.gd")
const Bridge = preload("res://scripts/sim/phase1/n155_head_strategy_shadow.gd")

static func _fixture() -> Dictionary:
	return {"schema_version":1,"tick":500,"faction_id":"faction-a",
		"treasury_credits":18000,"treasury_floor_credits":5000,
		"owned_markets":[
			{"market_id":"m-a","facility_id":"market-a","location_id":"sol",
			 "stock":{"ice":30.0},"demand":{"water":0.0},"prices":{"ice":10.0}},
			{"market_id":"m-b","facility_id":"market-b","location_id":"tau",
			 "stock":{"ice":0.0,"water":0.0},"demand":{"water":20.0},
			 "prices":{"ice":11.0}}],
		"facilities":[
			{"facility_id":"market-a","location_id":"sol","facility_type":"market"},
			{"facility_id":"market-b","location_id":"tau","facility_type":"market"},
			{"facility_id":"refinery-tau","location_id":"tau","facility_type":"refinery"}],
		"ships":[{"ship_id":"s1","class":"freighter","location_id":"sol",
			"in_transit":false,"free_cargo":20,"fuel":100.0}],
		"active_commitments":[],"technologies":[],
		"recipes":[{"recipe_id":"ice_to_water","facility_type":"refinery",
			"inputs":[["ice",10]],"outputs":[["water",10]]}]}

static func run_checks() -> Dictionary:
	var failures: Array[String] = []
	var snapshot: Dictionary = _fixture()
	var goal: Dictionary = {"goal_id":"supply:tau:water","destination_id":"tau",
		"commodity":"water","target_units":10,"priority":100}
	var generated: Dictionary = Native.catalogue(snapshot,"tau","water")
	_check(generated.get("ok",false),"two owned unique markets project successfully",failures)
	_check(generated.get("actions",[]).size() >= 2,"recipe and physical lot actions available",failures)
	var projected: Dictionary = generated.get("projected",{})
	var domain: Dictionary = Domain.domain_from_native(projected,goal,generated.get("actions",[]))
	_check(domain.get("ok",false),"source HTN stock domain physically grounded",failures)
	if domain.get("ok",false):
		var init: Array = domain["initial"]
		var rejected: Array = Domain.apply(init,{"pre":[[0,2147483647]],"delta":[]})
		_check(rejected.is_empty(),"missing 2^31 units refuses invented stock",failures)
		var ht: Dictionary = Htn.plan(projected,goal,generated.get("actions",[]),
			{"max_nodes":350,"max_depth":12})
		_check(ht.get("native_dispatch_authorized",true) == false,"HTN result never authorizes native mutation",failures)
		var tel: Dictionary = Telic.plan(projected,goal,generated.get("actions",[]),
			{"max_nodes":350,"max_depth":12})
		_check(tel.get("native_dispatch_authorized",true) == false,"GOAP result never authorizes native mutation",failures)
	var malformed: Dictionary = _fixture()
	malformed["owned_markets"].append({"market_id":"m-duplicate","facility_id":"market-b",
		"location_id":"tau","stock":{},"demand":{},"prices":{}})
	_check(Native.catalogue(malformed,"tau","water").get("error","") == "ambiguous_destination_markets",
		"co-located markets may never merge",failures)
	var committed: Dictionary = _fixture()
	committed["active_commitments"].append({"contract_id":"c","status":"posted",
		"source":"sol","destination":"tau","commodity":"ice","quantity":25,
		"assigned_ship_id":null})
	var before: int = int(committed["owned_markets"][0]["stock"]["ice"])
	var cleaned: Dictionary = Native.catalogue(committed,"tau","water")
	_check(int(cleaned.get("projected",{}).get("owned_markets",[])[0].get("stock",{}).get("ice",0)) == 5,
		"committed posted stock subtracted only in projection",failures)
	_check(int(committed["owned_markets"][0]["stock"]["ice"]) == before,
		"read-only projection does not remove real Ice",failures)
	var assigned: Dictionary = _fixture()
	assigned["active_commitments"].append({"contract_id":"busy","status":"accepted",
		"source":"sol","destination":"tau","commodity":"ore","quantity":2,
		"assigned_ship_id":"s1"})
	var cannot_deliver: Dictionary = Native.catalogue(assigned,"tau","ice")
	var any_delivery: bool = false
	for a in cannot_deliver.get("actions",[]):
		if str(a.get("kind","")) == "deliver": any_delivery = true
	_check(not any_delivery,"leased ship cannot be reused as physical hauler",failures)
	var nogoods: Dictionary = _fixture()
	nogoods["owned_markets"][0]["stock"]["ice"] = NAN
	var bad: Dictionary = Domain.domain_from_native(nogoods,goal,[])
	_check(bad.get("error","") == "invalid_stock","NaN stock refused",failures)
	var empty: Dictionary = Bridge.goal_from_head({"selected_option":"wait"})
	_check(empty.is_empty(),"no free head objective without real shortage",failures)
	_check(Native.projected_native_target(10,10).get("error","") == "native_goal_already_met",
		"recovery absolute stock milestone never drifts +10",failures)
	var blocked_plan: Dictionary = {"status":"Ready","goal_id":"supply:tau:water",
		"steps":[{"step_id":"one","action_id":"imaginary","depends_on":[]}],
		"forecast_credits":0,"forecast_ticks":0,"nodes_expanded":1}
	_check(Validate.validate_plan(snapshot,goal,[],blocked_plan,
		{"max_nodes":350,"max_depth":12}).get("error","") == "UnknownAction",
		"shared validator refuses forged plan step",failures)
	return {"passed":failures.is_empty(),"failures":failures,
		"runtime_executed":false,"fixtures_authored":14}

static func _check(ok: bool, label: String, failures: Array[String]) -> void:
	if not ok:
		failures.append(label)
