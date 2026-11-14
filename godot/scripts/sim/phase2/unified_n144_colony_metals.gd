extends RefCounted
## Frozen Rust strategy/colony.rs::commission + engine/transactions.rs::
## deliver / engine/apply.rs::commit_contract_delivery / construction.rs.
## No market exists at destination: physical Metals leave a real ship hold
## into ONE already approved ConstructionSite after actual N21 docking.
## All operations are PURE stages; ONLY the original N39 World/N9 may Apply.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Fleet = preload("res://scripts/sim/phase2/unified_fleet_logistics.gd")
const Construction = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const ShipProgression = preload("res://scripts/sim/native/ship_progression_n101.gd")
const ShipLifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")

const PROJECT_TAG: String = "strategy.colony.v1"
const PAYMENT: int = 10000
const LOT: int = 200
const STARTUP: int = 20000
const FLOOR: int = 5000

class CargoEvidence extends RefCounted:
    var receipts: Dictionary = {}

static func _reject(why: String) -> Dictionary:
    return {"ok": false, "reason": why}

## Query against live one-World source, not a hypothetical warehouse.
static func source_quote(world: Dictionary, site_id: String) -> Dictionary:
    var site: Dictionary = world.get("construction_sites", {}).get(site_id, {})
    if site.is_empty() or bool(site.get("completed", false)) or (
            not (site.get("labor") is Dictionary) or
            site["labor"].get("colony_source", null) == null or
            str(site.get("commodity", "")) != "metals"):
        return _reject("b2_no_original_colony_site")
    var faction: String = str(site.get("faction_id", ""))
    var source: String = str(site["labor"].get("colony_source", ""))
    var destination: String = str(site.get("location_name", ""))
    var proof: Dictionary = world.get("construction_receipts", {}).get(
        "n151_colony_dock:" + site_id, {})
    var fid: String = str(proof.get("facility_id", ""))
    var dock: Dictionary = world.get("facilities", {}).get(fid, {})
    var home: Dictionary = world.get("markets", {}).get(source, {})
    if home.is_empty() or world.get("markets", {}).has(destination) or (
            str(proof.get("kind", "")) != "colony_dock_prepared" or
            str(dock.get("type", "")) != "construction_dock" or
            str(dock.get("location", "")) != destination or
            str(dock.get("faction", "")) != faction):
        return _reject("b2_no_real_marketless_original_destination")
    var left: int = int(site.get("progress_required", 0)) - int(site.get("progress_delivered", 0))
    var qty: int = mini(LOT, left)
    if left <= 0 or qty <= 0:
        return _reject("awaiting_paid_labor")
    var stock: float = float(home.get("supply", {}).get("metals", 0.0))
    var price: float = float(home.get("prices", {}).get("metals", 0.0))
    if not is_finite(stock) or stock < float(qty):
        return _reject("insufficient_affordable_metals")
    if not is_finite(price) or price <= 0.0:
        return _reject("b2_invalid_source_market_price")
    # Frozen Rust sourcing::purchase_cost uses actual seller/buyer
    # relations; a same-faction original station has the identity
    # sourcing tier. No invented discount or market quote.
    var controller: String = str(home.get("owner", ""))
    var owner: String = str(world.get("facilities", {}).get(controller, {}).get("faction", ""))
    if owner != faction:
        return _reject("b2_source_market_not_owned_by_faction")
    var posture: Dictionary = MarketRules.posture({}, faction, owner, 0)
    if not posture.get("ok", false):
        return _reject("b2_cannot_quote_original_source")
    var raw: float = ceil(price * float(qty) * float(posture["multiplier"]))
    if not is_finite(raw) or raw <= 0.0 or raw >= float(PAYMENT):
        return _reject("insufficient_affordable_metals")
    var minimum: int = STARTUP + maxi(0,
        int(site["labor"].get("required", 0)) - int(site["labor"].get("completed", 0)))
    var treasury: int = int(world.get("faction_treasuries", {}).get(faction, -1))
    if treasury < PAYMENT + minimum + FLOOR:
        return _reject("insufficient_colony_budget")
    # No empty market at the site is silently filled; stock is sold by
    # an original LIVE N97 source seller in a later physical ship pickup.
    return {"ok": true, "site_id": site_id, "faction_id": faction,
        "source": source, "destination": destination, "commodity": "metals",
        "quantity": qty, "payment": PAYMENT, "source_cost": int(raw),
        "dock_id": fid, "source_station": controller}

