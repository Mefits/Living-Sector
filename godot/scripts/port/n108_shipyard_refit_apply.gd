extends RefCounted
## N108: frozen sim_server/engine/admin.rs::{try_shipyard_refit,
## apply_fitting_swap, commit_shipyard_refit,admin_refit_ship} and
## apply.rs::RequestRefit. Caller must authorize admin commands externally.
##
## Returns whole detached world only after full preflight. No modules,
## credits or retrofit points created for free, no second market ledger.
const Catalog = preload("res://scripts/port/n108_shipyard_module_catalog.gd")
const MAX_I64: int = 9223372036854775807
const MAX_U32: int = 4294967295

## Agent RequestRefit consumes ONE retrofit point; only a docked ship
## with a real shipyard module, funds and a manufactured recipe qualifies.
static func agent_refit(world: Dictionary, ship_id: String,
        slot: String, slug: String) -> Dictionary:
    return _apply(world, ship_id, slot, slug, "agent_shipyard")

## Admin UI authenticated override; NO credits/stock/points. Rust
## admin_refit_ship(... via_shipyard=false) can also clear a slot.
## This function must not be exposed to the autonomous ship planner.
static func admin_override(world: Dictionary, ship_id: String,
        slot: String, slug: Variant) -> Dictionary:
    return _apply(world, ship_id, slot, slug, "admin_override")

## Admin UI authenticated shipyard path charges real credits/stock but
## does NOT spend a ship retrofit point (unlike agent RequestRefit).
static func admin_shipyard(world: Dictionary, ship_id: String,
        slot: String, slug: String) -> Dictionary:
    return _apply(world, ship_id, slot, slug, "admin_shipyard")

