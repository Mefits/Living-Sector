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
    var sim = Runtime.new()
    if not sim.start_from_seed(seed) or not sim.restore_checkpoint(initial, seed):
        _fail("native demand checkpoint rejected")
        return
    var initial_total: int = _total(initial["native_production"]["ledger"]["balances"])
    var target_contract: String = ""
    var assigned_ship: String = ""
    var escrow_account: String = ""
    var saw_departure: bool = false
    var saw_in_flight: bool = false
    var saw_pickup: bool = false
    var saw_midflight_save: bool = false
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
        if target_contract.is_empty():
            var keys: Array = contracts.keys()
            keys.sort()
            for cid in keys:
                var c: Dictionary = contracts[cid]
                if str(c.get("destination_location", "")) == buyer_loc and str(c.get("commodity", "")) == good and world["markets"].has(str(c.get("source_location", ""))):
                    target_contract = str(cid)
                    escrow_account = str(c.get("escrow_account", ""))
                    break
        if target_contract.is_empty():
            continue
        if not contracts.has(target_contract):
            _fail("funded contract vanished from canonical board")
            return
        var contract: Dictionary = contracts[target_contract]
        if assigned_ship.is_empty():
            assigned_ship = str(contract.get("fulfiller_id", ""))
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
                    if resumed.checkpoint()["native_production"]["ledger"]["balances"] != ledger["balances"]:
                        _fail("N9 wallets changed across disk restart")
                        return
                    sim = resumed
                    saw_midflight_save = true
        if str(contract.get("status", "")) == "paid":
            if not saw_departure or not saw_in_flight or not saw_midflight_save or not saw_pickup:
                _fail("contract paid without observed physical N14 transit/pickup/restart")
                return
            var receipt_id: String = "contract:" + target_contract + ":payout"
            if not ledger["receipts"].has(receipt_id):
                _fail("N104 paid without unique N9 payout receipt")
                return
            if not escrow_account.is_empty() and int(ledger["balances"].get(escrow_account, -1)) != int(contract.get("reserved", -2)):
                _fail("N104 escrow and canonical reserved remainder diverged")
                return
            var final_state: Dictionary = sim.checkpoint()
            if not sim.queue_control("step", 1):
                _fail("cannot check payout idempotence")
                return
            sim.advance_frame(0.0)
            var after: Dictionary = sim.checkpoint()
            if not sim.last_phase_failure().is_empty() or not after["native_production"]["ledger"]["receipts"].has(receipt_id):
                _fail("settlement not durable after next native tick")
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
        " saved_in_flight=" + str(saw_midflight_save))

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
