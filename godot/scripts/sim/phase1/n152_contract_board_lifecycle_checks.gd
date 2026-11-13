extends RefCounted
## N152 scenarios from frozen sim_core/economy/contracts.rs.
## AUTHORED but NOT executed: Phase2 Godot 4 parser/headless and
## real N104 paid engine apply will verify source parity.

const Core = preload("res://scripts/sim/phase1/n152_native_contract_board_core.gd")
const Lifecycle = preload("res://scripts/sim/phase1/n152_native_contract_board_lifecycle.gd")

static func _expect(errors: Array[String], passed: bool, name: String) -> void:
	if not passed:
		errors.append(name)

static func _terms(kind: String, requestor: String = "station") -> Dictionary:
	return {"contract_type":kind,"requestor_id":requestor,
		"faction_id":"terran" if kind in ["subsidy","crew_mission"] else null,
		"commodity":"ore","quantity":20,"source_location":"earth",
		"destination_location":"mars","payment":900,"posted_at_tick":100,
		"lifespan_ticks":500,
		"mission_category":"security_detail" if kind=="crew_mission" else null}

static func _accept_receipt(id: String, ship: String) -> Dictionary:
	return {"trusted_internal_apply":true,"funding_committed":true,
		"contract_id":id,"ship_id":ship}

static func _pickup_receipt(id: String, ship: String) -> Dictionary:
	return {"trusted_internal_apply":true,"pickup_committed":true,
		"contract_id":id,"ship_id":ship}

static func _paid_receipt(id: String, ship: String) -> Dictionary:
	return {"trusted_internal_apply":true,"delivery_and_payment_committed":true,
		"contract_id":id,"ship_id":ship}

