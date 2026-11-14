extends RefCounted
## N42 CODE_UNVERIFIED. Read-only closed-transfer audit, not a world ledger.
## Native reference: engine/persist.rs atomic frame and economy/money.rs.
## The caller supplies authoritative snapshots; this module never mutates them.
const EPSILON: float = 0.000001
const MAX_SAFE_CREDITS: int = 9223372036854775807

## Shape: {"credits": {"account": int}, "stores": {"location": {"commodity": number}},
##         "cargo": {"ship": {"commodity": number}}, "ship_owner": {"ship": "faction"},
##         "ship_location": {"ship": "location"}, "dock": {"ship": "location"}}
## No source/sink is allowed: this checks transfers, not mining/production.
func audit_snapshot(state: Dictionary) -> Dictionary:
    var errors: Array[String] = []
    for required in ["credits", "stores", "cargo", "ship_owner", "ship_location", "dock"]:
        if not state.has(required) or not (state[required] is Dictionary):
            errors.append("missing_or_invalid:" + required)
    if not errors.is_empty():
        return _result(errors, {}, 0)
    var credits: Dictionary = state["credits"]
    var total_credits: int = 0
    var credit_ids: Array = credits.keys()
    credit_ids.sort()
    for id in credit_ids:
        var amount: Variant = credits[id]
        if not _identifier(id) or typeof(amount) != TYPE_INT or amount < 0:
            errors.append("invalid_credit:" + str(id))
            continue
        if total_credits > MAX_SAFE_CREDITS - amount:
            errors.append("credit_overflow")
        else:
            total_credits += amount
    var totals: Dictionary = {}
    _sum_inventory(state["stores"], "store", totals, errors)
    _sum_inventory(state["cargo"], "cargo", totals, errors)
    var owners: Dictionary = state["ship_owner"]
    var locations: Dictionary = state["ship_location"]
    var docks: Dictionary = state["dock"]
    var ships: Dictionary = state["cargo"]
    var ship_ids: Array = ships.keys()
    ship_ids.sort()
    for ship_id in ship_ids:
        if not owners.has(ship_id) or not _identifier(owners[ship_id]):
            errors.append("missing_ship_owner:" + str(ship_id))
        if not locations.has(ship_id) or not _identifier(locations[ship_id]):
            errors.append("missing_ship_location:" + str(ship_id))
    for ship_id in owners:
        if not ships.has(ship_id):
            errors.append("owner_without_ship:" + str(ship_id))
    for ship_id in locations:
        if not ships.has(ship_id):
            errors.append("location_without_ship:" + str(ship_id))
    for ship_id in docks:
        if not ships.has(ship_id) or not _identifier(docks[ship_id]):
            errors.append("invalid_dock:" + str(ship_id))
        elif not locations.has(ship_id) or docks[ship_id] != locations[ship_id]:
            errors.append("dock_location_mismatch:" + str(ship_id))
        elif not state["stores"].has(docks[ship_id]):
            errors.append("dock_without_store:" + str(ship_id))
    errors.sort()
    return _result(errors, totals, total_credits)

func audit_closed_transfer(before: Dictionary, after: Dictionary) -> Dictionary:
    var first: Dictionary = audit_snapshot(before)
    var second: Dictionary = audit_snapshot(after)
    var errors: Array[String] = []
    for error in first["errors"]:
        errors.append("before:" + error)
    for error in second["errors"]:
        errors.append("after:" + error)
    if not errors.is_empty():
        errors.sort()
        return _result(errors, {}, 0)
    if first["total_credits"] != second["total_credits"]:
        errors.append("credits_not_conserved")
    var old_goods: Dictionary = first["goods"]
    var new_goods: Dictionary = second["goods"]
    var keys: Dictionary = {}
    for commodity in old_goods:
        keys[commodity] = true
    for commodity in new_goods:
        keys[commodity] = true
    var ordered: Array = keys.keys()
    ordered.sort()
    for commodity in ordered:
        if absf(float(old_goods.get(commodity, 0.0)) - float(new_goods.get(commodity, 0.0))) > EPSILON:
            errors.append("goods_not_conserved:" + str(commodity))
    errors.sort()
    return _result(errors, new_goods, int(second["total_credits"]))

func _sum_inventory(inventories: Dictionary, prefix: String, totals: Dictionary, errors: Array[String]) -> void:
    var locations: Array = inventories.keys()
    locations.sort()
    for location in locations:
        if not _identifier(location) or not (inventories[location] is Dictionary):
            errors.append("invalid_" + prefix + ":" + str(location))
            continue
        var items: Dictionary = inventories[location]
        var commodities: Array = items.keys()
        commodities.sort()
        for commodity in commodities:
            var amount: Variant = items[commodity]
            if not _identifier(commodity) or not (amount is int or amount is float):
                errors.append("invalid_commodity:" + str(location) + ":" + str(commodity))
                continue
            var quantity: float = float(amount)
            if not is_finite(quantity) or quantity < 0.0:
                errors.append("invalid_quantity:" + str(location) + ":" + str(commodity))
                continue
            var previous: float = float(totals.get(commodity, 0.0))
            if not is_finite(previous + quantity):
                errors.append("quantity_overflow:" + str(commodity))
            else:
                totals[commodity] = previous + quantity

func _identifier(value: Variant) -> bool:
    return value is String and not value.is_empty()

func _result(errors: Array[String], goods: Dictionary, credits: int) -> Dictionary:
    return {"ok": errors.is_empty(), "errors": errors, "goods": goods.duplicate(true), "total_credits": credits}
