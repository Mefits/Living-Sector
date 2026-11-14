extends RefCounted
## Frozen Rust sim_server/engine/apply.rs N21 FIFO dock_queue on ONE N39
## World, including source FacilityStorage queue and paid commit_dock.
## Pure detached stage: only N39 may publish World and N9 balances.
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const DOCK_FEE_BASE: int = 50
const MAX_I64: int = 9223372036854775807

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": "n21_fifo_" + reason}

static func _queue(fac: Dictionary) -> Array:
    return fac.get("dock_queue", []).duplicate(true)

static func _occupants(world: Dictionary, fid: String) -> int:
    var count: int = 0
    for ship in world.get("ships", {}).values():
        if str(ship.get("docked_at", "")) == fid:
            count += 1
    return count

static func _candidates(world: Dictionary, loc: String,
        preferred_type: String, preferred_id: String) -> Array:
    var candidates: Array = []
    for fid in world.get("facilities", {}):
        var fac: Dictionary = world["facilities"][fid]
        if str(fac.get("location", "")) != loc or (
                not preferred_id.is_empty() and str(fid) != preferred_id) or (
                not preferred_type.is_empty() and str(fac.get("type", "")) != preferred_type):
            continue
        # Frozen Rust dockable_candidates_ordered permits any real
        # non-abandoned facility with a positive N21 capacity when no
        # explicit preferred type is requested (N83 market owners
        # can be farms/factories, not necessarily literal stations).
        if bool(fac.get("abandoned", false)) or (
                int(fac.get("docking_capacity", 0)) < 1):
            continue
        candidates.append(str(fid))
    # Rust sorts by DESC docking capacity; source ECS tie order is
    # unavailable across engines, so stable lexical tie-break.
    candidates.sort_custom(func(a, z):
        var cap_a: int = int(world["facilities"][a]["docking_capacity"])
        var cap_b: int = int(world["facilities"][z]["docking_capacity"])
        return cap_a > cap_b if cap_a != cap_b else str(a) < str(z))
    return candidates

static func _valid_waiter(world: Dictionary, fid: String,
        ship_id: String) -> bool:
    var ship: Dictionary = world.get("ships", {}).get(ship_id, {})
    var fac: Dictionary = world.get("facilities", {}).get(fid, {})
    if ship.is_empty() or fac.is_empty() or (
            str(ship.get("location", "")) != str(fac.get("location", "")) or
            not str(ship.get("docked_at", "")).is_empty() or
            not (ship.get("transit") is Dictionary) or
            not ship["transit"].is_empty() or
            ship.get("dock_attempt_start_tick", null) == null):
        return false
    var bt: Variant = ship.get("current_bt", null)
    # Rust stale ShipEconomy.dock_attempt_start_tick is cleared when a
    # Dock action stops. A completed/replaced BT must not hold a slot.
    return bt is Dictionary and BT.validate(bt) and (
        BT.current_action(bt) in ["Dock", "DockAtShipyard",
            "ConstructionDock"])

static func _prune(world: Dictionary, fid: String) -> bool:
    var fac: Dictionary = world["facilities"][fid]
    var before: Array = _queue(fac)
    var after: Array = []
    for sid in before:
        if _valid_waiter(world, fid, str(sid)) and not after.has(sid):
            after.append(sid)
    if after == before:
        return false
    fac["dock_queue"] = after
    return true

static func _fee(world: Dictionary, fid: String, ship_id: String) -> int:
    var fac: Dictionary = world["facilities"][fid]
    var ship: Dictionary = world["ships"][ship_id]
    var cap: int = int(fac.get("docking_capacity", 0))
    if cap <= 0:
        return -1
    var occupied: int = _occupants(world, fid)
    var raw_condition: Variant = fac.get("condition", 1.0)
    if not (raw_condition is int or raw_condition is float) or (
            not is_finite(float(raw_condition))):
        return -1
    var condition: float = clampf(float(raw_condition), 0.0, 1.0)
    # Rust f32 docking_fee(50, occupied, capacity, condition) followed
    # by trade_pact_dock_modifier + ROUND; no invented free docking.
    var gross: int = roundi(50.0 *
        (1.0 + float(occupied) / float(cap)) *
        maxf(2.0 - condition, 0.5))
    var treaty: Dictionary = Relations.trade_pact_dock_modifier(
        world.get("faction_relations", {}),
        str(ship.get("faction_id", "")), str(fac.get("faction", "")))
    var discounted: int = roundi(float(gross) *
        float(treaty.get("fee_factor", 1.0)))
    return discounted if discounted >= 0 else -1

