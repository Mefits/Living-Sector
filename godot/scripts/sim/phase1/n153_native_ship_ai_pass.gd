extends RefCounted
## Frozen Rust agents/ship/behavior.rs::decide_and_act and plan_goal.
## Phase1 snapshot projection ONLY; this is not a parallel Godot ECS.
## Phase2 must use N80 scored candidates/replan, N81 GOAP, N84 behavior
## tree, N88/N90 leaves and N146 command buffer exactly once per ship.
const Plans = preload("res://scripts/sim/phase1/n153_native_ship_bt_planning.gd")
const Contracts = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const TIER_BIO_WEIGHT := 100.0
const TIER_HOUSEKEEPING_WEIGHT := 40.0
const TIER_STRATEGIC_WEIGHT := 3.0
const TIER_EXPLORE_WEIGHT := 6.0
const TIER_IDLE_FLOOR := 0.5
const FUEL_URGENCY_ONSET := 0.45
const REPLAN_MIN_COMMIT_TICKS := 40
const REPLAN_SCORE_RATIO := 1.30
const CONTRACT_OBLIGATION_WEIGHT := 0.5
const LOYALTY_REPLAN_MULTIPLIER := 0.5

static func _action(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result: Dictionary = fields.duplicate(true)
	result["kind"] = kind
	return result

static func _candidate(name: String, score: float, request: Dictionary = {}, leaves: Array = []) -> Dictionary:
	return {"name": name, "score": score, "plan_request": request, "leaves": leaves}

static func _idle() -> Dictionary:
	return _candidate("idle", TIER_IDLE_FLOOR, {}, [_action("Idle")])

static func _score_strategic(profit: int, goal: String, personality: Dictionary, contested: bool) -> float:
	# Same source formula as N80; authoritative Phase2 scorer is N80.
	if profit <= 0:
		return 0.0
	var favorite: float = float(personality.get("prefer_goals", {}).get(goal, 0.0))
	var aggression: float = float(personality.get("aggression", 0.0))
	var contested_bonus: float = aggression * 0.4 if contested and aggression > 0.5 else 0.0
	return log(maxf(1.0, float(profit))) * (1.0 + favorite + contested_bonus) * maxf(0.3, float(personality.get("profit", 0.0))) * TIER_STRATEGIC_WEIGHT

static func _best_candidate(candidates: Array) -> Dictionary:
	var best: Dictionary = _idle()
	if candidates.is_empty():
		return best
	best = candidates[0]
	for index in range(1, candidates.size()):
		var c: Dictionary = candidates[index]
		# Rust std::iter::Iterator::max_by selects the LAST equal
		# candidate (although the frozen prose comment says earliest).
		if float(c.get("score", 0.0)) >= float(best.get("score", 0.0)):
			best = c
	return best

static func _has_bt(candidate: Dictionary) -> bool:
	return not candidate.get("plan_request", {}).is_empty() or not candidate.get("leaves", []).is_empty()

static func build_goal_candidates(ship: Dictionary, observed: Dictionary) -> Array:
	## All observed fields are read-only authoritative snapshots. N153 does
	## not compute physical trade prices, contract payouts or assign builders.
	var location: String = str(ship.get("location", ""))
	if location.is_empty():
		return [_idle()]
	var personality: Dictionary = ship.get("personality", {})
	var fuel_fraction: float = clampf(float(ship.get("fuel_fraction", 0.0)), 0.0, 1.0)
	var fuel_bucket: int = int(ship.get("fuel_bucket", -1))  # N81 original
	var routes: Dictionary = observed.get("routes", {})
	var systems: Dictionary = observed.get("system_by_location", {})
	var congestion: Dictionary = observed.get("dock_congestion", {})
	var candidates: Array = []
	if ship.has("crew_morale") and float(ship["crew_morale"]) < 15.0 and Plans.any_rest_destination_viable(location, congestion, systems):
		var morale: float = float(ship["crew_morale"])
		var urgency: float = clampf(1.0 - morale / 15.0, 0.0, 1.0)
		var score: float = urgency * maxf(0.2, float(personality.get("morale", 0.0))) * TIER_BIO_WEIGHT
		var target: String = Plans.pick_rest_destination(location, congestion, systems)
		var plan: Dictionary = Plans.plan_request("rest_crew", {"current": location, "source": location,
			"destination": target, "fuel_bucket": fuel_bucket}, routes)
		if not plan.is_empty():
			candidates.append(_candidate("rest_crew", score, plan))
	if fuel_fraction < FUEL_URGENCY_ONSET:
		var urgency: float = clampf(1.0 - fuel_fraction / FUEL_URGENCY_ONSET, 0.0, 1.0)
		var score: float = urgency * maxf(0.2, float(personality.get("safety", 0.0))) * TIER_BIO_WEIGHT
		candidates.append(_candidate("refuel", score, {}, [
			_action("Dock"), _action("DockDwell", {"seconds": 2}), _action("Refuel"),
			_action("DockDwell", {"seconds": 2}), _action("Undock")]))
	# A station-issued assignment short-circuits every nonbiological goal.
	# An assigned carrier has priority even if it has low public reputation.
	var assigned: bool = observed.get("has_assigned_delivery", false) == true
	if assigned:
		var duty: Dictionary = observed.get("contract_candidate", {})
		if not duty.is_empty() and _has_bt(duty):
			candidates.append(_candidate(str(duty.get("goal_name", "fulfill_delivery")), 35.0,
				duty.get("plan_request", {}), duty.get("leaves", [])))
		else:
			candidates.append(_candidate("idle_station_order", TIER_IDLE_FLOOR, {}, [_action("Idle")]))
		return candidates
	var cargo_used: int = int(ship.get("cargo_used", 0))
	var cargo_capacity: int = maxi(1, int(ship.get("cargo_capacity", 0)))
	var sell_to: String = str(observed.get("liquidation_market", ""))
	if cargo_used > 0 and not sell_to.is_empty():
		var scale: float = 0.5 + clampf(float(cargo_used) / float(cargo_capacity), 0.0, 1.0) * 0.5
		var leaves: Array = []
		if location != sell_to:
			leaves.append(_action("Undock"))
			leaves.append_array(Plans.route_actions(location, sell_to, routes))
		leaves.append_array([_action("Dock"), _action("DockDwell", {"seconds": 2}),
			_action("SellAll"), _action("DockDwell", {"seconds": 2}), _action("Undock")])
		candidates.append(_candidate("sell_cargo", scale * maxf(0.3, float(personality.get("profit", 0.0))) * TIER_HOUSEKEEPING_WEIGHT, {}, leaves))
	var retrofit: Dictionary = observed.get("retrofit_plan", {})
	if not retrofit.is_empty():
		var spec: Dictionary = Plans.plan_request("retrofit", {"current": location, "source": location,
			"destination": location, "fuel_bucket": fuel_bucket, "retrofit": retrofit}, routes)
		if not spec.is_empty():
			candidates.append(_candidate("seek_retrofit",
				0.9 * maxf(0.3, float(personality.get("profit", 0.0))) * TIER_HOUSEKEEPING_WEIGHT, spec))
	var contested: Dictionary = observed.get("contested_destinations", {})
	var market_priority: Dictionary = observed.get("own_market_priority", {})
	var contract: Dictionary = observed.get("contract_candidate", {})
	if not contract.is_empty() and _has_bt(contract):
		var name: String = str(contract.get("goal_name", "fulfill_delivery"))
		var destination: String = str(contract.get("destination", ""))
		var score: float = _score_strategic(int(contract.get("profit", 0)), name,
			personality, bool(contested.get(destination, false)))
		score *= float(market_priority.get(destination, 1.0))
		if bool(contract.get("own_strategy", false)):
			score *= 1.0 + clampf(float(personality.get("loyalty", 0.0)), 0.0, 1.0)
		if not retrofit.is_empty() and contract.get("delivery_params", null) is Dictionary:
			var dp: Dictionary = contract["delivery_params"]
			var combo: Dictionary = Plans.plan_request("delivery_retrofit", {
				"current": location, "source": dp.get("source", ""), "destination": dp.get("destination", ""),
				"commodity": dp.get("commodity", ""), "quantity": dp.get("quantity", 0),
				"contract_id": dp.get("contract_id", ""), "fuel_bucket": fuel_bucket, "retrofit": retrofit
			}, routes)
			if not combo.is_empty():
				var combo_score: float = score * 1.2 + _score_strategic(int(int(retrofit.get("cost", 0)) / 5),
					"seek_retrofit", personality, false)
				candidates.append(_candidate("fulfill_delivery_with_retrofit", combo_score, combo))
		candidates.append(_candidate(name, score, contract.get("plan_request", {}), contract.get("leaves", [])))
	var trade: Dictionary = observed.get("trade_candidate", {})
	if not trade.is_empty() and _has_bt(trade):
		var buy_loc: String = str(trade.get("buy_loc", ""))
		var sell_loc: String = str(trade.get("sell_loc", ""))
		var bias: float = (float(market_priority.get(buy_loc, 1.0)) + float(market_priority.get(sell_loc, 1.0))) / 2.0
		var score: float = _score_strategic(int(trade.get("profit", 0)), "trade_run",
			personality, bool(contested.get(buy_loc, false)) or bool(contested.get(sell_loc, false))) * bias
		if not retrofit.is_empty():
			var combo: Dictionary = Plans.plan_request("trade_run_retrofit", {
				"current": location, "source": buy_loc, "destination": sell_loc,
				"commodity": trade.get("commodity", ""), "quantity": 50,
				"fuel_bucket": fuel_bucket, "retrofit": retrofit
			}, routes)
			if not combo.is_empty():
				var combo_score: float = score * 1.2 + _score_strategic(int(int(retrofit.get("cost", 0)) / 5),
					"seek_retrofit", personality, false)
				candidates.append(_candidate("trade_run_with_retrofit", combo_score, combo))
		candidates.append(_candidate("trade_run", score, trade.get("plan_request", {}), trade.get("leaves", [])))
	# Source idle/explore escalation is in N80; N153 converts a proved
	# exploration route into actual BT leaves. All truthy gates N80-owned.
	var exploration: bool = observed.get("should_explore", false) == true
	var found_explore_route: bool = false
	if exploration:
		var explore_leaves: Array = Plans.explore_plan(location,
			ship.get("recent_systems", []), observed.get("gate_pairs_order", []),
			systems, observed.get("registry_order", []), routes)
		if not explore_leaves.is_empty():
			found_explore_route = true
			candidates.append(_candidate("explore", maxf(0.2, float(personality.get("exploration", 0.0))) * TIER_EXPLORE_WEIGHT, {}, explore_leaves))
	if not found_explore_route:
		var station_leaves: Array = Plans.idle_seek_station(location,
			bool(ship.get("docked", false)), str(ship.get("loc_type", "")),
			observed.get("registry_order", []), systems, routes)
		if not station_leaves.is_empty():
			candidates.append(_candidate("idle_seek_station", 0.8 * TIER_EXPLORE_WEIGHT, {}, station_leaves))
	candidates.append(_idle())
	return candidates

static func candidate_from_sources(ship: Dictionary, observed: Dictionary) -> Dictionary:
	var choices: Array = build_goal_candidates(ship, observed)
	var result: Dictionary = _best_candidate(choices)
	# The mining-only (N103) and engineering (N91) policies have source-
	# native score comparisons in decide_and_act, after plan_goal.
	var mine: Dictionary = observed.get("mining_candidate", {})
	if str(ship.get("class", "")) == "miner" and str(ship.get("active_contract_id", "")).is_empty() and not mine.is_empty():
		if float(mine.get("score", 0.0)) > float(result.get("score", 0.0)):
			result = mine
	var builder: Dictionary = observed.get("construction_candidate", {})
	if not builder.is_empty() and builder.get("n91_admitted", false) == true:
		var score: float = float(builder.get("score", -1.0))
		if score >= 0.0 and _has_bt(builder):
			result = builder
	return result

static func decide_pre_bt(ship_snapshot: Dictionary, observed: Dictionary) -> Dictionary:
	## Return updated private snapshot + ordered SimCommand proposals and a
	## BT-tick permission. No command is applied here. Caller N146 sorts by
	## actor entity bits after all ships, never by string ID.
	var ship: Dictionary = ship_snapshot.duplicate(true)
	var commands: Array = []
	if observed.get("lod_fired", false) != true:
		return {"ship": ship, "commands": commands, "tick_bt": false, "reason": "lod_skip"}
	if bool(ship.get("in_transit", false)):
		return {"ship": ship, "commands": commands, "tick_bt": false, "reason": "transit"}
	var contract_id: String = str(ship.get("active_contract_id", ""))
	var held: Dictionary = observed.get("held_contract", {})
	if not contract_id.is_empty():
		if held.is_empty() or str(held.get("id", "")) != contract_id or str(held.get("fulfiller_id", "")) != str(ship.get("id", "")) or not (str(held.get("status", "")) in ["Accepted", "PickedUp"]):
			ship["active_contract_id"] = ""
			ship["current_bt"] = null
			ship["transaction_pending"] = null
			ship["dirty"] = true
		elif ship.get("current_bt", null) == null:
			var request: Dictionary = Plans.resume_contract_request(
				str(ship.get("location", "")), bool(ship.get("docked", false)),
				ship.get("cargo", {}), int(ship.get("fuel_bucket", -1)),
				held, observed.get("routes", {}))
			ship["current_bt"] = request if not request.is_empty() else {"leaves": [_action("Idle")]}
			match str(held.get("contract_type", "")):
				"CrewMission": ship["current_goal"] = "do_crew_mission"
				"Passenger": ship["current_goal"] = "fulfill_passenger_transport"
				"Construction": ship["current_goal"] = "fulfill_construction"
				_: ship["current_goal"] = "fulfill_delivery"
			ship["last_plan_tick"] = int(observed.get("tick", 0))
			ship["transaction_pending"] = null
			ship["dirty"] = true
	if str(ship.get("current_goal", "")) == "construct" and observed.get("construction_target_valid", false) != true:
		ship["current_bt"] = null
	var assigned: bool = observed.get("has_assigned_delivery", false) == true
	var assigned_builder: bool = observed.get("has_assigned_builder", false) == true
	var goal: String = str(ship.get("current_goal", ""))
	if (assigned or assigned_builder) and str(ship.get("active_contract_id", "")).is_empty() and ship.get("transaction_pending", null) == null:
		if not goal.begins_with("fulfill_") and not (goal in ["construct", "refuel", "rest_crew"]):
			ship["current_bt"] = null
	var needs_plan: bool = ship.get("current_bt", null) == null
	var due: bool = observed.get("n80_replan_check_due", false) == true
	# N80's per-id FNV schedule/40-tick dwell/eligible goals exclusively
	# determines this input; never create a second scheduler.
	due = due and not needs_plan and ship.get("transaction_pending", null) == null and not assigned_builder
	due = due and not (assigned and not str(ship.get("active_contract_id", "")).is_empty())
	if needs_plan or due:
		var candidate: Dictionary = candidate_from_sources(ship, observed)
		var current_score: float = float(ship.get("current_goal_score", 0.0))
		var loyalty: float = clampf(float(ship.get("personality", {}).get("loyalty", 0.0)), 0.0, 1.0)
		var ratio: float = REPLAN_SCORE_RATIO
		if not str(ship.get("active_contract_id", "")).is_empty():
			ratio += CONTRACT_OBLIGATION_WEIGHT + loyalty * LOYALTY_REPLAN_MULTIPLIER
		if needs_plan or float(candidate.get("score", 0.0)) >= current_score * ratio:
			ship["transaction_pending"] = null
			if due and not str(ship.get("active_contract_id", "")).is_empty():
				commands.append({"kind": "ReleaseContract", "ship_id": str(ship.get("id", "")),
					"contract_id": str(ship["active_contract_id"]), "reason": "replan"})
				ship["active_contract_id"] = ""
			ship["current_goal"] = str(candidate.get("name", "idle"))
			ship["current_goal_score"] = float(candidate.get("score", TIER_IDLE_FLOOR))
			ship["current_bt"] = candidate
			ship["last_plan_tick"] = int(observed.get("tick", 0))
	if str(ship.get("current_goal", "")).begins_with("idle"):
		ship["idle_ticks"] = mini(4294967295, int(ship.get("idle_ticks", 0)) + 1)
	else:
		ship["idle_ticks"] = 0
	# Source strike/retirement is *only* N148, not duplicated here.
	ship["dirty"] = true
	return {"ship": ship, "commands": commands, "tick_bt": ship.get("current_bt", null) != null, "reason": "ready"}

static func apply_bt_result(ship_snapshot: Dictionary, status: String, blackboard: Dictionary, observed: Dictionary) -> Dictionary:
	## N84 executes one BT step; N88/N90 return receipts. Apply source
	## completion/failure cleanup after execution, never before.
	var ship: Dictionary = ship_snapshot.duplicate(true)
	var commands: Array = []
	var pending: Dictionary = ship.get("transaction_pending", {}) if ship.get("transaction_pending", null) is Dictionary else {}
	if str(pending.get("request_kind", "")) == "Accept" and pending.has("result"):
		var cid: String = str(pending.get("contract_id", ""))
		if str(pending.get("result", "")) == "error":
			# B1 cooldown only when quote+escrow/status key stays unchanged.
			var rejects: Dictionary = ship.get("contract_rejections", {}).duplicate(true)
			rejects[cid] = {"reason": pending.get("error", ""), "key": observed.get("funding_key", ""),
				"until_tick": int(observed.get("tick", 0)) + REPLAN_MIN_COMMIT_TICKS}
			ship["contract_rejections"] = rejects
		elif str(pending.get("result", "")) == "ok":
			var rejects: Dictionary = ship.get("contract_rejections", {}).duplicate(true)
			rejects.erase(cid)
			ship["contract_rejections"] = rejects
	if bool(blackboard.get("rest_timed_out", false)):
		# N86 personality.drift is the authoritative receiver of +0.02.
		ship["drift_safety_intent"] = 0.02
	if status in ["Success", "Failure"]:
		ship["current_bt"] = null
		ship["transaction_pending"] = null
		if status == "Failure" and not str(ship.get("active_contract_id", "")).is_empty():
			var reason: String = str(pending.get("error", ""))
			var issuer_failure: bool = reason in ["insufficient_contract_funding", "missing_contract_payer", "invalid_prepaid_amount"]
			commands.append({"kind": "ReleaseContract", "ship_id": str(ship.get("id", "")),
				"contract_id": str(ship["active_contract_id"]), "reason": "issuer_funding_failure" if issuer_failure else "bt_failure"})
			ship["active_contract_id"] = ""
	ship["dirty"] = true
	return {"ship": ship, "commands": commands}
