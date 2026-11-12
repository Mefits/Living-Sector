extends RefCounted
## N147 — frozen strategy/colony_development.rs::commission().
## Phase 1: source-complete *admission* and authoritative paid ContractBoard
## transaction proposal. Actual board post_passenger_for + register_prepaid
## AND real FactionData.treasury debit MUST be committed by one engine owner.
## A pure GDScript function cannot claim it already posted or spent.
const Plan = preload("res://scripts/sim/phase1/n147_native_colony_migration_planner.gd")
const MAX_U64: int = 9223372036854775807 # GDScript int; Rust u64 may exceed
const CONSTRUCTION_LIFESPAN_BASE: int = 800
const MISSION_TAG: String = "strategy.colony.workforce.v1"

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _positive_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0

static func _outstanding_for_destination(contracts: Array, faction: String,
		destination: String) -> bool:
	## Rust commission checks every outstanding passenger contract with
	## the SAME faction requestor and destination, regardless of its source.
	for c in contracts:
		if not c is Dictionary:
			continue
		if str(c.get("type", "")) != "passenger":
			continue
		if str(c.get("requestor_id", "")) == faction and 				str(c.get("destination_location", "")) == destination and 				Plan.outstanding(c):
			return true
	return false

static func _valid_households(people: Array, faction: String,
		source: String, destination: String, quantity: int) -> bool:
	## source requires original household still has quantity+10 people.
	## Destination MUST have an existing household; no ghost colonists.
	var source_ok := false
	var target_ok := false
	for pop in people:
		if not pop is Dictionary or str(pop.get("faction_id", "")) != faction:
			continue
		if str(pop.get("location", "")) == source and 				typeof(pop.get("population_count")) == TYPE_INT and 				int(pop["population_count"]) >= quantity + Plan.MIN_SOURCE_RESERVE:
			source_ok = true
		if str(pop.get("location", "")) == destination:
			target_ok = true
	return source_ok and target_ok

static func _native_idle_carrier(world: Dictionary, faction: String,
		source: String, quantity: int) -> bool:
	## Source commission() rechecks id/class/fuel/current position/transit,
	## but unlike migration_proposals() it does not look at outstanding
	## ContractBoard fulfiller assignments. Keep that exact distinction.
	var physical: Dictionary = world["physical_distances"]
	var classes: Dictionary = world["ship_classes"]
	for ship in world["ships"]:
		if not ship is Dictionary or str(ship.get("faction_id", "")) != faction:
			continue
		var active = ship.get("active_contract_id", null)
		if active != null and str(active) != "":
			continue
		if bool(ship.get("in_transit", false)):
			continue
		var fuel = ship.get("fuel", null)
		if not (typeof(fuel) in [TYPE_INT, TYPE_FLOAT]) or 				not is_finite(float(fuel)) or float(fuel) <= 0.0:
			continue
		var cls: String = str(ship.get("class", ""))
		var spec = classes.get(cls, null)
		if not (spec is Dictionary) or typeof(spec.get("passenger_capacity")) != TYPE_INT:
			continue
		if int(spec["passenger_capacity"]) < quantity:
			continue
		var loc = ship.get("location", null)
		if loc is String and (str(loc) == source or 				Plan.physical_route_exists(physical, str(loc), source)):
			return true
	return false