static func run() -> Dictionary:
	var errors: Array[String] = []
	var board := Core.new_board()
	var original := board.duplicate(true)
	var delivery := Core.post_kind(board,_terms("delivery"))
	_expect(errors,bool(delivery.get("ok",false)) and
		delivery["id"]=="contract-1" and board==original,
		"first_native_contract_id_one_no_inplace_world_changes")
	if not bool(delivery.get("ok",false)):
		return {"ok":false,"errors":errors}
	board=delivery["board"]
	var subsid := Core.post_kind(board,_terms("subsidy"))
	_expect(errors,bool(subsid.get("ok",false)) and subsid["id"]=="contract-2"
		and subsid["contract"]["min_reputation"]==70,
		"faction_only_subsidy_original_rep_tier")
	board=subsid["board"]
	var mission := Core.post_kind(board,_terms("crew_mission","security-board"))
	_expect(errors,bool(mission.get("ok",false)) and mission["id"]=="contract-3"
		and mission["contract"]["min_reputation"]==50
		and mission["contract"]["commodity"]=="tools",
		"crew_mission_allied_tier_and_tools_placeholder")
	board=mission["board"]
	_expect(errors,Core.posted_for_ship(board,{}).size()==1 and
		Core.posted_for_ship(board,{"terran":50}).size()==2 and
		Core.posted_for_ship(board,{"terran":70}).size()==3,
		"indexed_rep_bucket_faction_visibility_only")
	_expect(errors,Core.posted_for_destination(board,"mars").size()==3
		and Core.check_indices(board)["ok"],
		"all_native_status_location_faction_indices_on_post")
	var bad_accept := Lifecycle.accept_after_funding(board,delivery["id"],
		"ship-a",110,{"trusted_internal_apply":false,"funding_committed":true,
		"contract_id":delivery["id"],"ship_id":"ship-a"})
	_expect(errors,not bool(bad_accept.get("ok",false)),
		"untrusted_ui_receipt_cannot_approve_native_contract")
	var accepted := Lifecycle.accept_after_funding(board,delivery["id"],
		"ship-a",110,_accept_receipt(delivery["id"],"ship-a"))
	_expect(errors,bool(accepted.get("ok",false))
		and accepted["board"]["contracts"][delivery["id"]]["status"]=="accepted"
		and Core.posted_for_destination(accepted["board"],"mars").size()==2
		and Core.check_indices(accepted["board"])["ok"],
		"accept_removes_posted_indexes_without_removing_escrow")
	var denied := Lifecycle.release(accepted["board"],delivery["id"],"ship-b")
	_expect(errors,not bool(denied.get("ok",false)),
		"losing_ship_cannot_release_winners_accepted_contract")
	var released := Lifecycle.release(accepted["board"],delivery["id"],"ship-a")
	_expect(errors,bool(released.get("ok",false))
		and released["board"]["contracts"][delivery["id"]]["fulfiller_id"]==null
		and Core.posted_for_destination(released["board"],"mars").size()==3
		and Core.check_indices(released["board"])["ok"],
		"release_restores_offers_and_clears_ship_assignment")
	var shipping := Lifecycle.mark_picked_up_after_physical_receipt(
		accepted["board"],delivery["id"],_pickup_receipt(delivery["id"],"ship-a"))
	_expect(errors,bool(shipping.get("ok",false)) and
		shipping["board"]["contracts"][delivery["id"]]["status"]=="picked_up",
		"actual_physical_pickup_changes_only_board_state")
	var finished := Lifecycle.mark_delivered_after_physical_receipt(
		shipping["board"],delivery["id"],_paid_receipt(delivery["id"],"ship-a"))
	_expect(errors,bool(finished.get("ok",false)) and
		finished["board"]["contracts"][delivery["id"]]["status"]=="paid"
		and Core.check_indices(finished["board"])["ok"],
		"original_mark_delivered_goes_directly_to_paid_not_delivered")
	var paid_again := Lifecycle.mark_delivered_after_physical_receipt(
		finished["board"],delivery["id"],_paid_receipt(delivery["id"],"ship-a"))
	_expect(errors,not bool(paid_again.get("ok",false)),
		"paid_contract_cannot_be_credited_twice")
	var direct := Lifecycle.mark_delivered_after_physical_receipt(
		accepted["board"],delivery["id"],_paid_receipt(delivery["id"],"ship-a"))
	_expect(errors,bool(direct.get("ok",false))
		and direct["board"]["contracts"][delivery["id"]]["status"]=="paid",
		"rust_deliver_allows_Accepted_to_Paid_without_PickedUp")
	var accepted_sub := Lifecycle.accept_after_funding(board,subsid["id"],
		"ship-a",110,_accept_receipt(subsid["id"],"ship-a"))
	var aboard := Lifecycle.mark_picked_up_after_physical_receipt(
		accepted_sub["board"],subsid["id"],_pickup_receipt(subsid["id"],"ship-a"))
	var accepted_delivery := Lifecycle.accept_after_funding(aboard["board"],
		delivery["id"],"ship-a",110,_accept_receipt(delivery["id"],"ship-a"))
	var destroyed := Lifecycle.drop_ship_holdings(accepted_delivery["board"],"ship-a")
	_expect(errors,bool(destroyed.get("ok",false))
		and destroyed["released"].has(delivery["id"])
		and destroyed["cancelled"].has(subsid["id"])
		and destroyed["board"]["contracts"][delivery["id"]]["status"]=="posted"
		and destroyed["board"]["contracts"][subsid["id"]]["status"]=="expired"
		and Core.check_indices(destroyed["board"])["ok"],
		"lost_ship_releases_unpicked_up_and_expires_lost_cargo")
	var destroyed_twice := Lifecycle.drop_ship_holdings(destroyed["board"],"ship-a")
	_expect(errors,destroyed_twice["released"].is_empty()
		and destroyed_twice["cancelled"].is_empty(),
		"native_admin_ship_cleanup_idempotent_after_first_removal")
	var cancel_requestor := Lifecycle.cancel_for_facility(
		destroyed["board"],"station",null,null)
	_expect(errors,bool(cancel_requestor.get("ok",false))
		and cancel_requestor["cancelled"].has(delivery["id"])
		and Core.posted_for_destination(cancel_requestor["board"],"mars").size()==1
		and Core.check_indices(cancel_requestor["board"])["ok"],
		"admin_facility_cancel_removes_only_matching_live_posted_contracts")
	var cancel_dest := Lifecycle.cancel_for_facility(
		destroyed["board"],null,null,"mars")
	_expect(errors,bool(cancel_dest.get("ok",false))
		and cancel_dest["board"]["contracts"][mission["id"]]["status"]=="expired"
		and Core.check_indices(cancel_dest["board"])["ok"],
		"last_facility_location_cancel_all_live_related_contracts")
	var legacy := subsid["contract"].duplicate(true)
	legacy["id"]="contract-137"
	legacy["payment"]=1400
	legacy["initial_payment"]=900
	legacy["mission_category"]="strategy.colony.v1"
	legacy["funding"]={"source":"faction","reserved":900,"agreed_payment":null}
	legacy["status"]="posted"
	var restored := Core.insert_loaded(Core.new_board(),legacy)
	_expect(errors,bool(restored.get("ok",false))
		and restored["board"]["next_id"]==138
		and restored["board"]["contracts"]["contract-137"]["payment"]==900,
		"persisted_faction_fixed_strategy_reward_is_restored_and_next_id_advanced")
	var next := Core.post_kind(restored["board"],_terms("courier"))
	_expect(errors,bool(next.get("ok",false))
		and next["id"]=="contract-139" and
		Core.check_indices(next["board"])["ok"],
		"native_insert_loaded_contract_137_followed_by_contract_139_cursor")
	var duplicate := Core.insert_loaded(restored["board"],legacy)
	_expect(errors,not bool(duplicate.get("ok",false)),
		"reject_corrupted_duplicate_db_id_instead_of_inconsistent_indexes")
	return {"ok":errors.is_empty(),"errors":errors}
