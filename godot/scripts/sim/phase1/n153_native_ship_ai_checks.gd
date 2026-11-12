extends RefCounted
## Bounded source-derived fixtures for Phase2. Authored but NOT RUN in Phase1.
const Contract = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const Pass = preload("res://scripts/sim/phase1/n153_native_ship_ai_pass.gd")

static func run_checks() -> Dictionary:
	var failures: Array[String] = []
	_check(Contract.median_known_price({
		"a": {"Ice": {"price": 10.0}}, "b": {"Ice": {"price": 30.0}}
	}, "Ice") == 30.0, "upper median for even price observations", failures)
	_check(Contract.median_known_price({}, "Ice") == null, "no fabricated price", failures)
	var congested: Dictionary = {"port": {"capacity": 10, "docked": 0, "queued": 30}}
	_check(Contract.contract_queue_saturated("port", congested), "3x queued contract gate", failures)
	_check(not Contract.contract_queue_saturated("missing", congested), "unknown congestion does not block", failures)
	_check(Plans.location_saturated({"capacity": 10, "docked": 8, "queued": 4}), "1.2x shore leave gate", failures)
	_check(not Plans.location_saturated({"capacity": 10, "docked": 4, "queued": 2}), "shore leave viable", failures)
	_check(Plans.fuel_fraction_to_bucket(0.55) == 6, "rounded 0.55 fuel bucket", failures)
	_check(Plans.fuel_fraction_to_bucket(-0.1) == 0, "fuel <= 0 bucket zero", failures)
	_check(Plans.fuel_bucket_cost("a", "b", {}) == 1, "no route fuel bucket fallback", failures)
	_check(Plans.fuel_bucket_cost("a", "a", {}) == 0, "same location no fuel cost", failures)
	var offer: Dictionary = {
		"id": "c1", "source_location": "a", "destination_location": "b",
		"status": "Posted", "contract_type": "Passenger", "quantity": 5,
		"commodity": "Food", "may_accept": true, "requestor_id": "f",
		"faction_id": "f"
	}
	var base: Dictionary = {
		"offers": [offer], "quotes": {"c1": {
			"valid": true, "quoted_payment": 400, "top_up": 200,
			"payer_balance": 0, "fixed_strategy_reward": 400,
			"reserved": 400
		}}, "ship_id": "s", "ship_faction": "f",
		"ship_location": "a", "credits": 500, "cargo_capacity": 10,
		"sensor_range_au": 1.0,
		"commerce_allowed": {"f": true},
		"controllers": {"a": "f", "b": "f"},
		"system_by_location": {"a": "sol", "b": "tau"}
	}
	_check(Contract.select_contract(base).is_empty(), "no acceptance without payer top-up", failures)
	base["quotes"]["c1"]["payer_balance"] = 300
	_check(Contract.select_contract(base).is_empty(), "unassigned cross-system short sensor", failures)
	base["assigned"] = offer
	_check(not Contract.select_contract(base).is_empty(), "assigned funded order bypasses short sensors", failures)
	base["dock_congestion"] = {"b": {"capacity": 10, "docked": 3, "queued": 30}}
	_check(Contract.select_contract(base).is_empty(), "pre-accept queue congestion", failures)
	var courier: Dictionary = {"id": "c2", "contract_type": "Courier",
		"quantity": 8, "commodity": "Food", "source_location": "a",
		"destination_location": "b", "status": "PickedUp"}
	_check(Plans.resume_contract_request("a", false, {}, 7, courier, {}).is_empty(),
		"no courier phantom cargo on recovery", failures)
	var compiled: Array = Plans.compile_plan_to_bt_actions(
		[{"kind": "Travel", "destination": "b"}, {"kind": "Dock"}, {"kind": "Undock"}],
		{"origin": "a", "contract_id": "c4"}, {}, true)
	_check(compiled.size() > 0 and compiled[0]["kind"] != "AcceptContract",
		"no duplicate accept after restart", failures)
	var at_sea: Dictionary = {"id": "s", "in_transit": true, "current_goal": "fulfill_delivery"}
	var skipped: Dictionary = Pass.decide_pre_bt(at_sea, {"lod_fired": true, "tick": 200})
	_check(skipped["tick_bt"] == false, "no BT ticking while in transit", failures)
	var skipped_lod: Dictionary = Pass.decide_pre_bt({"id": "s"}, {"lod_fired": false})
	_check(skipped_lod["tick_bt"] == false, "LOD sleep preserves BT", failures)
	var completed: Dictionary = Pass.apply_bt_result({
		"id": "s", "active_contract_id": "c5", "transaction_pending": {
			"error": "insufficient_contract_funding", "result": "error"
		}}, "Failure", {}, {"tick": 300})
	_check(completed["commands"].size() == 1 and completed["commands"][0]["reason"] == "issuer_funding_failure",
		"payer failure is not carrier contract breach", failures)
	return {"passed": failures.is_empty(), "failures": failures,
		"fixtures": 17, "runtime_executed": false}

static func _check(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(label)
