extends RefCounted
## N100 source-parity fixtures: authored but NOT EXECUTED in Phase 1.
## Execute only after N155 and N99 scripts are combined in Phase 2.
const Hybrid = preload("res://scripts/sim/phase1/n100_hybrid_planner.gd")
const N155_DOMAIN := "res://scripts/sim/phase1/n155_native_domain.gd"
const N99_BEAM := "res://scripts/sim/phase1/n99_control_beam.gd"
const N155_HTN := "res://scripts/sim/phase1/n155_htn_methods.gd"
const N155_GOAP := "res://scripts/sim/phase1/n155_telic_goap_shadow.gd"
const N155_VALIDATOR := "res://scripts/sim/phase1/n155_planning_validation.gd"

static func _fixture() -> Dictionary:
	var snapshot: Dictionary = {
		"schema_version":1,"tick":100,"faction_id":"f",
		"treasury_credits":30000,"treasury_floor_credits":10000,
		"owned_markets":[
			{"market_id":"belt","facility_id":"facility-belt",
				"location_id":"belt","stock":{"ice":8.0},"demand":{},"prices":{}},
			{"market_id":"refinery","facility_id":"facility-refinery",
				"location_id":"colony","stock":{"water":0.0},"demand":{},"prices":{}}],
		"facilities":[{"facility_id":"facility-refinery",
			"location_id":"colony","facility_type":"refinery"}],
		"ships":[{"ship_id":"ship","class":"courier","location_id":"belt",
			"in_transit":false,"free_cargo":20,"fuel":100.0}],
		"active_commitments":[],"technologies":[],
		"recipes":[{"recipe_id":"ice","facility_type":"refinery",
			"inputs":[["ice",8]],"outputs":[["water",10]]}]}
	var goal: Dictionary = {"goal_id":"water","destination_id":"colony",
		"commodity":"water","target_units":10,"priority":100}
	var actions: Array = [
		{"action_id":"deliver-ice","kind":"deliver","source_id":"belt",
			"destination_id":"colony","commodity":"ice","units":8,
			"cost_credits":200,"expected_ticks":80,"inputs":[],
			"outputs":[],"required_facility_type":null},
		{"action_id":"refine","kind":"produce","source_id":null,
			"destination_id":"colony","commodity":"water","units":10,
			"cost_credits":100,"expected_ticks":40,"inputs":[["ice",8]],
			"outputs":[["water",10]],"required_facility_type":"refinery"}]
	return {"snapshot":snapshot,"goal":goal,"actions":actions,
		"budget":{"max_nodes":2000,"max_depth":12}}

static func _ready(result: Dictionary) -> bool:
	return result.get("status","") == "Ready"

