extends SceneTree
## End-to-end autonomy acceptance: NO manual ship commands, no fabricated
## transit, docking, cargo or ledger mutations. Uses the original N4 world,
## with ONLY a controlled N135 shortage/price fixture to force a real need.
## Run locally with Godot 4.7.2:
## godot --headless --path godot --script res://tests/p2_unattended_autonomous_flight_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")

const MAX_TICKS := 12000

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy source missing")
        return
    var runner = Runtime.new()
    if not runner.start_from_seed(seed):
        _fail("native boot: " + runner.boot_error())
        return
    var initial: Dictionary = runner.checkpoint()
    var world: Dictionary = initial["native_production"]["world"]
    if world.get("ships", {}).size() != 24:
        _fail("original 24 ships not loaded")
        return
    # Same source-backed market pairing used by N153 acceptance; no
    # synthetic ships, contracts, cargo, money or destination teleport.
    world["markets"]["alpha-station"]["prices"]["food"] = 60.0
    world["markets"]["earth-station"]["prices"]["food"] = 4.0
    var stock: float = float(world["markets"]["alpha-station"]["supply"].get("food", 0.0))
    world["markets"]["alpha-station"]["consumption_window"]["food"] = [
        {"tick": 0, "qty": stock + 5.0}]
    if not runner.restore_checkpoint(initial, seed):
        _fail("controlled economic fixture cannot restore")
        return
    var need: Dictionary = Demand.propose(runner.economy_snapshot(), 0)
    if not need.get("ok", false):
        _fail("N135 did not evaluate real station needs")
        return
    var order: Dictionary = {}
    for candidate in need.get("proposals", []):
        if str(candidate.get("location", "")) == "alpha-station" and str(candidate.get("source_location", "")) == "earth-station" and str(candidate.get("commodity", "")) == "food":
            order = candidate
            break
    if order.is_empty():
        _fail("no native directed economic demand for fixture")
        return
    # N135/N104 funded posting is the ONLY permitted explicit fixture
    # admission. All subsequent N153/N84/N146/N14/N21/N97/N15/N104
    # operations must happen autonomously in the canonical tick runner.
    var posted: Dictionary = runner.production.post_funded_contract(0, order)
    if not posted.get("ok", false):
        _fail("canonical N104 funded posting refused: " + str(posted))
        return
    var cid: String = str(posted["contract_id"])
    var initial_money: int = _money(runner.checkpoint()["native_production"]["ledger"]["balances"])
    var saved: bool = false
    var saw_accept: bool = false
    var saw_pickup: bool = false
    var saw_transit: bool = false
    var saw_destination_dock: bool = false
    var path: String = "user://tests/p2-autonomous-flight-" + str(Time.get_ticks_usec()) + ".json"
    for n in range(MAX_TICKS):
        if not runner.queue_control("step", 1):
            _fail("clock refused step " + str(n))
            return
        runner.advance_frame(0.0)
        if not runner.last_phase_failure().is_empty():
            _fail("authoritative phase failed at " + str(n) + ": " + str(runner.last_phase_failure()))
            return
        var checkpoint: Dictionary = runner.checkpoint()
        var w: Dictionary = checkpoint["native_production"]["world"]
        var bank: Dictionary = checkpoint["native_production"]["ledger"]
        if _money(bank["balances"]) != initial_money:
            _fail("N9 credits not conserved at tick " + str(n))
            return
        var board: Dictionary = w["contract_board"]["contracts"]
        if not board.has(cid):
            _fail("N104 order vanished")
            return
        var contract: Dictionary = board[cid]
        var status: String = str(contract.get("status", ""))
        if status in ["accepted", "picked_up", "paid"]:
            saw_accept = true
        if status in ["picked_up", "paid"]:
            saw_pickup = true
        var ship_id: String = str(contract.get("fulfiller_id", ""))
        if not ship_id.is_empty() and w["ships"].has(ship_id):
            var ship: Dictionary = w["ships"][ship_id]
            if not (ship.get("transit", {}) as Dictionary).is_empty():
                saw_transit = true
            if str(ship.get("location", "")) == "alpha-station" and not str(ship.get("docked_at", "")).is_empty():
                saw_destination_dock = true
        # Save only AFTER physical pickup; reload while the obligation is
        # still open. A restored N84 cursor must not repurchase or repay.
        if saw_pickup and saw_transit and not saved and status != "paid" and not ship_id.is_empty() and not (w["ships"][ship_id].get("transit", {}) as Dictionary).is_empty():
            if SaveState.save_runner(runner, path) != OK:
                _fail("N38 mid-contract disk save failed")
                return
            var restored = Runtime.new()
            if not restored.start_from_seed(seed):
                _fail("fresh runner cannot boot")
                return
            var loaded: Dictionary = SaveState.load_runner(restored, seed, path)
            if not loaded.get("ok", false) or restored.checkpoint() != checkpoint:
                _fail("N38 mid-contract snapshot changed on disk reload")
                return
            runner = restored
            saved = true
        if status == "paid":
            if not saw_accept or not saw_pickup or not saw_transit or not saw_destination_dock or not saved:
                _fail("N104 paid without independently observed flight/dock/save")
                return
            if not bank["receipts"].has("contract:" + cid + ":source_buy") or not bank["receipts"].has("contract:" + cid + ":payout"):
                _fail("N9 purchase/payout receipts missing")
                return
            if not w["cargo_receipts"].has("contract:" + cid + ":load") or not w["cargo_receipts"].has("contract:" + cid + ":unload"):
                _fail("N15 load/unload proof missing")
                return
            var escrow: String = str(contract.get("escrow_account", ""))
            if int(bank["balances"].get(escrow, -1)) != 0:
                _fail("N104 escrow not fully settled")
                return
            var before_replay: Dictionary = runner.checkpoint()
            if runner.production.apply_autonomous_contract_cargo(runner.tick_count, ship_id, cid, "delivery").get("ok", false) or runner.checkpoint() != before_replay:
                _fail("N104 paid delivery replay changed canonical World")
                return
            _cleanup(path)
            print("P2_UNATTENDED_N135_N104_N153_N14_N21_N15_N97_SAVE_PASS ticks=" + str(n + 1))
            quit(0)
            return
    _cleanup(path)
    _fail("no end-to-end paid flight after " + str(MAX_TICKS) + " native ticks; accepted=" + str(saw_accept) + " pickup=" + str(saw_pickup) + " transit=" + str(saw_transit) + " dock=" + str(saw_destination_dock) + " saved=" + str(saved))

func _money(balances: Dictionary) -> int:
    var total: int = 0
    for value in balances.values():
        total += int(value)
    return total

func _cleanup(path: String) -> void:
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")

func _fail(reason: String) -> void:
    push_error("P2_UNATTENDED_AUTONOMY_FAIL: " + reason)
    quit(1)
