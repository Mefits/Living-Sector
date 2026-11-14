extends RefCounted
## N121. Frozen Rust planning/native_execution.rs::{unique_market,
## unique_global_market, observed_stock, contract_receipt,
## production_receipt, native_recipe_output_total}.
## Pure SOURCE EVIDENCE: never certify a planner forecast as a receipt.
## Return receipt INTENTS for N98 PlanLedger.apply_receipt in Phase 2.
const State = preload("res://scripts/port/n121_native_execution_state.gd")
const RECIPE_INTERVAL_BASE: int = 5
const RECEIPT_EPSILON: float = 0.0001

## Snapshot owned_markets alone is insufficient: must verify exactly
## ONE physical global MarketIdentity at the location, with the same ID.
static func unique_owned_market(snapshot: Dictionary,
        location: String) -> Dictionary:
    var markets: Variant = snapshot.get("owned_markets", null)
    if not (markets is Array):
        return _err("missing_owned_markets")
    var found: Dictionary = {}
    for entry in markets:
        if not (entry is Dictionary):
            return _err("invalid_owned_market")
        if str(entry.get("location_id", "")) == location:
            if not found.is_empty():
                return _err("ambiguous_market")
            found = entry
    if found.is_empty() or str(found.get("market_id", "")).is_empty():
        return _err("market_not_found")
    return {"ok": true, "market": found.duplicate(true)}

static func unique_global_market(world: Dictionary, location: String,
        market_id: String) -> bool:
    var markets: Variant = world.get("global_markets", null)
    if not (markets is Array):
        return false
    var count: int = 0
    for entry in markets:
        if not (entry is Dictionary):
            return false
        if str(entry.get("location_id", "")) == location:
            count += 1
            if str(entry.get("market_id", "")) != market_id:
                return false
    return count == 1

static func commodity_stock(snapshot: Dictionary, world: Dictionary,
        location: String, commodity: String) -> Dictionary:
    var unique: Dictionary = unique_owned_market(snapshot, location)
    if not bool(unique.get("ok", false)):
        return unique
    var market: Dictionary = unique["market"]
    if not unique_global_market(world, location,
            str(market.get("market_id", ""))):
        return _err("native_global_market_ambiguity")
    var stock: Variant = market.get("stock", null)
    if not (stock is Dictionary):
        return _err("missing_stock")
    var quantity: Variant = stock.get(commodity, 0.0)
    if not _number(quantity) or float(quantity) < 0.0:
        return _err("invalid_observed_stock")
    return {"ok": true, "stock": float(quantity),
        "market_id": str(market["market_id"])}

## Rust terminal/native observed_stock accepts only unique owned physical
## stock; no sum of co-located faction and foreign market quantities.
static func goal_stock(snapshot: Dictionary, world: Dictionary,
        goal: Dictionary) -> Dictionary:
    return commodity_stock(snapshot, world,
        str(goal.get("destination_id", "")),
        str(goal.get("commodity", "")))

static func stock_verified(snapshot: Dictionary, world: Dictionary,
        goal: Dictionary) -> Dictionary:
    var observed: Dictionary = goal_stock(snapshot, world, goal)
    if not bool(observed.get("ok", false)):
        return observed
    return {"ok": true, "verified":
        float(observed["stock"]) >= float(goal.get("target_units", -1)),
        "observed": observed["stock"]}

static func action_for_step(plan: Dictionary, step_id: String) -> Dictionary:
    if not (plan.get("ledger", null) is Dictionary):
        return _err("missing_ledger")
    var action_id: String = ""
    for record in plan["ledger"].get("steps", []):
        if not (record is Dictionary) or not (record.get("step", null) is Dictionary):
            return _err("invalid_step_record")
        if str(record["step"].get("step_id", "")) == step_id:
            action_id = str(record["step"].get("action_id", ""))
            break
    if action_id.is_empty():
        return _err("missing_action_for_step")
    for action in plan.get("actions", []):
        if action is Dictionary and str(action.get("action_id", "")) == action_id:
            return {"ok": true, "action": action.duplicate(true)}
    return _err("missing_action_for_step")

