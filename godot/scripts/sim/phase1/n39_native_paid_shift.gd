extends RefCounted
## N39 physical payroll from frozen agents/facility/workforce.rs.
## Uses existing N9 CreditLedger.commit; never maintains a second money ledger.
## Crew_count are jobs, NOT newly spawned people. Shared real households and
## construction/commander shift reservations are mandatory for labor safety.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const MAX_CREDITS: int = 9223372036854775807

static func occupied(state: Dictionary, tick: int, external_workers: Dictionary = {}) -> Dictionary:
    var result: Dictionary = external_workers.duplicate(true)
    for id in state["facilities"]:
        var shift: Dictionary = state["facilities"][id].get("work_shift", {})
        if not shift.is_empty() and int(shift.get("tick", -1)) == tick:
            for pid in shift.get("workers", {}):
                result[pid] = int(result.get(pid, 0)) + int(shift["workers"][pid])
    return result

static func validate_reservations(state: Dictionary, external_workers: Dictionary) -> String:
    for pid in external_workers:
        if not state["populations"].has(pid) or typeof(external_workers[pid]) != TYPE_INT or int(external_workers[pid]) < 0:
            return "invalid_external_labor_receipt"
        var pop: Dictionary = state["populations"][pid]
        if int(external_workers[pid]) > int(int(pop["count"]) * 3 / 5):
            return "external_labor_exceeds_capacity"
    return ""

static func refresh_employment(state: Dictionary, tick: int, external_workers: Dictionary = {}) -> void:
    var counts: Dictionary = occupied(state, tick, external_workers)
    for id in state["populations"]:
        var pop: Dictionary = state["populations"][id]
        var capacity: float = maxf(1.0, float(pop["count"]) * 0.6)
        pop["employed_fraction"] = clampf(float(counts.get(id, 0)) / capacity, 0.0, 1.0)