static func _apply(world: Dictionary, ship_id: String,
        slot: String, slug: Variant, mode: String) -> Dictionary:
    if ship_id.is_empty() or not Catalog.SLOTS.has(slot):
        return _reject("invalid_refit_identity_or_slot")
    if not (world.get("ships", null) is Dictionary):
        return _reject("missing_ship_registry")
    var origin: Variant = world["ships"].get(ship_id, null)
    if not (origin is Dictionary) or str(origin.get("id", "")) != ship_id:
        return _reject("no_ship")
    var base: Variant = Catalog.CLASSES.get(str(origin.get("class", "")), null)
    if not (base is Dictionary):
        return _reject("no_class")
    if not (origin.get("fitting", null) is Dictionary):
        return _reject("missing_fitting")
    var fitting: Dictionary = origin["fitting"]
    if not (fitting.get("slots", null) is Dictionary):
        return _reject("missing_fitting_slots")
    var current: Dictionary = fitting["slots"]
    if current.size() != Catalog.SLOTS.size() or not current.has(slot):
        return _reject("invalid_fitting")
    var previous: Variant = current[slot]
    var clean_slug: Variant = null
    if slug != null:
        if not (slug is String) or not Catalog.MODULES.has(slug)                 or str(Catalog.MODULES[slug].get("slot", "")) != slot:
            return _reject("invalid_slug_or_slot")
        clean_slug = slug
    elif mode != "admin_override":
        return _reject("missing_shipyard_slug")
    var cost: int = 0
    var yard_id: String = ""
    if mode != "admin_override":
        if not (clean_slug is String):
            return _reject("invalid_shipyard_slug")
        var recipe: Dictionary = Catalog.slot_and_recipe(clean_slug, slot)
        if not bool(recipe.get("ok", false)):
            return _reject(str(recipe.get("reason", "invalid_recipe")))
        cost = int(recipe["cost"])
        var docked_at: Variant = origin.get("docked_at", null)
        if not (docked_at is String) or docked_at.is_empty():
            return _reject("not_docked")
        yard_id = str(docked_at)
        if not (world.get("facilities", null) is Dictionary):
            return _reject("missing_facility_registry")
        var operator: Variant = world["facilities"].get(yard_id, null)
        if not (operator is Dictionary):
            return _reject("not_shipyard")
        # Phase 1 source adapter calls the type "facility_type";
        # the only writable N39 World stores the same native kind as
        # "type". Accept either without copying or renaming the owner.
        if str(operator.get("facility_type", operator.get("type", ""))) != "shipyard":
            return _reject("not_shipyard")
        if not (operator.get("module_stock", null) is Dictionary):
            return _reject("no_module_stock")
        var modules: Dictionary = operator["module_stock"]
        if not (modules.get("stock", null) is Dictionary):
            return _reject("no_module_stock")
        var units: Variant = modules["stock"].get(clean_slug, 0)
        if typeof(units) != TYPE_INT or int(units) <= 0:
            return _reject("no_stock")
        if typeof(operator.get("credits", null)) != TYPE_INT                 or int(operator["credits"]) < 0:
            return _reject("missing_operator_wallet")
        if int(operator["credits"]) > MAX_I64 - cost:
            return _reject("shipyard_credit_overflow")
        var credits: Variant = origin.get("credits", null)
        if typeof(credits) != TYPE_INT or int(credits) < cost:
            return _reject("insufficient_credits")
    if mode == "agent_shipyard":
        var progress: Variant = origin.get("progression", null)
        if not (progress is Dictionary):
            return _reject("missing_ship_progression")
        var points: Variant = progress.get("retrofit_points", null)
        if typeof(points) != TYPE_INT or int(points) <= 0:
            return _reject("no_retrofit_points")
    if not ["agent_shipyard", "admin_shipyard", "admin_override"].has(mode):
        return _reject("invalid_refit_mode")
    var slots: Dictionary = current.duplicate(true)
    slots[slot] = clean_slug
    var effects: Dictionary = Catalog.combine(slots)
    if effects.is_empty():
        return _reject("invalid_resulting_fitting")
    var new_cargo: float = float(base["base_cargo"]) * float(effects["cargo_capacity_mult"])
    if not is_finite(new_cargo) or new_cargo < 0.0 or new_cargo > float(MAX_U32):
        return _reject("invalid_new_cargo_capacity")
    var new_speed: float = float(base["base_speed"]) * float(effects["speed_mult"])
    if not is_finite(new_speed) or new_speed <= 0.0:
        return _reject("invalid_new_speed_modifier")
    # Source does not check power_ok or current cargo used when shrinking
    # capacity; only exposes the derived budget and rebakes capacity.
    var staged: Dictionary = world.duplicate(true)
    var ship: Dictionary = staged["ships"][ship_id]
    ship["fitting"]["slots"] = slots
    ship["fitting"]["derived"] = effects
    ship["cargo_capacity"] = roundi(new_cargo)
    ship["speed_modifier"] = new_speed
    if ship.has("lifecycle_dirty"):
        ship["lifecycle_dirty"] = true
    if mode != "admin_override":
        var yard: Dictionary = staged["facilities"][yard_id]
        var stock: Dictionary = yard["module_stock"]
        stock["stock"][clean_slug] = int(stock["stock"][clean_slug]) - 1
        stock["dirty"] = true
        ship["credits"] = int(ship["credits"]) - cost
        yard["credits"] = int(yard["credits"]) + cost
        yard["dirty"] = true
    if mode == "agent_shipyard":
        ship["progression"]["retrofit_points"] = int(
            ship["progression"]["retrofit_points"]) - 1
        ship["progression"]["dirty"] = true
    var event: Dictionary = {
        "kind": "ship_refitted", "id": ship_id,
        "slot": slot, "from": previous, "to": clean_slug,
        "via": mode, "shipyard_id": yard_id if mode != "admin_override" else null,
        "cost": cost if mode != "admin_override" else null
    }
    return {"ok": true, "world": staged, "cost": cost,
        "previous": previous, "events": [event]}

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "events": []}