## Rust contract_receipt maps Posted→Submitted, Accepted/PickedUp/
## Delivered→Running, Paid→Succeeded, Expired→Failed ONLY if
## escrow.refunded. A stale Posted must NOT downgrade Running.
static func contract_receipt(plan: Dictionary, board: Dictionary,
        step_id: String, order_id: String, tick: int) -> Dictionary:
    if order_id.begins_with("facility:"):
        return {"ok": true, "reason": "await_native_production",
            "receipt": null}
    var contract: Variant = board.get(order_id, null)
    if not (contract is Dictionary):
        return {"ok": true,
            "reason": "missing_native_contract_manual_reconcile",
            "receipt": null}
    var ledger: Dictionary = plan.get("ledger", {})
    if str(contract.get("requestor_id", "")) != str(ledger.get("faction_id", "")):
        return {"ok": true, "reason": "native_contract_wrong_faction",
            "receipt": null}
    var status: String = str(contract.get("status", ""))
    var receipt_status: String = ""
    match status:
        "posted":
            receipt_status = "submitted"
        "accepted", "picked_up", "delivered":
            receipt_status = "running"
        "paid":
            receipt_status = "succeeded"
        "expired":
            var funding: Variant = contract.get("funding", null)
            if funding is Dictionary and int(funding.get("reserved", 0)) > 0:
                return {"ok": true, "reason": "await_native_refund",
                    "receipt": null}
            receipt_status = "failed"
        _:
            return _err("unknown_contract_status")
    var phase: String = ""
    for record in ledger.get("steps", []):
        if str(record.get("step", {}).get("step_id", "")) == step_id:
            phase = str(record.get("phase", ""))
            break
    if phase.is_empty():
        return _err("missing_step")
    if receipt_status == "submitted" and phase == "running":
        return {"ok": true, "reason": "waiting_native_contract",
            "receipt": null}
    var receipt: Dictionary = _receipt(plan, step_id, order_id,
        receipt_status, "native_contract_" + status, tick)
    return {"ok": true, "reason": "native_contract_checked",
        "receipt": receipt}