static func run_source_parity_fixtures() -> Dictionary:
	var split: Dictionary = Hybrid.split_budget({"max_nodes":15,"max_depth":12})
	assert(int(split["htn"]["max_nodes"]) + int(split["goap"]["max_nodes"]) + int(split["beam"]["max_nodes"]) == 15)
	assert(Hybrid.split_budget({"max_nodes":2,"max_depth":12}).has("error"))
	var bounded: Dictionary = Hybrid.bounded_preferences({
		"cost_weight":NAN,"speed_weight":INF,"caution_weight":-8.0})
	assert(bounded == {"cost_weight":1.0,"speed_weight":1.0,"caution_weight":0.1})
	# The same alternatives must respond to the *existing* Director's weights.
	var cheap: Dictionary = {"steps":[{"action_id":"deliver-ice"}],
		"forecast_credits":400,"forecast_ticks":600}
	var fast: Dictionary = {"steps":[{"action_id":"deliver-ice"}],
		"forecast_credits":7000,"forecast_ticks":50}
	assert(Hybrid.score(cheap,[],{"cost_weight":4.0,"speed_weight":0.2,"caution_weight":0.5})
		< Hybrid.score(fast,[],{"cost_weight":4.0,"speed_weight":0.2,"caution_weight":0.5}))
	assert(Hybrid.score(fast,[],{"cost_weight":0.2,"speed_weight":5.0,"caution_weight":0.5})
		< Hybrid.score(cheap,[],{"cost_weight":0.2,"speed_weight":5.0,"caution_weight":0.5}))
	if not ResourceLoader.exists(N155_DOMAIN) or not ResourceLoader.exists(N99_BEAM) or not ResourceLoader.exists(N155_HTN) or not ResourceLoader.exists(N155_GOAP) or not ResourceLoader.exists(N155_VALIDATOR):
		return {"status":"NOT_RUN_DEPENDENCIES_NOT_ASSEMBLED",
			"reason":"N155 HTN/GOAP/domain/validator and N99 are separate Draft PRs"}
	var f: Dictionary = _fixture()
	var before: String = JSON.stringify(f["snapshot"])
	var decision: Dictionary = Hybrid.decide(f["snapshot"],f["goal"],f["actions"],f["budget"])
	assert(_ready(decision["result"]))
	assert(decision["roles"]["goap_role"] == "htn_ingredient_subgoal_and_full_goal")
	assert(decision["roles"]["selected_source"] == "htn_plus_telic_goap")
	assert(decision["roles"]["beam_status"] == null)
	var path: Array = []
	for step in decision["result"]["steps"]:
		path.append(step["action_id"])
	assert(path == ["deliver-ice","refine"])
	assert(JSON.stringify(f["snapshot"]) == before)
	assert(decision["result"]["native_dispatch_authorized"] == false)
	var depleted: Dictionary = _fixture()
	depleted["snapshot"]["owned_markets"][0]["stock"]["ice"] = 0.0
	assert(not _ready(Hybrid.plan(depleted["snapshot"],depleted["goal"],
		depleted["actions"],depleted["budget"])))
	var no_ship: Dictionary = _fixture()
	no_ship["snapshot"]["ships"][0]["free_cargo"] = 2
	assert(not _ready(Hybrid.plan(no_ship["snapshot"],no_ship["goal"],
		no_ship["actions"],no_ship["budget"])))
	var committed: Dictionary = _fixture()
	committed["snapshot"]["active_commitments"].append({"assigned_ship_id":"ship"})
	assert(not _ready(Hybrid.plan(committed["snapshot"],committed["goal"],
		committed["actions"],committed["budget"])))
	var poor: Dictionary = _fixture()
	poor["snapshot"]["treasury_credits"] = 10050
	assert(not _ready(Hybrid.plan(poor["snapshot"],poor["goal"],
		poor["actions"],poor["budget"])))
	var ambiguous: Dictionary = _fixture()
	ambiguous["snapshot"]["owned_markets"].append({
		"market_id":"another","facility_id":"another-facility",
		"location_id":"colony","stock":{"water":100.0}})
	assert(not _ready(Hybrid.plan(ambiguous["snapshot"],ambiguous["goal"],
		ambiguous["actions"],ambiguous["budget"])))
	# NativeDomain's departure-slot count alone is insufficient when two
	# jobs require the one large ship, even if another tiny ship is idle.
	var distinct: Dictionary = _fixture()
	distinct["snapshot"]["ships"].append({"ship_id":"tiny","class":"courier",
		"location_id":"belt","in_transit":false,"free_cargo":1,"fuel":100.0})
	assert(not bool(Hybrid._carrier_assignment(distinct["snapshot"],distinct["actions"],
		[{"action_id":"deliver-ice"},{"action_id":"deliver-ice"}])["ok"]))
	var tight: Dictionary = _fixture()
	tight["budget"]["max_nodes"] = 15
	var limited: Dictionary = Hybrid.decide(tight["snapshot"],tight["goal"],
		tight["actions"],tight["budget"])
	assert(int(limited["result"]["nodes_expanded"]) <= 15)
	var fake: Dictionary = decision["result"].duplicate(true)
	fake["steps"][0]["action_id"] = "magic-ice"
	var domain_tool: Variant = load(N155_DOMAIN)
	var validator_tool: Variant = load("res://scripts/sim/phase1/n155_planning_validation.gd")
	var domain: Dictionary = domain_tool.callv("domain_from_native",
		[f["snapshot"],f["goal"],f["actions"]])
	var replay: Dictionary = Hybrid._safe_candidate(domain,f["snapshot"],f["goal"],
		f["actions"],fake,f["budget"],domain_tool,validator_tool)
	assert(not bool(replay["ok"]))
	return {"status":"PASSED","fixtures":11,"native_execution":"NEVER_INVOKED"}
