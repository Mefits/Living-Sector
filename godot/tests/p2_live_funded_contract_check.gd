extends SceneTree
## N135 → N104 → N9 in ONE authoritative P2 tick; Godot 4.7.2 headless.
## Uses actual frozen Galaxy facilities/markets but adds a CONTROLLED
## fixture N151 consumption window to guarantee a testable station shortage.
## godot --headless --path godot --script res://tests/p2_live_funded_contract_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("missing frozen Rust seed")
        return
    var original = Runtime.new()
    if not original.start_from_seed(seed):
        _fail("N158 boot: " + original.boot_error())
        return
    var checkpoint: Dictionary = original.checkpoint()
    var world: Dictionary = checkpoint["native_production"]["world"]
    var first: String = ""
    var second: String = ""
    var commodity: String = "food"
    var locs: Array = world["markets"].keys()
    locs.sort()
    # Choose only real, funded stations with the SAME real commodity.
    for destination in locs:
        var buyer: Dictionary = world["markets"][destination]
        var buyer_fac: Dictionary = world["facilities"][str(buyer["owner"])]
        if int(buyer_fac["credits"]) < 200 or not buyer["prices"].has(commodity):
            continue
        for source in locs:
            if source == destination:
                continue
            var seller: Dictionary = world["markets"][source]
            if float(seller["supply"].get(commodity, 0.0)) >= 2.0:
                first = str(destination)
                second = str(source)
                break
        if not first.is_empty():
            break
    if first.is_empty() or second.is_empty():
        _fail("no real funded pair of native markets")
        return
    # Not an invented market/ship: insert only a fixture demand receipt
    # into a cloned real N39 checkpoint, with all original stock and wallets.
    var current_stock: float = float(world["markets"][first]["supply"].get(commodity, 0.0))
    world["markets"][first]["consumption_window"][commodity] = [
        {"tick": 0, "qty": current_stock + 2.0}]
    var old_balances: Dictionary = checkpoint["native_production"]["ledger"]["balances"].duplicate(true)
    var old_total: int = _total(old_balances)
    var buyer_id: String = str(world["markets"][first]["owner"])
    var wallet: String = "facility/" + buyer_id
    var runner = Runtime.new()
    if not runner.start_from_seed(seed) or not runner.restore_checkpoint(checkpoint, seed):
        _fail("controlled native consumption fixture did not restore")
        return
    if not runner.queue_control("step", 1):
        _fail("cannot queue sole native simulation tick")
        return
    runner.advance_frame(0.0)
    if runner.tick_count != 1 or not runner.last_phase_failure().is_empty():
        _fail("native live market tick failed: " + str(runner.last_phase_failure()))
        return
    var posted: Dictionary = runner.contract_admissions_snapshot()
    if not posted.get("ok", false) or posted.get("posted", []).is_empty():
        _fail("station did not create an AUTONOMOUS funded contract: " + str(posted))
        return
    var receipt: Dictionary = posted["posted"][0]
    if str(receipt.get("status", "")) != "POSTED_FUNDED":
        _fail("proposal was falsely presented as a paid contract")
        return
    var contract_id: String = str(receipt["contract_id"])
    var escrow: String = str(receipt["escrow_account"])
    var after: Dictionary = runner.checkpoint()
    var next_world: Dictionary = after["native_production"]["world"]
    var next_balances: Dictionary = after["native_production"]["ledger"]["balances"]
    var board: Dictionary = next_world["contract_board"]
    if not board["contracts"].has(contract_id) or board["contracts"][contract_id]["status"] != "posted":
        _fail("N104 contract not durable in ONE World")
        return
    var reserved: int = int(board["contracts"][contract_id]["reserved"])
    if reserved <= 0 or int(next_balances[escrow]) != reserved:
        _fail("not a prepaid N104 delivery contract")
        return
    if int(next_world["escrow_balances"][escrow]) != reserved:
        _fail("escrow mirror and N9 ledger diverged")
        return
    if _total(next_balances) != old_total:
        _fail("N9 money created/destroyed by posting")
        return
    if int(next_balances[wallet]) != int(next_world["facilities"][buyer_id]["credits"]):
        _fail("buyer facility credits not mirrored from N9")
        return
    # N151 may buy real food and other facilities can earn/pay in the same
    # tick. Assert the EXACT N9 contract receipt, not a false assumption
    # that the buyer's entire wallet was otherwise unchanged.
    var receipt_key: String = "contract:" + contract_id + ":post"
    var money_receipts: Dictionary = after["native_production"]["ledger"]["receipts"]
    if not money_receipts.has(receipt_key):
        _fail("N104 real funding receipt not committed")
        return
    var credit_legs: Array = money_receipts[receipt_key]["legs"]
    if credit_legs.size() != 2 or credit_legs[0] != {"account": wallet, "delta": -reserved} or credit_legs[1] != {"account": escrow, "delta": reserved}:
        _fail("N9 contract receipt not a balanced buyer-to-escrow transfer")
        return
    var before_replay: Dictionary = runner.checkpoint()
    var proposal: Dictionary = runner.station_demand_snapshot()
    if proposal.get("proposals", []).is_empty():
        _fail("N135 source proposal missing for replay test")
        return
    var duplicate: Dictionary = runner.production.post_funded_contract(1, proposal["proposals"][0])
    if duplicate.get("ok", false) or runner.checkpoint() != before_replay:
        _fail("duplicate need posted or modified N9/World")
        return
    # Actual JSON disk checkpoint/restore, not an in-memory fake.
    var save_path: String = "user://tests/p2-autonomy-contract-" + str(Time.get_ticks_usec()) + ".json"
    if SaveState.save_runner(runner, save_path) != OK:
        _fail("N38 atomic save rejected funded contract")
        return
    var recovered = Runtime.new()
    if not recovered.start_from_seed(seed):
        _fail("new runner boot failed")
        return
    var load: Dictionary = SaveState.load_runner(recovered, seed, save_path)
    if not load.get("ok", false):
        _fail("funded escrow N104 restore failed: " + str(load))
        return
    if recovered.funded_contracts_snapshot() != board:
        _fail("N104 board changed across disk restart")
        return
    var recovered_world: Dictionary = recovered.checkpoint()["native_production"]["world"]
    var recovered_money: Dictionary = recovered.checkpoint()["native_production"]["ledger"]["balances"]
    if recovered_money != next_balances or recovered_world["escrow_balances"] != next_world["escrow_balances"]:
        _fail("N9 escrow/physical facility account changed across restart")
        return
    recovered.queue_control("step", 1)
    recovered.advance_frame(0.0)
    if recovered.tick_count != 2 or not recovered.last_phase_failure().is_empty():
        _fail("canonical simulation did not continue after N104 restart")
        return
    var continued: Dictionary = recovered.funded_contracts_snapshot()["contracts"]
    if not continued.has(contract_id) or continued[contract_id]["reserved"] != reserved:
        _fail("saved funded order disappeared or was recharged")
        return
    var after_restart: Dictionary = recovered.checkpoint()["native_production"]["ledger"]
    if not after_restart["receipts"].has(receipt_key):
        _fail("contract payment receipt lost after next tick")
        return
    if int(after_restart["balances"][escrow]) != reserved:
        _fail("saved escrow was debited or double-funded")
        return
    var end_state: Dictionary = recovered.checkpoint()
    if _total(end_state["native_production"]["ledger"]["balances"]) != old_total:
        _fail("N9 money lost after resume")
        return
    var absolute: String = ProjectSettings.globalize_path(save_path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_LIVE_N135_N104_N9_FUNDED_CONTRACT_PASS")
    quit(0)

func _total(balances: Dictionary) -> int:
    var sum: int = 0
    for value in balances.values():
        sum += int(value)
    return sum

func _fail(reason: String) -> void:
    push_error("P2_LIVE_FUNDED_CONTRACT_FAIL: " + reason)
    quit(1)