## This module only verifies actual source FacilityCrew.WorkShift
## counters. A paid shift must occur AFTER plan.ledger.created_tick;
## all recipe outputs need their OWN positive cumulative counters
## (process_ice produces water and fuel, not just water).
static func production_receipt(world: Dictionary, snapshot: Dictionary,
        plan: Dictionary, step_id: String, native_order_id: String,
        tick: int, mult: int) -> Dictionary:
    var chosen: Dictionary = action_for_step(plan, step_id)
    if not bool(chosen.get("ok", false)):
        return _waiting("missing_production_action")
    var action: Dictionary = chosen["action"]
    if str(action.get("kind", "")) != "produce":
        return _waiting("not_production_action")
    var facility_type: String = str(action.get("required_facility_type", ""))
    if facility_type.is_empty():
        return _waiting("no_production_facility_type")
    var location: String = str(action.get("destination_id", ""))
    var unique: Dictionary = unique_owned_market(snapshot, location)
    if not bool(unique.get("ok", false)):
        return _waiting("ambiguous_production_market")
    if not native_order_id.begins_with("facility:"):
        return _waiting("invalid_production_native_id")
    var facility_id: String = native_order_id.trim_prefix("facility:")
    var pins: Variant = world.get("producer_recipe_pins", null)
    if not (pins is Dictionary) or not (pins.get(str(action.get("action_id", "")), null) is Dictionary):
        return _waiting("producer_recipe_identity_changed")
    var pin: Dictionary = pins[str(action["action_id"])]
    if str(pin.get("facility_id", "")) != facility_id             or str(action.get("source_id", "")) != facility_id:
        return _waiting("producer_identity_changed")
    var recipe: String = str(pin.get("recipe_id", ""))
    if recipe.is_empty():
        return _waiting("producer_recipe_identity_changed")
    var started: Variant = plan.get("production_started_tick", null)
    if typeof(started) != TYPE_INT or int(started) < 0:
        return _waiting("production_start_missing")
    if not unique_global_market(world, location,
            str(unique["market"].get("market_id", ""))):
        return _waiting("production_global_market_ambiguity")
    var facilities: Variant = world.get("facilities", null)
    if not (facilities is Dictionary) or not (facilities.get(facility_id, null) is Dictionary):
        return _waiting("producer_identity_changed")
    var fac: Dictionary = facilities[facility_id]
    var ledger: Dictionary = plan.get("ledger", {})
    var paid: bool = (
        str(fac.get("id", "")) == facility_id
        and str(fac.get("faction_id", "")) == str(ledger.get("faction_id", ""))
        and str(fac.get("facility_type", "")) == facility_type
        and str(fac.get("location", "")) == location)
    var shift: Variant = fac.get("work_shift", null)
    if shift is Dictionary:
        var last: Variant = (shift.get("last_recipe_ticks", {}) as Dictionary).get(recipe, null)
        paid = (paid and typeof(last) == TYPE_INT
            and int(last) > int(ledger.get("created_tick", -1)))
    else:
        paid = false
    var outputs: Variant = action.get("outputs", null)
    if not (outputs is Array) or outputs.is_empty():
        return _waiting("invalid_recipe_outputs")
    var counters: Dictionary = {}
    if shift is Dictionary and shift.get("produced_outputs", null) is Dictionary:
        var raw: Variant = shift["produced_outputs"].get(recipe, {})
        if raw is Dictionary:
            counters = raw
    var baselines: Dictionary = plan.get("production_baselines", {})
    var accounted: Dictionary = plan.get("production_accounted", {})
    var new_accounting: Dictionary = accounted.duplicate(true)
    var fully_measured: bool = true
    var missing_baseline: bool = false
    for raw_output in outputs:
        var output: Dictionary = State.output_spec(raw_output)
        if output.is_empty():
            return _waiting("invalid_original_recipe_outputs")
        var commodity: String = str(output["commodity"])
        var units: int = int(output["quantity"])
        if units <= 0 or commodity.is_empty():
            fully_measured = false
            continue
        var start_value: Variant = State.output_value(baselines, action, commodity)
        var before_value: Variant = State.output_value(accounted, action, commodity)
        var observed: Variant = counters.get(commodity, null)
        if start_value == null:
            missing_baseline = true
            fully_measured = false
            continue
        if not _number(start_value) or not _number(observed):
            fully_measured = false
            continue
        var before: float = float(before_value) if _number(before_value)             else float(start_value)
        var end: float = before + float(units)
        if (not is_finite(end) or not is_finite(before)
                or float(observed) + RECEIPT_EPSILON < end):
            fully_measured = false
            continue
        new_accounting[State.output_key(action, commodity)] = end
    # Legacy source checkpoint: missing product-qualified baselines
    # cannot supply accounting. Fall back to ONE genuine paid shift and
    # visible >= full recipe output for every commodity, no previous
    # Succeeded instance of SAME action within this plan.
    var legacy: bool = false
    if missing_baseline and paid:
        var source_outputs_visible: bool = true
        for raw_output in outputs:
            var output: Dictionary = State.output_spec(raw_output)
            if output.is_empty():
                source_outputs_visible = false
                break
            var value: Dictionary = commodity_stock(snapshot, world,
                location, str(output["commodity"]))
            if (not bool(value.get("ok", false))
                    or float(value.get("stock", 0.0)) <
                    float(output["quantity"])):
                source_outputs_visible = false
                break
        var own: Dictionary = commodity_stock(snapshot, world,
            location, str(action.get("commodity", "")))
        var own_visible: bool = (bool(own.get("ok", false))
            and float(own["stock"]) >= float(action.get("units", 0)))
        var already_used: bool = false
        for record in ledger.get("steps", []):
            if (str(record.get("step", {}).get("step_id", "")) != step_id
                    and str(record.get("step", {}).get("action_id", "")) ==
                    str(action.get("action_id", ""))
                    and str(record.get("phase", "")) == "succeeded"):
                already_used = true
        legacy = source_outputs_visible and own_visible and not already_used
    if paid and (fully_measured or legacy):
        var reason: String = (
            "native_recipe_paid_and_all_outputs_confirmed"
            if fully_measured else "legacy_paid_shift_and_all_outputs_visible"
        )
        return {"ok": true, "reason": "native_production_confirmed",
            "receipt": _receipt(plan, step_id, native_order_id,
                "succeeded", reason, tick),
            "accounted_after_ack": new_accounting if fully_measured else null}
    if tick >= int(started) + 5 * RECIPE_INTERVAL_BASE * maxi(mult, 1):
        return {"ok": true, "reason": "native_production_timeout",
            "receipt": _receipt(plan, step_id, native_order_id,
                "failed", "production_not_confirmed_before_deadline", tick),
            "accounted_after_ack": null}
    return _waiting("await_paid_production_and_stock")

static func _receipt(plan: Dictionary, step_id: String, native_id: String,
        status: String, reason: String, tick: int) -> Dictionary:
    return {"plan_id": str(plan.get("ledger", {}).get("plan_id", "")),
        "step_id": step_id, "native_order_id": native_id,
        "status": status, "reason_code": reason, "tick": tick}

static func _waiting(reason: String) -> Dictionary:
    return {"ok": true, "reason": reason, "receipt": null}

static func _number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _err(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "receipt": null}