static func post(world: Dictionary, bank: Dictionary,
        site_id: String, tick: int, mult: int, graph: RefCounted) -> Dictionary:
    if tick < 1 or mult < 1 or graph == null:
        return _reject("b2_missing_original_tick_or_graph")
    var quote: Dictionary = source_quote(world, site_id)
    if not quote.get("ok", false):
        return quote
    var path: Dictionary = graph.shortest_path(str(quote["source"]), str(quote["destination"]))
    if not path.get("reachable", false):
        return _reject("b2_no_original_physical_directed_route")
    for c in world.get("contract_board", {}).get("contracts", {}).values():
        if str(c.get("requestor_id", "")) == Schema.faction_account(str(quote["faction_id"])) and (
                str(c.get("destination_location", "")) == str(quote["destination"]) and
                str(c.get("status", "")) not in ["paid", "expired"]):
            return _reject("colony_contract_in_progress")
    # Rust colony::commission longevity for Director-controlled source.
    var life: int = 800
    if world.get("research_directors", {}).has(str(quote["faction_id"])):
        life = maxi(800, int(path.get("distance", 0)) * 100 + 1200)
    if life > int((9223372036854775807 - tick) / mult):
        return _reject("b2_source_contract_expiry_overflow")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _reject("b2_missing_single_n9_ledger")
    var board := Board.new(ledger)
    if not board.restore(world.get("contract_board", {})):
        return _reject("b2_missing_single_n104_board")
    var cid: String = "n144/colony/metals/" + site_id + "/" + str(tick)
    var escrow: String = "escrow:" + cid
    if not ledger.register_empty_account(escrow):
        return _reject("b2_prepaid_contract_replay")
    var result: Dictionary = board.post(
        cid, "construction", Schema.faction_account(str(quote["faction_id"])),
        escrow, "metals", int(quote["quantity"]),
        str(quote["source"]), str(quote["destination"]), PAYMENT,
        tick, tick + life * mult, "faction")
    if not result.get("ok", false):
        return result
    var registered: Dictionary = board.snapshot()
    registered["contracts"][cid]["mission_category"] = PROJECT_TAG
    registered["contracts"][cid]["colony_site_id"] = site_id
    registered["contracts"][cid]["faction_id"] = str(quote["faction_id"])
    if not board.restore(registered):
        return _reject("b2_original_paid_metals_board_rejected")
    var staged: Dictionary = world.duplicate(true)
    staged["contract_board"] = board.snapshot()
    staged["faction_treasuries"][str(quote["faction_id"])] = ledger.balance(
        Schema.faction_account(str(quote["faction_id"])))
    staged["escrow_balances"][escrow] = ledger.balance(escrow)
    # N39's original construction-contract index points to the original
    # Site; no new warehouse and no stock or progress is created at post.
    staged["construction_contracts"][cid] = site_id
    return {"ok": true, "status": "N144_PREPAID_REAL_METALS_CONSTRUCTION",
        "world": staged, "ledger_snapshot": ledger.snapshot(),
        "site_id": site_id, "contract_id": cid, "escrow_account": escrow,
        "quantity": int(quote["quantity"]), "payment": PAYMENT,
        "source_cost": int(quote["source_cost"]), "tick": tick}

