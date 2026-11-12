extends RefCounted
## N143: native Rust director.rs::observe research slice + governance.rs.
## No technology is granted here. This is a side-effect-free projection
## over the N82 frozen TECHNOLOGIES catalogue supplied by Phase-2 adapter.
## Source: archive/rust-galaxy-067-reference (sim_core strategy/director,
## governance, charter). Never invent a new T4 science tree in Phase 1.

const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1
const MANDATE_MODES := ["delegated", "advise", "hold"]
const CHARTER_AUTHORITIES := ["delegated", "review", "autonomous"]

static func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func catalogue_map(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		if not (row is Dictionary):
			return {}
		var id = row.get("id")
		if not (id is String) or str(id).is_empty() or result.has(id):
			return {}
		if not (row.get("field") is String) or not (str(row["field"]) in ["industry", "science", "expansion"]):
			return {}
		if typeof(row.get("work")) != TYPE_INT or int(row["work"]) <= 0:
			return {}
		var prior = row.get("prerequisite", "")
		if not (prior is String):
			return {}
		result[id] = row.duplicate(true)
	for id in result:
		var req: String = str(result[id].get("prerequisite", ""))
		if req != "" and not result.has(req):
			return {}
	return result

static func has(completed: Array, technology: String) -> bool:
	return completed.has(technology)

static func production_bonus(completed: Array) -> int:
	## director.rs::production_bonus. Physical production consumes its
	## original input via N39, not a free grant from this helper.
	return int(has(completed, "industrial_methods")) + int(has(completed, "automation"))

static func next_technology(target: String, completed: Array, catalogue: Dictionary) -> Dictionary:
	## governance.rs::next_technology. If a saved state already knows the
	## target, returns no further work. Prerequisites form a single chain.
	if not catalogue.has(target):
		return _error("unknown_technology")
	var next: String = target
	for _i in range(catalogue.size()):
		if completed.has(next):
			return {"ok": true, "next": "", "work": 0}
		var previous: String = str(catalogue[next].get("prerequisite", ""))
		if previous != "" and not completed.has(previous):
			if not catalogue.has(previous):
				return _error("invalid_technology_graph")
			next = previous
			continue
		return {"ok": true, "next": next,
			"work": int(catalogue[next]["work"]), "field": str(catalogue[next]["field"])}
	return _error("technology_dependency_cycle")

static func _active_mandate(mandate: Dictionary, completed: Array) -> bool:
	## governance.rs::active = Hold OR not completed.
	if mandate.is_empty():
		return false
	return str(mandate.get("mode", "")) == "hold" or not completed.has(str(mandate.get("target_technology", "")))

static func validate_mandate(mandate: Dictionary, catalogue: Dictionary) -> String:
	if not (mandate.get("mode") is String) or str(mandate["mode"]) not in MANDATE_MODES:
		return "invalid_mandate_mode"
	if typeof(mandate.get("budget_ceiling_cr")) != TYPE_INT:
		return "invalid_mandate_budget"
	var budget: int = int(mandate["budget_ceiling_cr"])
	if budget < 100 or budget > 1000000000:
		return "invalid_mandate_budget"
	if typeof(mandate.get("treasury_floor_cr")) != TYPE_INT:
		return "invalid_treasury_floor"
	var floor_cr: int = int(mandate["treasury_floor_cr"])
	if floor_cr < 10000 or floor_cr > 1000000000:
		return "invalid_treasury_floor"
	if not catalogue.has(str(mandate.get("target_technology", ""))):
		return "unknown_technology"
	if typeof(mandate.get("spent_cr", 0)) != TYPE_INT:
		return "invalid_committed_amount"
	var spent: int = int(mandate.get("spent_cr", 0))
	if spent < 0 or spent > budget:
		return "invalid_committed_amount"
	return ""

static func update_mandate(old: Dictionary, incoming: Dictionary, tick: int, catalogue: Dictionary) -> Dictionary:
	## governance.rs::inherit_approved_budget and set_mandate. No state
	## changes until the native Director resource confirms the replacement.
	if tick < 0:
		return _error("invalid_tick")
	var next := incoming.duplicate(true)
	if not old.is_empty() and old.get("target_technology") == incoming.get("target_technology"):
		next["spent_cr"] = old.get("spent_cr", 0)
		next["created_tick"] = old.get("created_tick", 0)
		next["last_reason"] = "player_policy_updated_preserving_spend"
	else:
		next["spent_cr"] = 0
		next["created_tick"] = tick
		next["last_reason"] = "approved_in_native_director"
	var err := validate_mandate(next, catalogue)
	if err != "":
		return _error(err)
	return {"ok": true, "reason": "", "mandate": next}

static func _select_autonomous(completed: Array, profile: Dictionary, rows: Array) -> Dictionary:
	## director.rs::observe; highest field profile weight, then smallest
	## lexical technology id on ties, no calendar-era release gates.
	var chosen := {}
	var best_score := -INF
	for row in rows:
		if completed.has(str(row["id"])):
			continue
		var previous: String = str(row.get("prerequisite", ""))
		if previous != "" and not completed.has(previous):
			continue
		var score: float = float(profile.get(str(row["field"]), 0.0))
		if not is_finite(score):
			continue
		if chosen.is_empty() or score > best_score or (score == best_score and str(row["id"]) < str(chosen["id"])):
			chosen = row
			best_score = score
	return chosen

static func observe_research(commander: Dictionary, mandate: Dictionary, charter: Dictionary, catalogue_rows: Array) -> Dictionary:
	## Called after native faction/market/population observation. The full
	## head's crisis/goal portfolio is owned by N134; only science fields
	## change here and only when native director.rs would change them.
	var catalogue := catalogue_map(catalogue_rows)
	if catalogue.is_empty():
		return _error("invalid_technology_catalogue")
	var updated := commander.duplicate(true)
	var completed: Array = updated.get("technologies", [])
	if not (updated.get("technologies", []) is Array) or not (updated.get("profile") is Dictionary):
		return _error("invalid_commander_science")
	if not mandate.is_empty() and validate_mandate(mandate, catalogue) != "":
		return _error("invalid_mandate")
	var can_direct: bool = charter.is_empty() or str(charter.get("research_authority", "delegated")) != "autonomous"
	var progress: int = int(updated.get("progress", 0))
	var research: String = str(updated.get("research", ""))
	if not mandate.is_empty() and str(mandate.get("mode", "")) == "delegated" and can_direct 			and _active_mandate(mandate, completed) and progress == 0:
		var next := next_technology(str(mandate["target_technology"]), completed, catalogue)
		if bool(next.get("ok", false)) and str(next.get("next", "")) != "":
			if research != str(next["next"]):
				research = str(next["next"])
				updated["research"] = research
				updated["research_required"] = int(next["work"])
				updated["progress"] = 0
	# The native Director only replaces a missing research target. It must
	# NOT erase partially paid science when a mandate changes.
	if research == "":
		var chosen := _select_autonomous(completed, updated.get("profile", {}), catalogue_rows)
		if not chosen.is_empty():
			updated["research"] = str(chosen["id"])
			updated["research_required"] = int(chosen["work"])
			updated["progress"] = 0
	return {"ok": true, "reason": "", "commander": updated}

static func _charter_gate(charter: Dictionary, amount: int, treasury: int) -> String:
	## charter.rs::FactionCharter::gate(Department::Research). Call only
	## for new *delegated* paid research. Autonomous science skips charter.
	if charter.is_empty():
		return ""
	var authority: String = str(charter.get("research_authority", "delegated"))
	if authority == "autonomous":
		return "player_mandates_disabled_in_charter"
	if amount <= 0:
		return "invalid_native_payment"
	var total_spent: int = int(charter.get("spent_cr", 0))
	var ceiling: int = int(charter.get("shared_ceiling_cr", -1))
	if ceiling < 0 or total_spent < 0 or amount > ceiling - total_spent:
		return "shared_mandate_budget_exhausted"
	if treasury < amount or treasury - amount < int(charter.get("protected_treasury_cr", 0)):
		return "charter_treasury_reserve"
	if authority == "review":
		var left: int = int(charter.get("approved_research_cr", 0)) - int(charter.get("spent_research_cr", 0))
		if amount > left:
			return "player_approval_required"
	return ""

static func authorize_research(commander: Dictionary, mandate: Dictionary, charter: Dictionary,
		catalogue: Dictionary, cost: int, treasury: int) -> Dictionary:
	## Mirrors governance.rs::authorize_research's outer may_direct, active,
	## Advise/Hold/Delegated branches and final charter::authorize.
	if cost <= 0:
		return _error("invalid_research_charge")
	if not charter.is_empty() and str(charter.get("research_authority", "delegated")) == "autonomous":
		return {"ok": true, "reason": "", "mandated_shift": false}
	var completed: Array = commander.get("technologies", [])
	if mandate.is_empty() or not _active_mandate(mandate, completed):
		return {"ok": true, "reason": "", "mandated_shift": false}
	var m_error := validate_mandate(mandate, catalogue)
	if m_error != "":
		return _error(m_error)
	var mode: String = str(mandate.get("mode", ""))
	if mode == "advise":
		return {"ok": true, "reason": "", "mandated_shift": false}
	if mode == "hold":
		return _error("player_research_hold")
	var budget: int = int(mandate["budget_ceiling_cr"])
	var spent: int = int(mandate.get("spent_cr", 0))
	if spent > budget - cost:
		return _error("player_mandate_budget_exhausted")
	if treasury < cost or treasury - cost < int(mandate["treasury_floor_cr"]):
		return _error("player_mandate_treasury_floor")
	var reason := _charter_gate(charter, cost, treasury)
	if reason != "":
		return _error(reason)
	return {"ok": true, "reason": "", "mandated_shift": true}

static func paid_after_receipt(mandate: Dictionary, charter: Dictionary, amount: int, mandated_shift: bool) -> Dictionary:
	## Called ONLY by the authoritative same-tick transaction owner, AFTER
	## its physical debit/credit/electronics/worker receipt succeeds; NOT a
	## second payment engine. Both counters live in Director checkpoint.
	if not mandated_shift or amount <= 0:
		return {"ok": true, "mandate": mandate.duplicate(true), "charter": charter.duplicate(true)}
	var new_m := mandate.duplicate(true)
	var new_c := charter.duplicate(true)
	if not new_m.is_empty() and str(new_m.get("mode", "")) == "delegated":
		new_m["spent_cr"] = mini(MAX_I64, int(new_m.get("spent_cr", 0)) + amount)
		new_m["last_reason"] = "native_research_shift_paid"
		if not new_c.is_empty():
			new_c["spent_cr"] = mini(MAX_I64, int(new_c.get("spent_cr", 0)) + amount)
			new_c["spent_research_cr"] = mini(MAX_I64, int(new_c.get("spent_research_cr", 0)) + amount)
			new_c["last_reason"] = "native_paid_receipt_recorded"
	return {"ok": true, "mandate": new_m, "charter": new_c}