## input_payment=null is Rust stock-owner commissioned processing:
##  - self-owned: producer pays wages directly
##  - different owner: owner pays wages + ceil(wages/10) fee, producer gets fee
## input_payment=int means producer buys local same-faction stock and pays wages.
## Full debit/credit legs are checked BEFORE any household, shift or stock mutation.
static func pay_shift(state: Dictionary, ledger: RefCounted, producer_id: String,
        owner_id: String, tick: int, external_workers: Dictionary = {},
        input_payment: Variant = null) -> Dictionary:
    var facilities: Dictionary = state["facilities"]
    if not facilities.has(producer_id) or not facilities.has(owner_id):
        return _blocked(state, producer_id, "missing_employer")
    var producer: Dictionary = facilities[producer_id]
    var owner: Dictionary = facilities[owner_id]
    var old_shift: Dictionary = producer.get("work_shift", {})
    if not old_shift.is_empty() and int(old_shift.get("tick", -1)) >= tick:
        return {"ok": false, "reason": "already_worked_this_tick"}
    if input_payment == null and bool(state.get("station_executing", false)) and int(producer.get("assigned_workers", 0)) <= 0:
        return _blocked(state, producer_id, "station_workforce_not_assigned")
    var required: int = int(producer["crew_count"])
    if required <= 0:
        return _blocked(state, producer_id, "no_staffed_jobs")
    if str(producer["faction"]) != str(owner["faction"]) or str(producer["location"]) != str(owner["location"]):
        return _blocked(state, producer_id, "foreign_workplace_stock")
    var used: Dictionary = occupied(state, tick, external_workers)
    var ids: Array = state["populations"].keys()
    ids.sort()
    var needed: int = required
    var assignments: Dictionary = {}
    for pid in ids:
        var person: Dictionary = state["populations"][pid]
        if str(person["faction"]) != str(producer["faction"]) or str(person["location"]) != str(producer["location"]):
            continue
        var capacity: int = int(int(person["count"]) * 3 / 5)
        var available: int = maxi(0, capacity - int(used.get(pid, 0)))
        var amount: int = mini(needed, available)
        if amount <= 0:
            continue
        if ledger.balance(Schema.household_account(str(pid))) < 0:
            return _blocked(state, producer_id, "invalid_household_balance")
        assignments[pid] = amount
        needed -= amount
        if needed == 0:
            break
    if needed != 0:
        return _blocked(state, producer_id, "insufficient_workers")
    var wages: int = required  # Rust WAGE_PER_SHIFT = 1 CR/worker.
    var producer_account: String = Schema.facility_account(producer_id)
    var owner_account: String = Schema.facility_account(owner_id)
    var producer_cash: int = ledger.balance(producer_account)
    var owner_cash: int = ledger.balance(owner_account)
    if producer_cash < 0 or owner_cash < 0:
        return _blocked(state, producer_id, "invalid_cash_balance")
    var distinct: bool = producer_id != owner_id
    var fee: int = 0
    var service_debit: int = 0
    var cost: int = 0
    var legs: Array = []
    if input_payment != null:
        if typeof(input_payment) != TYPE_INT or int(input_payment) < 0:
            return _blocked(state, producer_id, "invalid_input_payment")
        cost = int(input_payment) if distinct else 0
        if cost > MAX_CREDITS - wages or producer_cash < wages + cost:
            return _blocked(state, producer_id, "insufficient_payroll_budget")
        legs.append({"account": producer_account, "delta": -(wages + cost)})
        if distinct and cost > 0:
            legs.append({"account": owner_account, "delta": cost})
    elif distinct:
        fee = int((wages + 9) / 10)
        service_debit = wages + fee
        if fee > MAX_CREDITS - wages or owner_cash < wages + fee:
            return _blocked(state, producer_id, "insufficient_processing_budget")
        legs.append({"account": owner_account, "delta": -(wages + fee)})
        legs.append({"account": producer_account, "delta": fee})
    else:
        if producer_cash < wages:
            return _blocked(state, producer_id, "insufficient_payroll_budget")
        legs.append({"account": producer_account, "delta": -wages})
    for pid in assignments:
        legs.append({"account": Schema.household_account(str(pid)), "delta": int(assignments[pid])})
    var operation_id: String = "n39/production/%s/%d" % [producer_id, tick]
    if ledger.has_receipt(operation_id):
        return _blocked(state, producer_id, "duplicate_operation")
    var payment: Dictionary = ledger.commit(operation_id, legs, tick, "native_paid_production")
    if not payment.get("ok", false):
        return _blocked(state, producer_id, str(payment.get("reason", "credit_commit_failed")))
    # Everything below follows the sole atomic ledger.commit and cannot fail.
    producer["credits"] = ledger.balance(producer_account)
    owner["credits"] = ledger.balance(owner_account)
    for pid in assignments:
        var person: Dictionary = state["populations"][pid]
        person["wealth"] = ledger.balance(Schema.household_account(str(pid)))
        person["employed_fraction"] = clampf(
            float(int(used.get(pid, 0)) + int(assignments[pid])) /
            maxf(1.0, float(person["count"]) * 0.6), 0.0, 1.0)
    var shift: Dictionary = {
        "tick": tick, "workers": assignments.duplicate(true),
        "wages": wages, "input_payment": cost, "processing_fee": service_debit,
        "last_recipe_ticks": old_shift.get("last_recipe_ticks", {}).duplicate(true),
        "produced_outputs": old_shift.get("produced_outputs", {}).duplicate(true),
        "receipt": operation_id
    }
    producer["work_shift"] = shift
    producer["work_blocked_reason"] = ""
    return {"ok": true, "receipt": operation_id, "wages": wages, "processing_fee": service_debit,
        "input_payment": cost, "workers": assignments.duplicate(true)}

static func _blocked(state: Dictionary, producer_id: String, reason: String) -> Dictionary:
    if state["facilities"].has(producer_id):
        state["facilities"][producer_id]["work_blocked_reason"] = reason
    return {"ok": false, "reason": reason}
