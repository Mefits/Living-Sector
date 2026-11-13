extends SceneTree
## One-World N21/N15 + paid N97/N9 + N104 receipt settlement.
## This intentionally isolates economic correctness from the separate N14
## multi-tick route test: destination co-location is TEST-ONLY staging.
## godot --headless --path godot --script res://tests/p2_native_paid_autonomous_delivery_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Fleet = preload("res://scripts/sim/phase2/unified_fleet_logistics.gd")
const Paid = preload("res://scripts/sim/phase2/unified_autonomous_paid_cargo.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("no frozen native Galaxy world")
        return
    var runtime = Runtime.new()
    if not runtime.start_from_seed(seed):
        _fail("N39 source boot: " + runtime.boot_error())
        return
    var checkpoint: Dictionary = runtime.checkpoint()
    var w: Dictionary = checkpoint["native_production"]["world"]
    var original_money: Dictionary = checkpoint["native_production"]["ledger"]
    var source: String = ""
    var dest: String = ""
    var ship_id: String = ""
    var good: String = ""
    var cost: int = 0
    var market_ids: Array = w["markets"].keys()
    market_ids.sort()
    var ship_ids: Array = w["ships"].keys()
    ship_ids.sort()
    # Pick REAL N4 co-located ship, station and original commodity stock,
    # with enough original money on both ship and buyer station.
    for loc in market_ids:
        var seller_id: String = str(w["markets"][loc]["owner"])
        if int(w["facilities"][seller_id].get("docking_capacity", 0)) < 1:
            continue
        for sid in ship_ids:
            var sh: Dictionary = w["ships"][sid]
            if str(sh["location"]) != str(loc) or not (sh["cargo"] as Dictionary).is_empty() or int(sh["cargo_capacity"]) < 1:
                continue
            var goods: Array = w["markets"][loc]["supply"].keys()
            goods.sort()
            for commodity in goods:
                if not Catalog.contains(str(commodity)) or float(w["markets"][loc]["supply"][commodity]) < 1.0:
                    continue
                var unit_price: float = float(w["markets"][loc]["prices"].get(commodity, 0.0))
                if unit_price <= 0.0 or not is_finite(unit_price):
                    continue
                var estimate: int = int(ceil(unit_price))
                if estimate < 1 or int(sh["credits"]) < estimate:
                    continue
                for buyer_loc in market_ids:
                    if buyer_loc == loc:
                        continue
                    var buyer_id: String = str(w["markets"][buyer_loc]["owner"])
                    if int(w["facilities"][buyer_id].get("docking_capacity", 0)) > 0 and int(w["facilities"][buyer_id]["credits"]) > estimate + 25:
                        source = str(loc)
                        dest = str(buyer_loc)
                        ship_id = str(sid)
                        good = str(commodity)
                        cost = estimate
                        break
                if not source.is_empty():
                    break
            if not source.is_empty():
                break
        if not source.is_empty():
            break
    if source.is_empty():
        _fail("no genuine funded market/hauler/destination combination")
        return
    var source_station: String = str(w["markets"][source]["owner"])
    var buyer_station: String = str(w["markets"][dest]["owner"])
    var bank := Ledger.new()
    if not bank.restore(original_money):
        _fail("original N9 ledger not loadable")
        return
    var initial_total: int = bank.total()
    var cid: String = "n97-native-verified-delivery-test"
    var escrow: String = "escrow:" + cid
    if not bank.register_empty_account(escrow):
        _fail("N9 escrow fixture cannot open")
        return
    var board := Board.new(bank)
    if not board.restore(w["contract_board"]):
        _fail("N104 source board unreadable")
        return
    var pay: int = cost + 25
    var buyer_wallet: String = Schema.facility_account(buyer_station)
    var placed: Dictionary = board.post(cid, "delivery", buyer_wallet, escrow,
        good, 1, source, dest, pay, 0, 100, "facility")
    if not placed.get("ok", false):
        _fail("real N104 paid post refused: " + str(placed))
        return
    var accepted: Dictionary = board.accept(cid, ship_id,
        str(w["ships"][ship_id]["faction_id"]), 0.0, 1.0, 0)
    if not accepted.get("ok", false):
        _fail("N104 paid accepted test not possible")
        return
    w["contract_board"] = board.snapshot()
    w["escrow_balances"][escrow] = bank.balance(escrow)
    w["facilities"][buyer_station]["credits"] = bank.balance(buyer_wallet)
    w["ships"][ship_id]["active_contract_id"] = cid
    w["ships"][ship_id]["current_goal"] = "fulfill_delivery"
    w["ships"][ship_id]["max_source_cost"] = cost
    w["ships"][ship_id]["current_bt"] = Bt.sequence([
        Bt.action({"kind": "Dock"}),
        Bt.action({"kind": "Buy", "commodity": good, "qty": 1})])
    checkpoint["native_production"]["ledger"] = bank.snapshot()
    if not Schema.validate(w).is_empty():
        _fail("controlled N104 source fixture violates canonical schema")
        return
    if not runtime.restore_checkpoint(checkpoint, seed):
        _fail("N38 cannot restore genuine N104 source fixture")
        return
    var first_stock: float = float(w["markets"][source]["supply"][good])
    var first_ship_cash: int = int(w["ships"][ship_id]["credits"])
    var first_seller_cash: int = int(w["facilities"][source_station]["credits"])
    var source_dock: Dictionary = Fleet.command(runtime.economy_snapshot(),
        "dock", ship_id, "test:n21:source", 1)
    if not source_dock.get("ok", false) or not runtime.production.apply_fleet_logistics(1, source_dock, true):
        _fail("real N21 source docking failed: " + str(source_dock))
        return
    # A changed live source quote above N153's accepted ceiling must
    # reject before any N9 credits, N15 inventory or N104 state changes.
    var overpriced: Dictionary = runtime.economy_snapshot()
    overpriced["markets"][source]["prices"][good] = float(cost) + 500.0
    var denied: Dictionary = Paid.propose(overpriced,
        runtime.production.ledger_snapshot(), ship_id, cid, "pickup", 1)
    if denied.get("ok", false) or runtime.economy_snapshot()["markets"][source]["supply"][good] != first_stock:
        _fail("N97 accepted an unauthorised repriced market purchase")
        return
    var bought: Dictionary = runtime.production.apply_autonomous_contract_cargo(1,
        ship_id, cid, "pickup")
    if not bought.get("ok", false):
        _fail("N97 real source purchase or N104 pickup refused: " + str(bought))
        return
    var loaded: Dictionary = runtime.economy_snapshot()
    var source_bank: Dictionary = runtime.production.ledger_snapshot()
    if str(loaded["contract_board"]["contracts"][cid]["status"]) != "picked_up":
        _fail("N104 pickup not advanced by validated N15 receipt")
        return
    if float(loaded["markets"][source]["supply"][good]) != first_stock - 1.0 or int(loaded["ships"][ship_id]["cargo"].get(good, 0)) != 1:
        _fail("real N15 stock/cargo not conserved")
        return
    if int(loaded["ships"][ship_id]["credits"]) != first_ship_cash - cost or int(loaded["facilities"][source_station]["credits"]) != first_seller_cash + cost:
        _fail("N97 source purchase not paid with real N9 credits")
        return
    if not source_bank["receipts"].has("contract:" + cid + ":source_buy") or not loaded["cargo_receipts"].has("contract:" + cid + ":load"):
        _fail("missing N9 or N15 real purchase proof")
        return
    if _total(source_bank["balances"]) != initial_total:
        _fail("N97 created or lost credits")
        return
    var before_replay: Dictionary = runtime.checkpoint()
    if runtime.production.apply_autonomous_contract_cargo(1, ship_id, cid, "pickup").get("ok", false) or runtime.checkpoint() != before_replay:
        _fail("duplicate purchase replayed N15 or N9")
        return

    # Independent N104 delivery-settlement acceptance test. A detached
    # fixture relocates the SAME real ship to the actual destination only
    # to test N15 unload and N104 payout. This is NOT a flight test.
    var destination_world: Dictionary = loaded.duplicate(true)
    destination_world["ships"][ship_id]["docked_at"] = ""
    destination_world["ships"][ship_id]["location"] = dest
    var end_dock: Dictionary = Fleet.command(destination_world, "dock",
        ship_id, "test:n21:destination", 2)
    if not end_dock.get("ok", false):
        _fail("N21 destination fixture docking refused: " + str(end_dock))
        return
    destination_world = end_dock["world"]
    var before_target_stock: float = float(destination_world["markets"][dest]["supply"].get(good, 0.0))
    var before_payout_cash: int = int(destination_world["ships"][ship_id]["credits"])
    var delivered: Dictionary = Paid.propose(destination_world, source_bank,
        ship_id, cid, "delivery", 2)
    if not delivered.get("ok", false):
        _fail("N15/N104 physically verified settlement failed: " + str(delivered))
        return
    var final_world: Dictionary = delivered["world"]
    var final_bank: Dictionary = delivered["ledger_snapshot"]
    if str(final_world["contract_board"]["contracts"][cid]["status"]) != "paid":
        _fail("N104 did not settle genuine N15 delivery")
        return
    if int(final_world["ships"][ship_id]["cargo"].get(good, 0)) != 0 or float(final_world["markets"][dest]["supply"].get(good, 0.0)) != before_target_stock + 1.0:
        _fail("physical N15 destination cargo invented or missing")
        return
    if int(final_world["ships"][ship_id]["credits"]) != before_payout_cash + pay or int(final_world["escrow_balances"][escrow]) != 0:
        _fail("N104 escrow payout not in the sole N9 ledger")
        return
    if str(final_world["ships"][ship_id]["active_contract_id"]) != "" or not final_bank["receipts"].has("contract:" + cid + ":payout"):
        _fail("paid ship still assigned or payout receipt missing")
        return
    if _total(final_bank["balances"]) != initial_total:
        _fail("N104 final payout changed total money")
        return
    if Paid.propose(final_world, final_bank, ship_id, cid, "delivery", 3).get("ok", false):
        _fail("paid delivery repeated settlement")
        return
    print("P2_N21_N15_N97_N104_SINGLE_LEDGER_CARGO_PASS")
    quit(0)

func _total(rows: Dictionary) -> int:
    var sum: int = 0
    for value in rows.values():
        sum += int(value)
    return sum

func _fail(reason: String) -> void:
    push_error("P2_NATIVE_PAID_DELIVERY_FAIL: " + reason)
    quit(1)
