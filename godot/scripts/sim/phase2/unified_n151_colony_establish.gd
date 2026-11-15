extends RefCounted
## Miro B3 — native Rust engine/colony.rs::establish (PURE proposal).
## N39 owns the single World and N9: no market/ship/population/credits
## may be invented, only the existing N151 dock gets upgraded.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const N154 = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const METALS: int = 600
const WORK: int = 150
const CAPITAL: int = 20000

static func fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func native_market(location: String, facility: String,
        multiplier: int) -> Dictionary:
    if location.is_empty() or facility.is_empty() or multiplier < 1 or multiplier > 10000:
        return {}
    var prices: Dictionary = {}
    for slug in Catalog.ORDER:
        var price: float = Catalog.base_price(str(slug))
        if price <= 0.0 or not is_finite(price):
            return {}
        prices[str(slug)] = price
    # Rust MarketPricing::default, MarketFlow::default, MarketOrders and
    # MarketHistory::default; no warehouse stock and no imaginary producer.
    return {"id": "market-" + location, "location": location,
        "owner": facility, "supply": {}, "prices": prices,
        "demand": {"food": 5.0, "water": 3.0},
        "seed_demand": {"food": 5.0, "water": 3.0},
        "elasticity": 0.02, "spread": 0.10,
        "consumption_window": {},
        "orders": {"pending_buys": [], "pending_sells": [],
            "reserved": {}, "order_expiry_ticks": 50 * multiplier},
        "history": {"shortage_ticks": {}, "trend_samples": [],
            "spawned_at_tick": null, "last_tick": 0}, "limits": {}}

static func _verify_paid_history(world: Dictionary, bank: Dictionary,
        site: Dictionary, id: String) -> Dictionary:
    var receipts: Dictionary = world.get("construction_receipts", {})
    var contracts: Dictionary = world.get("contract_board", {}).get("contracts", {})
    var claims: Dictionary = world.get("contract_board", {}).get("receipt_claims", {})
    var money: Dictionary = bank.get("receipts", {})
    var delivered: int = 0
    var wages: int = 0
    var shipments: int = 0
    var shifts: int = 0
    var faction: String = str(site.get("faction_id", ""))
    var origin: String = str(site.get("labor", {}).get("colony_source", ""))
    var dest: String = str(site.get("location_name", ""))
    for key in receipts:
        var r: Dictionary = receipts[key]
        if str(r.get("site_id", "")) != id:
            continue
        var kind: String = str(r.get("kind", ""))
        if kind == "delivery":
            var cid: String = str(r.get("contract_id", ""))
            var c: Dictionary = contracts.get(cid, {})
            var amount: int = int(r.get("quantity", -1))
            var load: String = "contract:" + cid + ":load"
            var unload: String = "contract:" + cid + ":unload"
            var pay: String = "contract:" + cid + ":payout"
            var loaded: Dictionary = world.get("cargo_receipts", {}).get(load, {})
            var unloaded: Dictionary = world.get("cargo_receipts", {}).get(unload, {})
            var payment: Dictionary = money.get(pay, {})
            var ship: String = str(c.get("fulfiller_id", ""))
            var legs: Variant = payment.get("legs", null)
            if not (legs is Array) or legs.size() != 2 or (
                    not (legs[0] is Dictionary) or
                    not (legs[1] is Dictionary)):
                return fail("b3_invalid_original_escrow_payout_legs")
            if amount <= 0 or amount > 200 or (
                    str(world.get("construction_contracts", {}).get(cid, "")) != id or
                    str(c.get("contract_type", "")) != "construction" or
                    str(c.get("mission_category", "")) != "strategy.colony.v1" or
                    str(c.get("colony_site_id", "")) != id or
                    str(c.get("faction_id", "")) != faction or
                    str(c.get("status", "")) != "paid" or
                    int(c.get("reserved", -1)) != 0 or
                    int(c.get("quantity", -1)) != amount or
                    str(c.get("picked_up_receipt", "")) != load or
                    str(c.get("delivered_receipt", "")) != unload or
                    not claims.has(load) or not claims.has(unload) or
                    str(r.get("n15_receipt_id", "")) != unload or
                    str(r.get("n9_receipt_id", "")) != pay or
                    loaded.get("quantities", {}) != {"metals": amount} or
                    str(loaded.get("ship_id", "")) != ship or
                    str(loaded.get("action", "")) != "load" or
                    str(loaded.get("location_id", "")) != origin or
                    unloaded.get("quantities", {}) != {"metals": amount} or
                    str(unloaded.get("kind", "")) != "construction_site" or
                    str(unloaded.get("action", "")) != "unload" or
                    str(unloaded.get("site_id", "")) != id or
                    str(unloaded.get("ship_id", "")) != ship or
                    str(unloaded.get("location_id", "")) != dest or
                    str(payment.get("kind", "")) != "contract_payment" or
                    not (legs is Array) or legs.size() != 2 or
                    str(legs[0].get("account", "")) != str(c.get("escrow_account", "")) or
                    int(legs[0].get("delta", 0)) != -int(c.get("agreed_payment", -1)) or
                    str(legs[1].get("account", "")) != Schema.ship_account(ship) or
                    int(legs[1].get("delta", 0)) != int(c.get("agreed_payment", -1))):
                return fail("b3_unbacked_real_paid_n15_metals")
            delivered += amount
            shipments += 1
        elif kind == "labor":
            var receipt_id: String = str(r.get("n9_receipt_id", ""))
            var spent: int = int(r.get("wages", -1))
            var pay: Dictionary = money.get(receipt_id, {})
            var legs: Variant = pay.get("legs", null)
            if receipt_id != str(key) or spent <= 0 or (
                    str(pay.get("kind", "")) != "n141_native_paid_construction_work" or
                    int(pay.get("tick", -1)) != int(r.get("tick", -2)) or
                    not (legs is Array)):
                return fail("b3_missing_real_n141_wage_receipt")
            var debited: int = 0
            var credited: int = 0
            for line in legs:
                if not (line is Dictionary):
                    return fail("b3_invalid_n9_labor_leg")
                var account: String = str(line.get("account", ""))
                var delta: int = int(line.get("delta", 0))
                if account == Schema.faction_account(faction) and delta < 0:
                    debited += -delta
                elif account.begins_with("population/") and delta > 0:
                    credited += delta
                else:
                    return fail("b3_unrecognized_n141_wage_counterparty")
            if debited != spent or credited != spent:
                return fail("b3_unbalanced_n141_wages")
            wages += spent
            shifts += 1
    if delivered != METALS or wages != WORK or shipments < 3 or shifts < 1 or (
            int(site.get("progress_delivered", -1)) != delivered or
            int(site.get("labor", {}).get("completed", -1)) != wages):
        return fail("b3_600_real_metals_or_150_paid_labor_missing")
    return {"ok": true, "delivered": delivered, "wages": wages,
        "shipments": shipments, "shifts": shifts}

