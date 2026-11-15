extends RefCounted
## N143: executable source-backed research domain regression; not run yet.
## Prior source: director.rs research/observe/research_ready; governance.rs;
## charter.rs, N44/45/76/82/89/110/120 earlier draft ports.
const Director = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const Shift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")

static func _expect(errors: Array[String], yes: bool, label: String) -> void:
	if not yes:
		errors.append(label)

static func _catalogue() -> Array:
	## Minimal fixture; authoritative all-12 frozen technology metadata
	## comes from N82 and is injected by the Phase-2 world adapter.
	return [
		{"id":"industrial_methods","prerequisite":"","work":40,"field":"industry"},
		{"id":"orbital_habitats","prerequisite":"","work":50,"field":"expansion"},
		{"id":"automation","prerequisite":"industrial_methods","work":90,"field":"industry"}
	]

static func _commander(progress: int = 30) -> Dictionary:
	return {"technologies":[], "research":"industrial_methods", "progress":progress,
		"research_required":40, "last_research_tick":null,
		"last_shift":null, "history":[], "crisis":false,
		"profile":{"industry":1.5,"expansion":0.8,"science":0.5}}

static func _mandate() -> Dictionary:
	return {"target_technology":"automation","mode":"delegated",
		"budget_ceiling_cr":300,"treasury_floor_cr":10000,
		"spent_cr":0,"created_tick":2,"last_reason":""}

static func _charter() -> Dictionary:
	return {"research_authority":"review","shared_ceiling_cr":1000,
		"protected_treasury_cr":10000,"approved_research_cr":100,
		"spent_cr":0,"spent_research_cr":0,"spent_economy_cr":0,
		"last_reason":""}

