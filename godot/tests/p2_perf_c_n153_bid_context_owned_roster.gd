extends RefCounted
## Run via the project's existing Godot test harness; no fabricated World ticks.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Selector = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")

static func _check(condition: bool, message: String) -> void:
    assert(condition, message)

static func _legacy_context(offer: Dictionary, controllers: Dictionary,
        base: Dictionary, ship_id: String, faction: String, ship: Dictionary,
        quote: Dictionary, knowledge: Dictionary) -> Dictionary:
    var commerce: Dictionary = base.duplicate()
    commerce[faction] = true
    return {
        "offers": [offer], "ship_id": ship_id, "ship_faction": faction,
        "ship_location": "Alpha", "cargo_capacity": int(ship["cargo_capacity"]),
        "credits": int(ship.get("credits", 0)), "sensor_range_au": 2.0,
        "system_by_location": {"Alpha": "S", "Beta": "S"},
        "controllers": controllers, "commerce_allowed": commerce,
        "quotes": {"job": quote}, "memory": {"price_knowledge": knowledge},
        "tick": 10
    }

static func run() -> Dictionary:
    var offer: Dictionary = {
        "id": "job", "status": "Posted", "contract_type": "Delivery",
        "faction_id": "buyer", "requestor_id": "buyer",
        "source_location": "Alpha", "destination_location": "Beta",
        "commodity": "ore", "quantity": 3, "may_accept": true
    }
    var controllers: Dictionary = {"Alpha": "seller", "Beta": "buyer"}
    var base: Dictionary = {"buyer": true, "seller": true}
    var cache: Dictionary = {}
    var knowledge: Dictionary = {"Alpha": {"ore": {"price": 4.0}}}
    var ship: Dictionary = {"cargo_capacity": 20, "credits": 100}
    var rows: Array = [offer]
    var systems: Dictionary = {"Alpha": "S", "Beta": "S"}
    for faction in ["seller", "buyer", "third"]:
        for payment in [30, 9, 0]:
            var quote: Dictionary = {
                "valid": payment > 0, "quoted_payment": payment,
                "top_up": 0, "payer_balance": 100,
                "reserved": 0, "source_purchase_cost": 12
            }
            var old: Dictionary = _legacy_context(offer, controllers, base,
                "ship_" + faction, faction, ship, quote, knowledge)
            var commerce: Dictionary = Dispatch._offer_commerce_view(
                cache, faction, base)
            var fresh: Dictionary = Dispatch._selector_bid_context(
                rows, controllers, commerce, "ship_" + faction, faction,
                "Alpha", ship, 2.0, systems, quote, "job", knowledge, 10)
            _check(Selector.select_contract(old) == Selector.select_contract(fresh),
                "N153 source selector changed winner/price/cargo for " + faction)
            _check(old["quotes"] == fresh["quotes"], "bid quote mismatch")
            _check(old["commerce_allowed"] == fresh["commerce_allowed"],
                "bid commerce mismatch")
    _check(cache.size() == 3, "faction view should be cached once")
    var first: Dictionary = Dispatch._offer_commerce_view(cache, "third", base)
    var second: Dictionary = Dispatch._offer_commerce_view(cache, "third", base)
    _check(is_same(first, second), "repeated faction must reuse view")
    _check(not base.has("third"), "must not mutate base commerce")
    var q1: Dictionary = {"valid": true, "quoted_payment": 30,
        "top_up": 0, "payer_balance": 100}
    var q2: Dictionary = {"valid": false, "quoted_payment": 0,
        "top_up": 999, "payer_balance": 0}
    var c1: Dictionary = Dispatch._selector_bid_context(rows, controllers,
        first, "a", "third", "Alpha", ship, 2.0, systems, q1,
        "job", knowledge, 10)
    var c2: Dictionary = Dispatch._selector_bid_context(rows, controllers,
        first, "b", "third", "Alpha", ship, 2.0, systems, q2,
        "job", knowledge, 10)
    _check(not is_same(c1, c2), "bid contexts must not alias")
    _check(not is_same(c1["quotes"], c2["quotes"]),
        "quote dictionaries must not alias")
    _check(not is_same(c1["memory"], c2["memory"]),
        "memory wrappers must not alias")
    _check(Selector.select_contract(c2).is_empty(),
        "invalid quote must remain rejected")
    _check(not Selector.select_contract(c1).is_empty(),
        "valid paid quote must remain accepted")
    # New proposal and N38 restore must allocate fresh cache, not reuse views.
    var restored_cache: Dictionary = {}
    var changed_base: Dictionary = {"buyer": false, "seller": false}
    var changed: Dictionary = Dispatch._offer_commerce_view(
        restored_cache, "third", changed_base)
    _check(not changed["buyer"] and not changed["seller"],
        "proposal-local commerce must invalidate after world change")
    _check(first["buyer"] and first["seller"],
        "old immutable view must remain unchanged")
    return {"ok": true, "cases": 9, "negative": 4}
