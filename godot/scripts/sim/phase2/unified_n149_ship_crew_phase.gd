extends RefCounted
## Frozen Rust sim_core/agents/ship/mod.rs::tick_crew (N149) applied
## ONCE to N140-fired real N39 ship rows, in original 5-stage order.
## The N9 ledger is the ONLY spendable credit owner; ShipCrew.wages_credits
## is the original nonspendable accrued statistic, not a second wallet.
const SourceCrew = preload("res://scripts/sim/phase1/n149_native_crew_tick_single_owner.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const CrewRoster = preload("res://scripts/sim/ships/native_crew_roster.gd")

static func _fail(reason: String, ship_id: String = "") -> Dictionary:
    return {"ok": false, "reason": reason, "ship_id": ship_id}

static func _legacy_crew(ship: Dictionary) -> Dictionary:
    # Only older P2 saves without a ShipCrew may use the exact native
    # spawner defaults; never overwrite an existing tired/unpaid crew.
    var size: int = int(ship.get("crew_size", -1))
    if size < 0 or not (ship.get("crew_roles") is Array):
        return {}
    if size != (ship["crew_roles"] as Array).size():
        return {}
    return {"size": size, "hunger": CrewRoster.INITIAL_HUNGER,
        "morale": CrewRoster.INITIAL_MORALE,
        "fatigue": CrewRoster.INITIAL_FATIGUE,
        "health": CrewRoster.INITIAL_HEALTH,
        "current_task": "idle", "wages_credits": 0, "dirty": false}

static func stage(world: Dictionary, ledger_snapshot: Dictionary,
        tick: int, tick_scale: float, multiplier: int,
        n140_fired: Dictionary) -> Dictionary:
    if tick < 1 or multiplier < 1 or not is_finite(tick_scale) or tick_scale < 0.0:
        return _fail("n149_invalid_source_clock")
    if not (world.get("ships") is Dictionary):
        return _fail("n149_no_live_canonical_fleet")
    if not (ledger_snapshot.get("balances") is Dictionary):
        return _fail("n149_no_single_n9_money")
    var money := Ledger.new()
    if not money.restore(ledger_snapshot):
        return _fail("n149_invalid_n9_snapshot")
    var next_ships: Dictionary = world["ships"].duplicate(true)
    var ids: Array = n140_fired.keys()
    ids.sort()
    var records: Array = []
    var wages_total: int = 0
    var food_total: int = 0
    var changed: bool = false
    for ship_id in ids:
        var sid: String = str(ship_id)
        if not next_ships.has(sid) or typeof(n140_fired[sid]) != TYPE_INT or int(n140_fired[sid]) < 1:
            return _fail("n149_foreign_n140_fired_ship", sid)
        var ship: Dictionary = next_ships[sid]
        if typeof(ship.get("credits", null)) != TYPE_INT or not (ship.get("cargo") is Dictionary):
            return _fail("n149_invalid_real_ship_cargo_or_wallet", sid)
        var real_credits: int = int(ship["credits"])
        var account: String = "ship:" + sid
        if money.balance(account) != real_credits:
            return _fail("n149_original_n9_ship_money_mismatch", sid)
        var crew: Variant = ship.get("crew", null)
        if crew == null:
            crew = _legacy_crew(ship)
        if not (crew is Dictionary) or crew.is_empty():
            return _fail("n149_invalid_original_ship_crew", sid)
        var cargo_ages: Variant = ship.get("cargo_age", {})
        if not (cargo_ages is Dictionary):
            return _fail("n149_invalid_actual_cargo_ages", sid)
        var original_efficiency: float = float(ship.get("crew_efficiency",
            clampf(float(crew.get("health", 100.0)) / 100.0 * 0.6 +
                float(crew.get("morale", 70.0)) / 100.0 * 0.4, 0.1, 1.0)))
        var facts: Dictionary = {
            "ship_id": sid, "crew": crew.duplicate(true),
            "economy": {"credits": real_credits,
                "efficiency": original_efficiency},
            "cargo": ship["cargo"].duplicate(true),
            "cargo_age": cargo_ages.duplicate(true),
            "roles": (ship.get("crew_roles", []) as Array).duplicate(true),
            "docked": not str(ship.get("docked_at", "")).is_empty(),
            "in_transit": not (ship.get("transit", {}) as Dictionary).is_empty()
        }
        var computed: Dictionary = SourceCrew.core_step(
            facts, tick, tick_scale, multiplier, int(n140_fired[sid]))
        if not computed.get("ok", false):
            return _fail("n149_source_" + str(computed.get("reason", "invalid")), sid)
        var projected: Dictionary = computed["projected_ship"]
        var effects: Dictionary = computed["effects"]
        var paid: int = -int(effects.get("ship_credits_delta", 0))
        var accrued: int = int(effects.get("crew_savings_delta", -1))
        var eaten: int = -int(effects.get("food_delta", 0))
        if paid < 0 or paid != accrued or eaten < 0:
            return _fail("n149_invalid_rust_effect_accounting", sid)
        if int(projected["economy"]["credits"]) != real_credits - paid or (
                int(projected["crew"]["wages_credits"]) !=
                int(crew["wages_credits"]) + accrued):
            return _fail("n149_ship_crew_wage_not_balanced", sid)
        if int(ship["cargo"].get("food", 0)) - int(projected["cargo"].get("food", 0)) != eaten:
            return _fail("n149_meal_did_not_consume_actual_cargo", sid)
        if paid > 0:
            var receipt_id: String = "n149:crew:" + sid + ":" + str(tick)
            var debit: Dictionary = money.pay_native_ship_crew(
                receipt_id, account, sid, paid, tick)
            if not debit.get("ok", false):
                return _fail("n149_n9_wages_" + str(debit.get("reason", "rejected")), sid)
        if money.balance(account) != int(projected["economy"]["credits"]):
            return _fail("n149_single_ship_wallet_diverged", sid)
        ship["crew"] = projected["crew"].duplicate(true)
        ship["crew_efficiency"] = float(projected["economy"]["efficiency"])
        ship["cargo"] = projected["cargo"].duplicate(true)
        ship["cargo_age"] = projected["cargo_age"].duplicate(true)
        ship["credits"] = int(projected["economy"]["credits"])
        wages_total += paid
        food_total += eaten
        changed = changed or ship != world["ships"][sid]
        records.append({"ship_id": sid, "tick": tick,
            "wages": paid, "food_consumed": eaten,
            "unpaid_wages": bool(effects.get("unpaid_wages", false)),
            "morale": float(ship["crew"]["morale"]),
            "efficiency": float(ship["crew_efficiency"]),
            "task": str(ship["crew"]["current_task"]),
            "skipped_ticks": int(n140_fired[sid])})
    if money.total() != _total_balances(ledger_snapshot) - wages_total:
        return _fail("n149_nonconservative_native_wage_outflow")
    return {"ok": true, "changed": changed, "ships": next_ships,
        "ledger_snapshot": money.snapshot(), "records": records,
        "wages_total": wages_total, "food_consumed": food_total,
        "fired_count": ids.size(), "tick": tick}

static func _total_balances(saved: Dictionary) -> int:
    var total: int = 0
    for value in saved.get("balances", {}).values():
        total += int(value)
    return total