static func _world(treasury: int = 20000) -> Dictionary:
	return {"faction_id":"own","tick":60,"treasury":treasury,
		"commander":_commander(), "mandate":_mandate(), "charter":_charter(),
		"markets":[
			{"id":"market-b", "facility_id":"station-b","location":"beta",
				"owner_faction":"own","facility_type":"station","electronics_supply":5.0,
				"electronics_price":3.0,"facility_credits":120},
			{"id":"market-a","facility_id":"station-a","location":"alpha",
				"owner_faction":"own","facility_type":"station","electronics_supply":3.0,
				"electronics_price":4.4,"facility_credits":100}
		],
		"people":[
			{"id":"worker-b","faction_id":"own","location":"alpha",
				"population_count":100,"occupied_workers":3,"wealth":20},
			{"id":"worker-a","faction_id":"own","location":"alpha",
				"population_count":100,"occupied_workers":2,"wealth":10},
			{"id":"worker-c","faction_id":"own","location":"beta",
				"population_count":10,"occupied_workers":0,"wealth":4}
		]}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var rows := _catalogue()
	var catalog := Director.catalogue_map(rows)
	_expect(errors, catalog.size() == 3, "catalogue_loaded")
	var next := Director.next_technology("automation", [], catalog)
	_expect(errors, bool(next.get("ok",false)) and next["next"] == "industrial_methods", "mandate_prerequisite_first")
	next = Director.next_technology("automation", ["industrial_methods"], catalog)
	_expect(errors, bool(next["ok"]) and next["next"] == "automation", "mandate_target_after_prerequisite")
	next = Director.next_technology("automation", ["industrial_methods","automation"], catalog)
	_expect(errors, bool(next["ok"]) and next["next"] == "", "mandate_known_end")
	var c := _commander(0)
	c["research"] = null
	var ai := Director.observe_research(c, {}, {}, rows)
	_expect(errors, bool(ai["ok"]) and ai["commander"]["research"] == "industrial_methods", "ai_select_profile_weight")
	c["profile"] = {"industry":1.0,"expansion":1.0,"science":0.1}
	ai = Director.observe_research(c, {}, {}, rows)
	_expect(errors, ai["commander"]["research"] == "industrial_methods", "profile_tie_lexicographic")
	c["research"] = "orbital_habitats"
	c["progress"] = 10
	var changed := Director.observe_research(c, _mandate(), _charter(), rows)
	_expect(errors, changed["commander"]["research"] == "orbital_habitats" and
		changed["commander"]["progress"] == 10, "mandate_never_erases_paid_partial_progress")
	c["progress"] = 0
	changed = Director.observe_research(c, _mandate(), _charter(), rows)
	_expect(errors, changed["commander"]["research"] == "industrial_methods" and
		changed["commander"]["research_required"] == 40, "mandate_redirects_unpaid_goal")
	var old := _mandate()
	old["spent_cr"] = 180
	var incoming := _mandate()
	incoming["mode"] = "hold"
	incoming["spent_cr"] = 0
	var retained := Director.update_mandate(old, incoming, 80, catalog)
	_expect(errors, bool(retained["ok"]) and int(retained["mandate"]["spent_cr"]) == 180 and
		int(retained["mandate"]["created_tick"]) == 2, "mandate_reconfiguration_preserves_paid_spend")
	incoming["budget_ceiling_cr"] = 100
	var rejected := Director.update_mandate(old, incoming, 80, catalog)
	_expect(errors, not bool(rejected["ok"]) and rejected["reason"] == "invalid_committed_amount",
		"lowering_budget_cannot_erase_prior_research_debit")
	incoming = _mandate()
	incoming["target_technology"] = "orbital_habitats"
	var retarget := Director.update_mandate(old, incoming, 80, catalog)
	_expect(errors, bool(retarget["ok"]) and retarget["mandate"]["spent_cr"] == 0, "new_objective_new_budget")
	var world := _world()
	var exact := world.duplicate(true)
	var pending := Shift.prepare_paid_shift(world, rows)
	_expect(errors, bool(pending.get("ok", false)), "research_paid_preflight")
	if bool(pending.get("ok", false)):
		_expect(errors, pending["market_id"] == "market-a" and pending["population_id"] == "worker-a",
			"stable_source_order_market_location_then_household_id")
		_expect(errors, pending["cost"] == 15 and pending["work_added"] == 10 and
			pending["payroll"] == 10 and pending["electronics"] == 1.0, "paid_shift_exact_bill")
		var fx: Dictionary = pending["effects"]
		_expect(errors, int(fx["faction_treasury_delta"]) + int(fx["facility_credits_delta"]) +
			int(fx["population_wealth_delta"]) == 0, "research_cash_conservation")
		_expect(errors, pending["completed_technology"] == "industrial_methods" and
			pending["commander_after"]["research"] == null and
			pending["commander_after"]["technologies"].has("industrial_methods"), "unlock_only_after_paid_shift")
		_expect(errors, int(pending["mandate_after"]["spent_cr"]) == 15 and
			int(pending["charter_after"]["spent_research_cr"]) == 15, "one_mandate_and_charter_receipt")
		_expect(errors, world == exact, "pure_preflight_does_not_charge_or_grant")
		var forged := pending.duplicate(true)
		forged["effects"]["faction_treasury_delta"] = 999
		var false_ack := Shift.verify_authoritative_receipt(pending, {"authoritative":true,
			"receipt_id":pending["receipt_id"],"faction_id":"own","tick":60,
			"market_id":pending["market_id"],"facility_id":pending["facility_id"],
			"population_id":pending["population_id"],
			"technology":pending["technology"],"effects":forged["effects"]})
		_expect(errors, not bool(false_ack.get("ok", false)), "forged_ledger_delta_refused")
		var ack := {"authoritative":true,
			"receipt_id":pending["receipt_id"],"faction_id":"own","tick":60,
			"market_id":pending["market_id"],"facility_id":pending["facility_id"],
			"population_id":pending["population_id"],
			"technology":pending["technology"],"effects":pending["effects"]}
		var approved := Shift.verify_authoritative_receipt(pending, ack)
		_expect(errors, bool(approved["ok"]) and approved["commander"]["technologies"].has("industrial_methods"),
			"authoritative_receipt_yields_commit_ready_research_only")
		var no_external := ack.duplicate(true)
		no_external["authoritative"] = false
		_expect(errors, not bool(Shift.verify_authoritative_receipt(pending, no_external)["ok"]),
			"unverified_payment_can_never_grant_research")
	var boundary := _world(10015)
	# 4.4 electronics => cost 5+10 = 15, native actual paid shift
	# accepts exactly 10015 CR, whereas research_ready uses STRICT >.
	var ready := Shift.research_ready(boundary, rows)
	var at_floor := Shift.prepare_paid_shift(boundary, rows)
	_expect(errors, bool(ready["ok"]) and not bool(ready["ready"]) and
		bool(at_floor["ok"]), "rust_ready_strict_vs_paid_exact_reserve")
	var held := _world()
	held["mandate"]["mode"] = "hold"
	_expect(errors, Shift.prepare_paid_shift(held, rows)["reason"] == "player_research_hold",
		"delegated_player_hold_blocks_new_shift")
	held["charter"]["research_authority"] = "autonomous"
	_expect(errors, bool(Shift.prepare_paid_shift(held, rows)["ok"]),
		"autonomous_charter_leaves_genesis_science_independent")
	var no_workers := _world()
	for person in no_workers["people"]:
		person["occupied_workers"] = 100
	_expect(errors, Shift.prepare_paid_shift(no_workers, rows)["reason"] ==
		"needs_local_electronics_and_free_workers", "source_requires_local_unused_staff")
	var already := _world()
	already["commander"]["last_research_tick"] = 60
	_expect(errors, Shift.prepare_paid_shift(already, rows)["reason"] == "already_researched",
		"one_paid_shift_per_faction_per_tick")
	var budget := _world()
	budget["mandate"]["spent_cr"] = 295
	_expect(errors, Shift.prepare_paid_shift(budget, rows)["reason"] == "player_mandate_budget_exhausted",
		"delegated_spend_prevents_overdraw")
	var review := _world()
	review["charter"]["approved_research_cr"] = 10
	_expect(errors, Shift.prepare_paid_shift(review, rows)["reason"] == "player_approval_required",
		"review_needs_paid_approval_tranche")
	return {"ok": errors.is_empty(), "errors": errors}
