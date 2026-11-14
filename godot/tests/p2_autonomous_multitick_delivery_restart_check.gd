extends SceneTree
## Autonomous end-to-end regression: only a real native-market demand fixture.
## No ship commands, forced docking, teleportation, or fabricated inventory.
## Run locally: godot --headless --path godot --script res://tests/p2_autonomous_multitick_delivery_restart_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Save = preload("res://scripts/sim/save_state.gd")
const MAX_TICKS: int = 6000

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy seed unavailable")
        return
    var boot = Runtime.new()
    if not boot.start_from_seed(seed):
        _fail("native boot rejected: " + boot.boot_error())
        return
    var initial: Dictionary = boot.checkpoint()
    var world: Dictionary = initial["native_production"]["world"]
    var markets: Array = world["markets"].keys()
    markets.sort()
    var buyer_loc: String = ""
    var seller_loc: String = ""
    var good: String = "food"
    for destination in markets:
        var buyer: Dictionary = world["markets"][destination]
        var buyer_fac: Dictionary = world["facilities"][str(buyer["owner"])]
        if int(buyer_fac.get("credits", 0)) < 200 or not buyer.get("prices", {}).has(good):
            continue
        for source in markets:
            if source == destination:
                continue
            if float(world["markets"][source].get("supply", {}).get(good, 0.0)) >= 2.0:
                buyer_loc = str(destination)
                seller_loc = str(source)
                break
        if not buyer_loc.is_empty():
            break
    if buyer_loc.is_empty():
        _fail("no real funded buyer and source market for N135 fixture")
        return
    # A genuine original station and commodity; only a controlled N151
    # consumption history creates urgency. No free goods or fake ships.
    var stock: float = float(world["markets"][buyer_loc]["supply"].get(good, 0.0))
    world["markets"][buyer_loc]["consumption_window"][good] = [
        {"tick": 0, "qty": stock + 2.0}]
    # Explicitly restore the controlled demand into the authoritative checkpoint.
    initial["native_production"]["world"] = world
    var sim = Runtime.new()
    if not sim.start_from_seed(seed) or not sim.restore_checkpoint(initial, seed):
        _fail("native demand checkpoint rejected")
        return
    var initial_total: int = _total(initial["native_production"]["ledger"]["balances"])
    var initial_contracts: Dictionary = world["contract_board"]["contracts"].duplicate(true)
    var posted_by_native_n135: Dictionary = {}
    var accepted_by_native_n153: Dictionary = {}
    var target_contract: String = ""
    var assigned_ship: String = ""
    var escrow_account: String = ""
    var saw_departure: bool = false
    var saw_in_flight: bool = false
    var saw_pickup: bool = false
    var saw_midflight_save: bool = false
    var saw_loaded_restart: bool = false
    var save_path: String = "user://tests/p2-autonomous-flight-" + str(Time.get_ticks_usec()) + ".json"
    for i in range(MAX_TICKS):
        if not sim.queue_control("step", 1):
            _fail("single TickRunner refused step")
            return
        sim.advance_frame(0.0)
        if not sim.last_phase_failure().is_empty():
            _fail("canonical phase failed at tick " + str(sim.tick_count) + ": " + str(sim.last_phase_failure()))
            return
        var snap: Dictionary = sim.checkpoint()
        var w: Dictionary = snap["native_production"]["world"]
        var ledger: Dictionary = snap["native_production"]["ledger"]
        if _total(ledger["balances"]) != initial_total:
            _fail("N9 credit conservation failed at tick " + str(sim.tick_count))
            return
        var contracts: Dictionary = w["contract_board"]["contracts"]
        # Prove provenance from live N158 market/faction phases.
        # An injected or pre-existing N104 contract cannot pass this gate.
        var posting: Dictionary = sim.contract_admissions_snapshot()
        for row in posting.get("posted", []):
            if not (row is Dictionary):
                _fail("N135 admission contains an invalid receipt")
                return
            var posted_id: String = str(row.get("contract_id", ""))
            if posted_id.is_empty() or initial_contracts.has(posted_id) or not contracts.has(posted_id):
                _fail("N135 claimed a missing or pre-existing funded contract")
                return
            if str(row.get("status", "")) != "POSTED_FUNDED":
                _fail("N135 admission was not funded through canonical N104")
                return
            if not ledger["receipts"].has(str(row.get("receipt_id", ""))):
                _fail("N135 funded order has no durable N9 escrow receipt")
                return
            posted_by_native_n135[posted_id] = true
        var assignments: Dictionary = sim.last_n153_result()
        for row in assignments.get("accepted", []):
            if not (row is Dictionary):
                _fail("N153 acceptance contains an invalid assignment")
                return
            var accepted_id: String = str(row.get("contract_id", ""))
            var accepted_ship: String = str(row.get("ship_id", ""))
            if not posted_by_native_n135.has(accepted_id) or accepted_ship.is_empty():
                _fail("N153 accepted a contract without observed native N135 funding")
                return
            accepted_by_native_n153[accepted_id] = accepted_ship
        if target_contract.is_empty():
            var keys: Array = contracts.keys()
            keys.sort()
            for cid in keys:
                var c: Dictionary = contracts[cid]
                if posted_by_native_n135.has(str(cid)) and str(c.get("destination_location", "")) == buyer_loc and str(c.get("commodity", "")) == good and world["markets"].has(str(c.get("source_location", ""))):
                    target_contract = str(cid)
                    escrow_account = str(c.get("escrow_account", ""))
                    break
        if target_contract.is_empty():
            continue
        if not contracts.has(target_contract):
            _fail("funded contract vanished from canonical board")
            return
        var contract: Dictionary = contracts[target_contract]
        if assigned_ship.is_empty() and accepted_by_native_n153.has(target_contract):
            assigned_ship = str(accepted_by_native_n153[target_contract])
        if not assigned_ship.is_empty() and str(contract.get("fulfiller_id", "")) != assigned_ship:
            _fail("N104 fulfiller diverged from observed independent N153 assignment")
            return
        if str(contract.get("status", "")) in ["picked_up", "paid"]:
            saw_pickup = true
        if not assigned_ship.is_empty() and w["ships"].has(assigned_ship):
            var ship: Dictionary = w["ships"][assigned_ship]
            var transit: Dictionary = ship.get("transit", {})
            if not transit.is_empty():
                saw_departure = true
                saw_in_flight = true
                if not saw_midflight_save:
                    if Save.save_runner(sim, save_path) != OK:
                        _fail("N38 could not persist real N14 transit")
                        return
                    var resumed = Runtime.new()
                    if not resumed.start_from_seed(seed):
                        _fail("reboot rejected original Galaxy")
                        return
                    var result: Dictionary = Save.load_runner(resumed, seed, save_path)
                    if not result.get("ok", false):
                        _fail("N38 reload failed in flight: " + str(result))
                        return
                    if resumed.checkpoint()["native_production"]["world"]["ships"][assigned_ship]["transit"] != transit:
                        _fail("real N14 transit changed across disk restart")
                        return
                    var recovered: Dictionary = resumed.checkpoint()["native_production"]
                    if recovered["world"]["contract_board"] != w["contract_board"]:
                        _fail("N104 contract lifecycle or escrow changed across N38 disk restart")
                        return
                    if recovered["world"]["cargo_receipts"] != w["cargo_receipts"]:
                        _fail("N15 physical cargo receipts changed across N38 disk restart")
                        return
                    if recovered["world"]["ships"][assigned_ship]["cargo"] != ship["cargo"]:
                        _fail("N15 physical hold changed across N38 disk restart")
                        return
                    if recovered["ledger"]["receipts"] != ledger["receipts"]:
                        _fail("N9 payment receipts changed across N38 disk restart")
                        return
                    if recovered["ledger"]["balances"] != ledger["balances"]:
                        _fail("N9 wallets changed across disk restart")
                        return
                    sim = resumed
                    saw_midflight_save = true
        if str(contract.get("status", "")) == "picked_up" and not assigned_ship.is_empty() and w["ships"].has(assigned_ship):
            var commodity: String = str(contract.get("commodity", ""))
            var quantity: int = int(contract.get("quantity", 0))
            var load_id: String = "contract:" + target_contract + ":load"
            var load_receipt: Dictionary = w.get("cargo_receipts", {}).get(load_id, {})
            if quantity < 1 or str(load_receipt.get("action", "")) != "load" or str(load_receipt.get("ship_id", "")) != assigned_ship:
                _fail("N104 pickup status without real N15 loading receipt")
                return
            if int(load_receipt.get("quantities", {}).get(commodity, -1)) != quantity:
                _fail("N15 pickup quantity differs from N104 obligation")
                return
            if float(w["ships"][assigned_ship].get("cargo", {}).get(commodity, 0.0)) < float(quantity):
                _fail("N104 pickup status without physical ship cargo")
                return
        # Restart again after the paid source purchase: cargo and seller
        # payment exist, but N104 escrow must not settle before delivery.
        if str(contract.get("status", "")) == "picked_up" and saw_midflight_save and not saw_loaded_restart:
            if Save.save_runner(sim, save_path) != OK:
                _fail("N38 could not persist paid N97 pickup")
                return
            var loaded_runtime = Runtime.new()
            if not loaded_runtime.start_from_seed(seed):
                _fail("N38 pickup restart rejected native seed")
                return
            var loaded_result: Dictionary = Save.load_runner(loaded_runtime, seed, save_path)
            if not loaded_result.get("ok", false):
                _fail("N38 pickup reload failed: " + str(loaded_result))
                return
            var before_pickup_restart: Dictionary = sim.checkpoint()["native_production"]
            var after_pickup_restart: Dictionary = loaded_runtime.checkpoint()["native_production"]
            if after_pickup_restart["world"]["contract_board"] != before_pickup_restart["world"]["contract_board"]:
                _fail("N104 picked-up contract changed across disk restart")
                return
            if after_pickup_restart["world"]["cargo_receipts"] != before_pickup_restart["world"]["cargo_receipts"]:
                _fail("N15 loading proof changed across disk restart")
                return
            if after_pickup_restart["world"]["ships"][assigned_ship]["cargo"] != before_pickup_restart["world"]["ships"][assigned_ship]["cargo"]:
                _fail("N15 loaded hold changed across disk restart")
                return
            if after_pickup_restart["ledger"] != before_pickup_restart["ledger"]:
                _fail("N9 paid pickup or escrow changed across disk restart")
                return
            sim = loaded_runtime
            saw_loaded_restart = true
        if str(contract.get("status", "")) == "paid":
            if not posted_by_native_n135.has(target_contract) or not accepted_by_native_n153.has(target_contract):
                _fail("paid contract lacks observed N135 funding or N153 assignment")
                return
            if not saw_departure or not saw_in_flight or not saw_midflight_save or not saw_loaded_restart or not saw_pickup:
                _fail("contract paid without observed physical N14 transit/pickup/restart")
                return
            var commodity: String = str(contract.get("commodity", ""))
            var quantity: int = int(contract.get("quantity", 0))
            var source_id: String = str(contract.get("source_location", ""))
            var destination_id: String = str(contract.get("destination_location", ""))
            var load_id: String = "contract:" + target_contract + ":load"
            var unload_id: String = "contract:" + target_contract + ":unload"
            var cargo_receipts: Dictionary = w.get("cargo_receipts", {})
            var loading: Dictionary = cargo_receipts.get(load_id, {})
            var unloading: Dictionary = cargo_receipts.get(unload_id, {})
            if quantity < 1 or str(loading.get("action", "")) != "load" or str(unloading.get("action", "")) != "unload":
                _fail("N104 paid without BOTH durable physical N15 cargo receipts")
                return
            if str(loading.get("location_id", "")) != source_id or str(unloading.get("location_id", "")) != destination_id:
                _fail("N15 receipts do not match original source and destination")
                return
            if str(loading.get("ship_id", "")) != assigned_ship or str(unloading.get("ship_id", "")) != assigned_ship:
                _fail("N15 pickup/delivery performed by a different ship")
                return
            if int(loading.get("quantities", {}).get(commodity, -1)) != quantity or int(unloading.get("quantities", {}).get(commodity, -1)) != quantity:
                _fail("N15 cargo quantities do not match funded N104 obligation")
                return
            if float(w["ships"][assigned_ship].get("cargo", {}).get(commodity, 0.0)) >= float(quantity):
                _fail("N104 paid but delivered cargo remains in ship hold")
                return
            var receipt_id: String = "contract:" + target_contract + ":payout"
            if not ledger["receipts"].has(receipt_id):
                _fail("N104 paid without unique N9 payout receipt")
                return
            if not escrow_account.is_empty() and int(ledger["balances"].get(escrow_account, -1)) != int(contract.get("reserved", -2)):
                _fail("N104 escrow and canonical reserved remainder diverged")
                return
            var final_state: Dictionary = sim.checkpoint()
            var final_receipts: Dictionary = final_state["native_production"]["world"]["cargo_receipts"].duplicate(true)
            var final_payout: Dictionary = ledger["receipts"][receipt_id].duplicate(true)
            if not sim.queue_control("step", 1):
                _fail("cannot check payout idempotence")
                return
            sim.advance_frame(0.0)
            var after: Dictionary = sim.checkpoint()
            if not sim.last_phase_failure().is_empty() or not after["native_production"]["ledger"]["receipts"].has(receipt_id):
                _fail("settlement not durable after next native tick")
                return
            if after["native_production"]["world"]["cargo_receipts"] != final_receipts:
                _fail("physical cargo receipt changed or repeated after settlement")
                return
            if after["native_production"]["ledger"]["receipts"][receipt_id] != final_payout:
                _fail("N104 payout receipt mutated after settlement")
                return
            if _total(after["native_production"]["ledger"]["balances"]) != initial_total:
                _fail("settlement minted or lost credits")
                return
            if int(after["native_production"]["world"]["contract_board"]["contracts"][target_contract].get("reserved", -1)) != int(contract.get("reserved", -2)):
                _fail("N104 escrow remainder changed after settlement")
                return
            _cleanup(save_path)
            print("P2_AUTONOMOUS_N135_N104_N153_N14_N21_N15_N97_RESTART_PASS: " + target_contract + " at tick " + str(sim.tick_count))
            quit(0)
            return
    _cleanup(save_path)
    _fail("no full hands-off paid delivery within " + str(MAX_TICKS) +
        " ticks; contract=" + target_contract + " ship=" + assigned_ship +
        " departed=" + str(saw_departure) + " pickup=" + str(saw_pickup) +
        " saved_in_flight=" + str(saw_midflight_save) +
        " saved_after_pickup=" + str(saw_loaded_restart))

func _total(balances: Dictionary) -> int:
    var total: int = 0
    for value in balances.values():
        total += int(value)
    return total

func _cleanup(path: String) -> void:
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")

func _fail(message: String) -> void:
    push_error("P2_AUTONOMOUS_FULL_FLIGHT_FAIL: " + message)
    quit(1)
