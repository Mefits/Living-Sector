extends RefCounted
## N39/N150 observation-only local validator.
## A cheap rejection gate, NEVER a replacement for Schema.validate.
## It has no writable references to the authoritative World, and checks
## only the six N150 observation dictionaries (not stock, funds or cargo).
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")

const OBSERVATION_FIELDS: Array[String] = [
    "prices", "demand", "seed_demand", "consumption_window",
    "orders", "history"]

static func validate_observation_proposal(world: Dictionary,
        updates: Dictionary, expected_version: int,
        current_version: int) -> String:
    if expected_version >= 0 and expected_version != current_version:
        return "stale_market_observation_version"
    if not (world.get("markets") is Dictionary):
        return "missing_market_domain"
    var markets: Dictionary = world["markets"]
    if updates.size() != markets.size():
        return "wrong_market_cardinality"
    for location in updates:
        if not markets.has(location) or not (updates[location] is Dictionary):
            return "unknown_market_observation"
        if not (markets[location] is Dictionary):
            return "invalid_market_row"
        var original: Dictionary = markets[location]
        var proposed: Dictionary = updates[location]
        if str(proposed.get("id", "")) != str(original.get("id", "")):
            return "forged_market_identity"
        for field in OBSERVATION_FIELDS:
            if not (proposed.get(field) is Dictionary):
                return "invalid_market_observation_field"
        for commodity in proposed["prices"]:
            if not Inventory.valid_amount(proposed["prices"][commodity]):
                return "invalid_market_price"
        var history: Dictionary = proposed["history"]
        var flags: Variant = history.get("crisis_notified", {})
        if not (flags is Dictionary):
            return "invalid_native_market_crisis_flags"
        for commodity in flags:
            if not (commodity is String) or str(commodity).is_empty() or (
                    typeof(flags[commodity]) != TYPE_BOOL):
                return "invalid_native_market_crisis_flag"
    return ""