## Rust transactions.rs::deliver + apply.rs::commit_contract_delivery:
## after real arrival/dock, Metals move DIRECTLY from the ship hold to
## the actual construction site (NOT a phantom N15 warehouse). The
## original ContractBoard consumes one durable physical receipt,
## then N9 transfers the already-funded escrow to the ship wallet.
static func deliver(world: Dictionary, bank: Dictionary,
        cid: String, sid: String, tick: int) -> Dictionary:
    if tick < 1 or cid.is_empty() or sid.is_empty() or (
            not world.get("ships", {}).has(sid)):
        return _reject("b2_missing_real_ship_or_tick")
    var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
    var ship: Dictionary = world["ships"][sid]
    if str(c.get("contract_type", "")) != "construction" or (
            str(c.get("mission_category", "")) != PROJECT_TAG or
            str(c.get("status", "")) != "picked_up" or
            str(c.get("fulfiller_id", "")) != sid or
            str(ship.get("active_contract_id", "")) != cid or
            str(c.get("commodity", "")) != "metals"):
        return _reject("b2_not_original_active_colony_cargo")
    var site_id: String = str(c.get("colony_site_id", ""))
    var site: Dictionary = world.get("construction_sites", {}).get(site_id, {})
    var dest: String = str(c.get("destination_location", ""))
    var proof: Dictionary = world.get("construction_receipts", {}).get(
        "n151_colony_dock:" + site_id, {})
    var fid: String = str(proof.get("facility_id", ""))
    var dock: Dictionary = world.get("facilities", {}).get(fid, {})
    var qty: int = int(c.get("quantity", 0))
    if site.is_empty() or qty < 1 or qty > LOT or (
            str(world.get("construction_contracts", {}).get(cid, "")) != site_id or
            str(site.get("location_name", "")) != dest or
            str(site.get("commodity", "")) != "metals" or
            bool(site.get("completed", false)) or
            str(site.get("faction_id", "")) != str(c.get("faction_id", "")) or
            int(site.get("progress_required", 0)) - int(site.get("progress_delivered", 0)) < qty):
        return _reject("b2_original_site_cannot_consume_metals")
    if str(proof.get("kind", "")) != "colony_dock_prepared" or (
            str(dock.get("type", "")) != "construction_dock" or
            str(dock.get("location", "")) != dest or
            str(ship.get("docked_at", "")) != fid or
            str(ship.get("location", "")) != dest or
            not (ship.get("transit", {}) as Dictionary).is_empty()):
        return _reject("b2_n21_real_site_dock_required")
    # _open also checks real N21 occupant and every loaded ship N15 hold,
    # without registering any synthetic warehouse at this empty planet.
    var opened: Dictionary = Fleet._open(world)
    if not opened.get("ok", false):
        return opened
    var registry: RefCounted = opened["registry"]
    if not registry.occupants.has(fid) or not (registry.occupants[fid] as Array).has(sid):
        return _reject("b2_n21_real_dock_occupancy_missing")
    var hold: Dictionary = ship.get("cargo", {})
    var have: int = int(hold.get("metals", 0))
    if have < qty or qty > int(ship.get("cargo_capacity", 0)):
        return _reject("b2_unfunded_or_missing_physical_ship_metals")
    var pickup_id: String = "contract:" + cid + ":load"
    var pickup: Dictionary = world.get("cargo_receipts", {}).get(pickup_id, {})
    var expected_qty: Dictionary = {"metals": qty}
    if str(c.get("picked_up_receipt", "")) != pickup_id or (
            str(pickup.get("action", "")) != "load" or
            str(pickup.get("ship_id", "")) != sid or
            str(pickup.get("location_id", "")) != str(c.get("source_location", "")) or
            pickup.get("quantities", {}) != expected_qty or
            not world.get("contract_board", {}).get("receipt_claims", {}).has(pickup_id)):
        return _reject("b2_metal_has_no_real_n97_source_purchase")
    var receipt_id: String = "contract:" + cid + ":unload"
    var site_receipt_id: String = "native_construction_delivery:" + cid
    if world.get("cargo_receipts", {}).has(receipt_id) or (
            world.get("construction_receipts", {}).has(site_receipt_id)):
        return _reject("b2_replayed_original_physical_site_unload")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _reject("b2_invalid_original_n9")
    var board := Board.new(ledger)
    if not board.restore(world.get("contract_board", {})):
        return _reject("b2_invalid_original_n104")
    var physical := CargoEvidence.new()
    physical.receipts = world["cargo_receipts"].duplicate(true)
    board.bind_physical_cargo(physical)
    var staged: Dictionary = world.duplicate(true)
    # Rust apply.rs removes the actual quantity from ShipCargo and sends
    # it straight into ConstructionSite; one receipt is the evidence.
    var left: int = have - qty
    if left == 0:
        staged["ships"][sid]["cargo"].erase("metals")
        if staged["ships"][sid].get("cargo_age") is Dictionary:
            staged["ships"][sid]["cargo_age"].erase("metals")
        if staged["ships"][sid].get("cargo_origin") is Dictionary:
            staged["ships"][sid]["cargo_origin"].erase("metals")
    else:
        staged["ships"][sid]["cargo"]["metals"] = left
    var advanced: Dictionary = Construction.material_delivery(
        [site], staged["markets"], dest, "metals", qty)
    if not advanced.get("ok", false) or (
            advanced.get("fallback_to_market", true) or
            int(advanced.get("admitted_units", -1)) != qty):
        return _reject("b2_source_materials_not_fully_admitted")
    staged["construction_sites"][site_id] = (advanced["sites"][0] as Dictionary).duplicate(true)
    if staged["markets"] != world["markets"]:
        return _reject("b2_marketless_delivery_created_fake_stock")
    var receipt: Dictionary = {"ok": true, "action": "unload",
        "kind": "construction_site", "site_id": site_id,
        "ship_id": sid, "contract_id": cid, "facility_id": fid,
        "operation_id": receipt_id, "location_id": dest,
        "quantities": expected_qty, "tick": tick}
    staged["cargo_receipts"][receipt_id] = receipt.duplicate(true)
    physical.receipts[receipt_id] = receipt.duplicate(true)
    var delivered: Dictionary = board.confirm_delivery(cid, sid, tick, receipt_id)
    if not delivered.get("ok", false):
        return delivered
    var settled: Dictionary = board.settle(cid, sid,
        Schema.ship_account(sid), tick)
    if not settled.get("ok", false):
        return settled
    var payment: int = int(settled.get("paid", -1))
    if payment <= 0:
        return _reject("b2_missing_real_n9_funded_payout")
    staged["ships"][sid]["credits"] = ledger.balance(Schema.ship_account(sid))
    staged["escrow_balances"][str(c["escrow_account"])] = ledger.balance(str(c["escrow_account"]))
    staged["contract_board"] = board.snapshot()
    staged["construction_receipts"][site_receipt_id] = {
        "id": site_receipt_id, "kind": "delivery", "site_id": site_id,
        "contract_id": cid, "quantity": qty, "tick": tick,
        "n15_receipt_id": receipt_id, "n9_receipt_id": "contract:" + cid + ":payout"}
    staged["ships"][sid]["active_contract_id"] = ""
    staged["ships"][sid]["current_bt"] = null
    staged["ships"][sid]["current_goal"] = "idle"
    staged["ships"][sid]["max_source_cost"] = 0
    if ship.get("progression") is Dictionary:
        var xp: Dictionary = ShipProgression.grant_delivery_xp(ship["progression"])
        if not xp.get("ok", false):
            return _reject("b2_original_n101_ship_xp_rejected")
        staged["ships"][sid]["progression"] = xp["state"].duplicate(true)
    if ship.get("lifecycle") is Dictionary:
        var recovered: Dictionary = ShipLifecycle.after_confirmed_delivery(
            ship["lifecycle"], {"trusted_internal_apply": true,
                "delivery_succeeded": true, "ship_entity": sid})
        if not recovered.get("ok", false):
            return _reject("b2_original_n148_delivery_reset_rejected")
        staged["ships"][sid]["lifecycle"] = recovered["lifecycle"].duplicate(true)
    # Frozen delivery reputation: 5+payment/2000, clamped to 1..15.
    var reputation: Dictionary = ship.get("faction_reputation", {}).duplicate(true)
    var owner: String = str(c.get("faction_id", ""))
    if not owner.is_empty():
        reputation[owner] = mini(100, int(reputation.get(owner, 0)) +
            clampi(5 + int(payment / 2000), 1, 15))
        staged["ships"][sid]["faction_reputation"] = reputation
    return {"ok": true, "status": "N144_REAL_COLONY_METALS_DELIVERED",
        "world": staged, "ledger_snapshot": ledger.snapshot(),
        "site_id": site_id, "ship_id": sid, "contract_id": cid,
        "quantity": qty, "payout": payment,
        "n15_receipt": receipt_id,
        "n9_receipt": "contract:" + cid + ":payout",
        "construction_receipt": site_receipt_id, "tick": tick}