static func _admit(world: Dictionary, ledger: Dictionary, fid: String,
        sid: String, tick: int, cause: String) -> Dictionary:
    var fac: Dictionary = world["facilities"][fid]
    var ship: Dictionary = world["ships"][sid]
    if int(fac.get("docking_capacity", 0)) <= _occupants(world, fid) or (
            not str(ship.get("docked_at", "")).is_empty() or
            str(ship.get("location", "")) != str(fac.get("location", ""))):
        return _bad("source_dock_not_really_available")
    var price: int = _fee(world, fid, sid)
    if price < 0 or int(ship.get("credits", -1)) < price or (
            int(fac.get("credits", -1)) > MAX_I64 - price):
        return _bad("source_dock_fee_unaffordable")
    var op_id: String = "n21:dock:" + sid + ":" + str(tick)
    if world.get("dock_receipts", {}).has(op_id):
        return _bad("duplicate_real_dock_receipt")
    var paid: Dictionary = ledger.duplicate(true)
    if price > 0:
        var bank := Bank.new()
        if not bank.restore(ledger):
            return _bad("n9_original_bank_restore_failed")
        var moved: Dictionary = bank.transfer(op_id, "ship:" + sid,
            "facility:" + fid, price, tick, "native_n21_dock")
        if not moved.get("ok", false):
            return _bad("n9_original_dock_debit_rejected")
        paid = bank.snapshot()
    ship["credits"] = int(ship["credits"]) - price
    ship["docked_at"] = fid
    ship["dock_attempt_start_tick"] = null
    fac["credits"] = int(fac["credits"]) + price
    fac["dirty"] = true
    var queued: Array = _queue(fac)
    queued.erase(sid)
    fac["dock_queue"] = queued
    var receipt: Dictionary = {
        "operation_id": op_id, "action": "dock", "ship_id": sid,
        "facility_id": fid, "tick": tick, "fee": price,
        "financial_receipt": op_id if price > 0 else "",
        "source": cause}
    world["dock_receipts"][op_id] = receipt.duplicate(true)
    return {"ok": true, "changed": true, "status": "docked",
        "world": world, "ledger_snapshot": paid,
        "receipt": receipt, "fee": price}

static func request(world: Dictionary, ledger: Dictionary,
        ship_id: String, location: String, tick: int,
        preferred_type: String = "", preferred_id: String = "") -> Dictionary:
    if tick < 1 or ship_id.is_empty() or location.is_empty() or (
            not world.get("ships", {}).has(ship_id) or
            not (world.get("facilities") is Dictionary) or
            not (world.get("dock_receipts") is Dictionary)):
        return _bad("invalid_original_dock_request")
    var current: Dictionary = world["ships"][ship_id]
    if str(current.get("location", "")) != location or (
            not (current.get("transit") is Dictionary) or
            not current["transit"].is_empty() or
            not str(current.get("docked_at", "")).is_empty()):
        return _bad("request_ship_not_waiting_at_actual_location")
    var staged: Dictionary = world.duplicate(true)
    var options: Array = _candidates(staged, location, preferred_type, preferred_id)
    if options.is_empty():
        return {"ok": true, "changed": false, "status": "no_real_dock",
            "world": world, "ledger_snapshot": ledger}
    for fid in options:
        if not staged["facilities"][fid].has("dock_queue"):
            # Genuine legacy P2 checkpoint or original N154 site with
            # FacilityStorage default not serialized yet.
            staged["facilities"][fid]["dock_queue"] = []
        _prune(staged, str(fid))
    for fid in options:
        var q: Array = _queue(staged["facilities"][fid])
        if not q.has(ship_id):
            continue
        if str(q[0]) != ship_id or _occupants(staged, str(fid)) >= int(
                staged["facilities"][fid]["docking_capacity"]):
            return {"ok": true, "changed": staged != world,
                "status": "queued", "world": staged,
                "ledger_snapshot": ledger}
        var fee: int = _fee(staged, str(fid), ship_id)
        if fee < 0 or int(staged["ships"][ship_id]["credits"]) < fee:
            staged["facilities"][fid]["dock_queue"].erase(ship_id)
            staged["ships"][ship_id]["dock_attempt_start_tick"] = null
            return {"ok": true, "changed": true, "status": "evicted_insolvent",
                "world": staged, "ledger_snapshot": ledger}
        return _admit(staged, ledger, str(fid), ship_id, tick, "request_head")
    for fid in options:
        var fac: Dictionary = staged["facilities"][fid]
        var q: Array = _queue(fac)
        var occupied: int = _occupants(staged, str(fid))
        if occupied + q.size() >= int(fac["docking_capacity"]):
            continue
        var fee: int = _fee(staged, str(fid), ship_id)
        if fee >= 0 and int(staged["ships"][ship_id]["credits"]) >= fee:
            return _admit(staged, ledger, str(fid), ship_id, tick, "request_fast_path")
    var shortest: String = ""
    var shortest_count: int = MAX_I64
    for fid in options:
        var len: int = _queue(staged["facilities"][fid]).size()
        if len < shortest_count:
            shortest = str(fid)
            shortest_count = len
    if shortest.is_empty():
        return _bad("no_original_queue_candidate")
    staged["facilities"][shortest]["dock_queue"].append(ship_id)
    if staged["ships"][ship_id].get("dock_attempt_start_tick", null) == null:
        staged["ships"][ship_id]["dock_attempt_start_tick"] = tick
    return {"ok": true, "changed": true, "status": "queued",
        "facility_id": shortest, "world": staged,
        "ledger_snapshot": ledger}