static func prepare_commission(world: Dictionary, faction: String,
		plan: Dictionary, tick: int, multiplier: int) -> Dictionary:
	## Same gate ordering as native commission(). Atomic proposal includes
	## post/funding/debit together; do NOT precredit carrier or household.
	for key in ["contracts", "households", "ships", "ship_classes",
			"physical_distances", "treasuries"]:
		if not world.has(key):
			return _fail("missing_world_field:" + key)
	if not (world["contracts"] is Array and world["households"] is Array and
			world["ships"] is Array and world["ship_classes"] is Dictionary and
			world["physical_distances"] is Dictionary and world["treasuries"] is Dictionary):
		return _fail("invalid_world_projection")
	if faction.is_empty() or tick < 0 or multiplier < 0:
		return _fail("invalid_identity_or_tick")
	var quantity_v = plan.get("quantity", null)
	var payment_v = plan.get("payment", null)
	var source: String = str(plan.get("source", ""))
	var destination: String = str(plan.get("destination", ""))
	if str(plan.get("reason", "")) != "ready" or 			not _positive_int(quantity_v) or int(quantity_v) > Plan.MAX_MIGRATION_PARTY or 			source.is_empty() or destination.is_empty() or source == destination:
		return _fail("invalid_migration_plan")
	var quantity: int = int(quantity_v)
	if typeof(payment_v) != TYPE_INT or int(payment_v) != quantity * Plan.PASSENGER_PAYMENT_PER_HEAD:
		return _fail("invalid_passenger_contract_payment")
	var payment: int = int(payment_v)
	if _outstanding_for_destination(world["contracts"], faction, destination):
		return _fail("existing_passenger_contract")
	if not _valid_households(world["households"], faction, source, destination, quantity):
		return _fail("missing_real_source_or_destination_household")
	if not Plan.physical_route_exists(world["physical_distances"], source, destination):
		return _fail("no_physical_navigation")
	if not _native_idle_carrier(world, faction, source, quantity):
		return _fail("no_idle_eligible_passenger_ship")
	var money := Plan._read_cash(world["treasuries"], faction)
	if not bool(money.get("ok", false)):
		return _fail("missing_faction_treasury")
	var balance: int = int(money["cash"])
	if balance - Plan.FACTION_SUBSIDY_FLOOR < payment:
		return _fail("below_faction_subsidy_floor")
	var lifespan: int = CONSTRUCTION_LIFESPAN_BASE * maxi(1, multiplier)
	if lifespan > MAX_U64:
		lifespan = MAX_U64
	# ContractBoard::post_passenger_for requests must match Rust fields.
	# Contract type Passenger stores commodity Food placeholder, but real
	# delivery applies to household counts, NOT food inventory.
	var post := {"requestor_id": faction, "faction_id": faction, "type": "passenger",
		"commodity": "food", "quantity": quantity, "source_location": source,
		"destination_location": destination, "payment": payment,
		"posted_at_tick": tick, "lifespan_ticks": lifespan,
		"mission_category": MISSION_TAG, "funding_source": "faction",
		"reserved_credits": payment}
	return {"ok": true, "reason": "", "faction_id": faction, "tick": tick,
		"treasury_before": balance, "treasury_after": balance - payment,
		"treasury_delta": -payment, "escrow_reserved": payment,
		"post": post, "plan": plan.duplicate(true),
		"preconditions": {
			"treasury": balance, "source_population_min": quantity + Plan.MIN_SOURCE_RESERVE,
			"destination_household_present": true, "idle_carrier_present": true,
			"physical_distance": world["physical_distances"][source][destination],
			"no_outstanding_passenger_contract": true
		},
		"authoritative_operation": "post_passenger_for+register_prepaid+debit_faction_treasury"}

static func verify_native_commission_receipt(prepared: Dictionary, receipt: Dictionary) -> Dictionary:
	## Only the trusted native engine transaction owner can attest this
	## receipt after a single atomic ContractBoard/treasury save boundary.
	## NEVER accept any UI-generated Dictionary as payment evidence.
	if not bool(prepared.get("ok", false)) or not bool(receipt.get("trusted_internal_apply", false)):
		return _fail("authoritative_prepaid_receipt_required")
	var post: Dictionary = prepared["post"]
	var fields := {
		"requestor_id": prepared["faction_id"], "faction_id": prepared["faction_id"],
		"source_location": post["source_location"],
		"destination_location": post["destination_location"],
		"quantity": post["quantity"], "initial_payment": post["payment"],
		"posted_at_tick": prepared["tick"], "mission_category": MISSION_TAG,
		"status": "posted", "contract_type": "passenger",
		"funding_source": "faction", "funding_reserved": prepared["escrow_reserved"],
		"faction_treasury_delta": prepared["treasury_delta"]
	}
	if not receipt.get("contract_id") is String or str(receipt.get("contract_id", "")).is_empty():
		return _fail("missing_authoritative_contract_id")
	for field in fields:
		if receipt.get(field, null) != fields[field]:
			return _fail("authoritative_commission_mismatch:" + str(field))
	return {"ok": true, "reason": "", "contract_id": str(receipt["contract_id"]),
		"credits_transferred_to_escrow": int(prepared["escrow_reserved"]),
		"event": {"kind": "colony_workforce_contract_posted",
			"faction_id": prepared["faction_id"], "contract_id": str(receipt["contract_id"]),
			"destination": post["destination_location"], "source": post["source_location"],
			"passengers": post["quantity"], "tick": prepared["tick"]}}