static func stage(world: Dictionary, bank: Dictionary,
        id: String, tick: int, multiplier: int) -> Dictionary:
    if id.is_empty() or tick < 1 or multiplier < 1 or multiplier > 10000:
        return fail("b3_invalid_original_tick")
    var site: Dictionary = world.get("construction_sites", {}).get(id, {})
    if site.is_empty() or not (site.get("labor") is Dictionary) or (
            site["labor"].get("colony_source", null) == null or
            bool(site.get("completed", false)) or
            int(site.get("progress_required", -1)) != METALS or
            int(site["labor"].get("required", -1)) != WORK or
            not N154.ready_for_materialization(site)):
        return fail("b3_not_genuine_completed_original_site")
    var location: String = str(site.get("location_name", ""))
    var faction: String = str(site.get("faction_id", ""))
    var body: String = str(site.get("body_id", ""))
    var dock_proof: Dictionary = world.get("construction_receipts", {}).get(
        "n151_colony_dock:" + id, {})
    var fid: String = str(dock_proof.get("facility_id", ""))
    var pid: String = str(dock_proof.get("population_id", ""))
    var dock: Dictionary = world.get("facilities", {}).get(fid, {})
    var home: Dictionary = world.get("populations", {}).get(pid, {})
    if location != body + "-colony" or location.is_empty() or (
            str(dock_proof.get("kind", "")) != "colony_dock_prepared" or
            str(dock_proof.get("site_id", "")) != id or
            str(dock_proof.get("destination_location", "")) != location or
            str(dock_proof.get("faction_id", "")) != faction or
            str(dock.get("type", "")) != "construction_dock" or
            str(dock.get("location", "")) != location or
            str(dock.get("faction", "")) != faction or
            str(dock.get("body_id", "")) != body or
            str(dock.get("construction_source_site_id", "")) != id or
            str(home.get("colony_dock_id", "")) != fid or
            str(home.get("location", "")) != location or
            str(home.get("faction", "")) != faction or
            int(home.get("count", 0)) <= 0 or
            world.get("markets", {}).has(location)):
        return fail("b3_original_temporary_dock_not_found")
    for other in world.get("facilities", {}):
        if str(other) != fid and str(
                world["facilities"][other].get("location", "")) == location:
            return fail("b3_destination_already_has_real_facility")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return fail("b3_one_n9_ledger_unavailable")
    var payer: String = Schema.faction_account(faction)
    var payee: String = Schema.facility_account(fid)
    if ledger.balance(payer) < CAPITAL or (
            ledger.balance(payer) != int(world.get("faction_treasuries", {}).get(faction, -1)) or
            ledger.balance(payee) != int(dock.get("credits", -1))):
        return fail("insufficient_startup_capital")
    if int(dock.get("credits", 0)) > Ledger.MAX_CREDITS - CAPITAL:
        return fail("credit_overflow")
    var proof: Dictionary = _verify_paid_history(world, bank, site, id)
    if not proof.get("ok", false):
        return proof
    for cid in world.get("construction_contracts", {}):
        if str(world["construction_contracts"][cid]) != id:
            continue
        var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
        if str(c.get("status", "")) not in ["paid", "expired"]:
            return fail("b3_active_original_n104_shipment")
    var market: Dictionary = native_market(location, fid, multiplier)
    if market.is_empty():
        return fail("b3_invalid_original_market_catalog")
    var history_id: String = "n151_colony_established:" + id
    var money_id: String = "native_colony_establish:" + id + ":" + str(tick)
    if world.get("construction_receipts", {}).has(history_id) or ledger.has_receipt(money_id):
        return fail("b3_replayed_original_colony_completion")
    var transfer: Dictionary = ledger.transfer(money_id, payer, payee,
        CAPITAL, tick, "native_n151_colony_startup_capital")
    if not transfer.get("ok", false):
        return transfer
    var staged: Dictionary = world.duplicate(true)
    staged["faction_treasuries"][faction] = ledger.balance(payer)
    staged["facilities"][fid]["credits"] = ledger.balance(payee)
    staged["facilities"][fid]["type"] = "station"
    staged["facilities"][fid]["condition"] = 1.0
    var services: Array = staged["facilities"][fid].get("services", []).duplicate(true)
    if not services.has("market"):
        services.append("market")
    staged["facilities"][fid]["services"] = services
    # Rust tick_construction_labor preserves the FINAL N141 WorkShift
    # on the upgraded facility crew in the same tick. N39 station
    # snapshots use a per-household worker map instead of Rust tuples.
    var source_shift: Variant = site.get("labor", {}).get("last_shift", null)
    if source_shift is Dictionary:
        var crew_workers: Dictionary = {}
        var shift_rows: Variant = source_shift.get("workers", null)
        if not (shift_rows is Array):
            return fail("b3_missing_original_n141_last_shift")
        for pair in shift_rows:
            if not (pair is Array) or pair.size() != 2 or (
                    crew_workers.has(str(pair[0])) or int(pair[1]) <= 0):
                return fail("b3_invalid_original_final_shift")
            crew_workers[str(pair[0])] = int(pair[1])
        staged["facilities"][fid]["work_shift"] = {
            "tick": int(source_shift.get("tick", -1)),
            "workers": crew_workers}
    staged["markets"][location] = market
    var closed: Array = []
    for cid in staged["construction_contracts"].keys():
        if str(staged["construction_contracts"][cid]) == id:
            closed.append(str(cid))
            staged["construction_contracts"].erase(cid)
    staged["construction_sites"].erase(id)
    # Immutable original source evidence is retained in N38. The new
    # receipt certifies the deleted ConstructionSite without keeping a
    # phantom working site, while original N9 and N104 history stays.
    staged["construction_receipts"][history_id] = {
        "id": history_id, "kind": "colony_established",
        "site_id": id, "tick": tick, "facility_id": fid,
        "population_id": pid, "market_id": str(market["id"]),
        "destination_location": location, "faction_id": faction,
        "body_id": body, "native_db_id": int(dock.get("native_db_id", 0)),
        "capital": CAPITAL, "n9_receipt_id": money_id,
        "delivered_metals": int(proof["delivered"]),
        "paid_labor": int(proof["wages"]),
        "shipments": int(proof["shipments"]),
        "shifts": int(proof["shifts"]),
        "retired_contract_ids": closed.duplicate(true),
        "executor_id": str(site.get("labor", {}).get("last_executor", ""))}
    return {"ok": true, "status": "B3_REAL_N151_SAME_DOCK_ESTABLISHED",
        "world": staged, "ledger_snapshot": ledger.snapshot(),
        "site_id": id, "facility_id": fid, "population_id": pid,
        "market_id": str(market["id"]), "location": location,
        "capital": CAPITAL, "n9_receipt_id": money_id,
        "construction_receipt": history_id,
        "delivered_metals": METALS, "paid_labor": WORK,
        "retired_contract_ids": closed, "tick": tick}