static func release(world: Dictionary, ledger: Dictionary,
        ship_id: String, location: String, tick: int) -> Dictionary:
    if tick < 1 or not world.get("ships", {}).has(ship_id):
        return _bad("unknown_source_release_actor")
    var ship: Dictionary = world["ships"][ship_id]
    var fid: String = str(ship.get("docked_at", ""))
    if fid.is_empty() or not world.get("facilities", {}).has(fid) or (
            str(ship.get("location", "")) != location or
            str(world["facilities"][fid].get("location", "")) != location):
        return _bad("no_real_physical_dock_to_release")
    var staged: Dictionary = world.duplicate(true)
    staged["ships"][ship_id]["docked_at"] = ""
    staged["ships"][ship_id]["dock_attempt_start_tick"] = null
    var op_id: String = "n21:undock:" + ship_id + ":" + str(tick)
    if staged.get("dock_receipts", {}).has(op_id):
        return _bad("replayed_n21_release")
    var receipt: Dictionary = {
        "operation_id": op_id, "action": "undock",
        "ship_id": ship_id, "facility_id": fid, "tick": tick,
        "fee": 0, "financial_receipt": ""}
    staged["dock_receipts"][op_id] = receipt.duplicate(true)
    return {"ok": true, "changed": true, "status": "undocked",
        "world": staged, "ledger_snapshot": ledger.duplicate(true),
        "receipt": receipt}

static func advance(world: Dictionary, ledger: Dictionary,
        tick: int) -> Dictionary:
    if tick < 1 or not (world.get("facilities") is Dictionary) or (
            not (world.get("ships") is Dictionary)):
        return _bad("missing_canonical_dock_queue")
    # A clean finite Galaxy has no queued arrivals most ticks. Do not
    # deep-copy all markets/factions/ships/receipts or N9 just to perform
    # an empty Rust tick_dock_queue_advance pass.
    var has_waiters: bool = false
    for facility in world["facilities"].values():
        if facility is Dictionary and facility.get("dock_queue", []) is Array and (
                not facility.get("dock_queue", []).is_empty()):
            has_waiters = true
            break
    if not has_waiters:
        return {"ok": true, "changed": false, "world": world,
            "ledger_snapshot": ledger, "events": [], "tick": tick,
            "status": "SOURCE_N21_FIFO_EMPTY"}
    var staged: Dictionary = world.duplicate(true)
    var bank: Dictionary = ledger.duplicate(true)
    var events: Array = []
    var changed: bool = false
    var keys: Array = staged["facilities"].keys()
    keys.sort()
    for fid in keys:
        if _queue(staged["facilities"][fid]).is_empty():
            continue
        changed = _prune(staged, str(fid)) or changed
        while not _queue(staged["facilities"][fid]).is_empty():
            var fac: Dictionary = staged["facilities"][fid]
            if _occupants(staged, str(fid)) >= int(fac.get(
                    "docking_capacity", 0)):
                break
            var head: String = str(_queue(fac)[0])
            var fee: int = _fee(staged, str(fid), head)
            if fee < 0 or int(staged["ships"][head].get("credits", -1)) < fee:
                fac["dock_queue"].pop_front()
                staged["ships"][head]["dock_attempt_start_tick"] = null
                events.append({"status": "evicted_insolvent",
                    "ship_id": head, "facility_id": str(fid), "tick": tick})
                changed = true
                continue
            var placed: Dictionary = _admit(
                staged, bank, str(fid), head, tick, "fifo_tick")
            if not placed.get("ok", false):
                return placed
            staged = placed["world"]
            bank = placed["ledger_snapshot"]
            events.append(placed["receipt"].duplicate(true))
            changed = true
    return {"ok": true, "changed": changed, "world": staged,
        "ledger_snapshot": bank, "events": events, "tick": tick,
        "status": "SOURCE_N21_FIFO_DOCK_QUEUE"}
