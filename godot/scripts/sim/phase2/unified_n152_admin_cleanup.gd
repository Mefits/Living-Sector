extends RefCounted
## P2 source bridge: frozen Rust engine/admin.rs::admin_remove_ship and
## admin_remove_facility with N152 ContractBoard cascades. Read original
## N39 World and N9 Ledger, stage a single DETACHED candidate and return.
## Only N39 may apply after full World/Board/wallet verification.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _has_embarked(c: Dictionary) -> bool:
    var funding: Variant = c.get("funding", null)
    return (funding is Dictionary and funding.get("embarked", null) != null) or (
        c.get("embarked", null) != null)

static func stage(world: Dictionary, bank: Dictionary, tick: int,
        kind: String, actor_id: String, reason: String = "admin") -> Dictionary:
    if tick < 0 or actor_id.is_empty() or kind not in ["ship", "facility"]:
        return _bad("invalid_native_admin_identity")
    if kind == "ship" and reason not in ["admin", "bankruptcy", "stagnation"]:
        return _bad("invalid_frozen_retirement_reason")
    if kind == "facility" and reason != "admin":
        return _bad("invalid_facility_removal_reason")
    if not (world.get("contract_board") is Dictionary) or not (
            world.get("escrow_balances") is Dictionary):
        return _bad("missing_one_n104_escrow_authority")
    var source: Dictionary = world["ships"] if kind == "ship" else world["facilities"]
    if not source.has(actor_id):
        return _bad("native_actor_not_found")
    var actor: Dictionary = source[actor_id]
    var contracts: Dictionary = world["contract_board"].get("contracts", {})
    var location: String = str(actor.get("location", ""))
    var lost_account: String = (Schema.ship_account(actor_id) if kind == "ship"
        else Schema.facility_account(actor_id))
    var receipt_id: String = "admin:" + kind + ":" + actor_id + ":remove"
    if world.get("native_admin_removals", {}).has(receipt_id):
        return _bad("native_admin_actor_already_removed")
    for cid in contracts:
        var c: Dictionary = contracts[cid]
        if not _has_embarked(c):
            continue
        if kind == "ship" and str(c.get("fulfiller_id", "")) == actor_id:
            return _bad("passengers_aboard")
        if kind == "facility" and str(c.get("destination_location", "")) == location:
            return _bad("active_passengers_at_facility")
    if kind == "facility":
        # A colony Site with a physically embarked workforce must not
        # be deleted with its sponsor. This is Rust admin.rs guard.
        for site in world.get("construction_sites", {}).values():
            var labor: Variant = site.get("labor", null)
            if str(site.get("location_name", "")) == location and (
                    labor is Dictionary and labor.get("colony_source", null) != null):
                return _bad("active_colony_at_facility")
        # P2 Market is keyed to exactly one real station owner. The
        # source admin removes a station ECS entity, but P2 has not
        # admitted the matching native Market teardown/reassignment.
        # Refuse a dangling market; NEVER silently relabel its owner.
        for market in world.get("markets", {}).values():
            if str(market.get("owner", "")) == actor_id:
                return _bad("canonical_market_owner_needs_source_removal")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _bad("invalid_single_n9_admin_ledger")
    var board := Board.new(ledger)
    if not board.restore(world["contract_board"]):
        return _bad("invalid_single_n104_admin_board")
    var next_world: Dictionary = world.duplicate(true)
    var released: Array = []
    var cancelled: Array = []
    var kicked: Array = []
    var last_at_location: bool = false
    if kind == "ship":
        var dropping: Dictionary = board.drop_removed_ship_holdings(actor_id)
        if not dropping.get("ok", false):
            return _bad("n152_ship_cleanup_rejected")
        released = dropping.get("released", []).duplicate(true)
        cancelled = dropping.get("cancelled", []).duplicate(true)
        next_world["ships"].erase(actor_id)
    else:
        var served: int = 0
        for id in world["facilities"]:
            if str(world["facilities"][id].get("location", "")) == location and str(id) != actor_id:
                served += 1
        last_at_location = served == 0
        var cleaning: Dictionary = board.cancel_removed_facility_contracts(
            actor_id, location, last_at_location)
        if not cleaning.get("ok", false):
            return _bad("n152_facility_cleanup_rejected")
        cancelled = cleaning.get("cancelled", []).duplicate(true)
        next_world["facilities"].erase(actor_id)
        if next_world.get("station_administration", null) is Dictionary:
            next_world["station_administration"].erase(actor_id)
        for ship_id in next_world.get("ships", {}):
            var ship: Dictionary = next_world["ships"][ship_id]
            if str(ship.get("docked_at", "")) == actor_id:
                ship["docked_at"] = ""
                kicked.append(str(ship_id))
        # A source cancellation can release a ship from a now-invalid
        # job, but cannot fabricate a cargo delivery or move its goods.
        for ship_id in next_world.get("ships", {}):
            var ship: Dictionary = next_world["ships"][ship_id]
            if cancelled.has(str(ship.get("active_contract_id", ""))):
                ship["active_contract_id"] = ""
                ship["current_goal"] = "idle"
                ship["current_bt"] = null
                ship["max_source_cost"] = 0
    var written: Dictionary = ledger.close_removed_entity_account(
        receipt_id, lost_account, tick,
        "ship_decommissioned" if kind == "ship" else "facility_removed")
    if not written.get("ok", false):
        return _bad("n9_native_actor_close_" + str(written.get("reason", "rejected")))
    next_world["contract_board"] = board.snapshot()
    var retirement: Dictionary = {}
    if kind == "ship":
        var capacity: float = float(actor.get("fuel_capacity", 0.0))
        var fuel_percent: int = int(round(float(actor.get("fuel", 0.0)) /
            capacity * 100.0)) if capacity > 0.0 else 0
        var lifecycle: Dictionary = actor.get("lifecycle", {})
        retirement = {"agent_id": actor_id,
            "name": str(actor.get("name", actor_id)),
            "class": str(actor.get("class", "")),
            "faction_id": str(actor.get("faction_id", "")),
            "final_location": location,
            "final_credits": int(actor.get("credits", 0)),
            "final_crew_morale": int(round(float(actor.get("crew_morale", 0.0)))),
            "final_fuel_pct": fuel_percent,
            "broke_strikes": int(lifecycle.get("broke_strikes",
                actor.get("broke_strikes", 0))),
            "hoard_strikes": int(lifecycle.get("hoard_strikes",
                actor.get("hoard_strikes", 0))),
            "retired_at_tick": tick, "reason": reason}
    if not next_world.has("native_admin_removals"):
        next_world["native_admin_removals"] = {}
    next_world["native_admin_removals"][receipt_id] = {
        "id": actor_id, "kind": kind, "tick": tick,
        "credits_lost": int(written["credits_lost"]),
        "ledger_receipt": receipt_id, "reason": reason,
        "retirement": retirement}
    var err: String = Schema.validate(next_world)
    if not err.is_empty():
        return _bad("invalid_native_admin_world_" + err)
    return {"ok": true, "world": next_world,
        "ledger_snapshot": ledger.snapshot(),
        "receipt_id": receipt_id, "credits_lost": int(written["credits_lost"]),
        "released": released, "cancelled": cancelled, "kicked": kicked,
        "last_at_location": last_at_location, "retirement": retirement}

