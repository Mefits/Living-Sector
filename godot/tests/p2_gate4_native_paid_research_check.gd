extends SceneTree
## Gate4: real 0.6.7 faction treasury -> N143 paid science -> N9 receipts
## -> saved N155 progress, without invented labs, labor or research accounts.
## One acceptance run, not a suite of micro-PR tests.
## godot --headless --path godot --script res://tests/p2_gate4_native_paid_research_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const N143 = preload("res://scripts/sim/phase2/unified_native_research_phase.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("missing original Galaxy seed")
        return
    var runner = Runtime.new()
    if not runner.start_from_seed(seed):
        _fail("P2 N39/N158 native boot: " + runner.boot_error())
        return
    var initial: Dictionary = runner.checkpoint()
    var base_world: Dictionary = initial["native_production"]["world"]
    var first_money: Dictionary = initial["native_production"]["ledger"]
    if base_world.get("faction_treasuries", {}).size() != 3:
        _fail("source faction treasury missing from canonical N9 World")
        return
    var faction_ids: Array = base_world["faction_treasuries"].keys()
    faction_ids.sort()
    for fid in faction_ids:
        if int(base_world["faction_treasuries"][fid]) != 240000:
            _fail("source treasury must equal original frozen faction JSON")
            return
        var account: String = "faction/" + str(fid)
        if int(first_money["balances"].get(account, -1)) != 240000:
            _fail("faction treasury not in same canonical N9 account")
            return
    var total: int = _sum(first_money["balances"])
    # This is ONE controlled preflight: insufficient real treasury MUST
    # block a paid shift; it cannot invent money or science on a copy.
    var unfunded: Dictionary = base_world.duplicate(true)
    for fid in faction_ids:
        unfunded["faction_treasuries"][fid] = 1000
    var source_factions: Dictionary = {}
    for f in seed["factions"]:
        source_factions[str(f["id"])] = f.duplicate(true)
    var blocked: Dictionary = N143.propose(unfunded, source_factions, 1, 32)
    if not blocked.get("ok", false) or not blocked.get("shifts", []).is_empty():
        _fail("N143 generated free science despite insufficient real treasury")
        return
    runner.queue_control("step", 1)
    runner.advance_frame(0.0)
    if runner.tick_count != 1 or not runner.last_phase_failure().is_empty():
        _fail("integrated first faction research tick failed: " +
            str(runner.last_phase_failure()))
        return
    var after: Dictionary = runner.checkpoint()
    var world: Dictionary = after["native_production"]["world"]
    var money: Dictionary = after["native_production"]["ledger"]
    var shifts: Array = runner.last_native_research_result().get("paid", [])
    if shifts.size() != 3 or world.get("research_receipts", {}).size() != 3:
        _fail("expected three real paid original-station research shifts: " +
            str(runner.last_native_research_result()))
        return
    if _sum(money["balances"]) != total:
        _fail("N143 created or destroyed N9 credits")
        return
    for fid in faction_ids:
        var receipt_id: String = "native_research:" + str(fid) + ":1"
        if not money["receipts"].has(receipt_id) or not world["research_receipts"].has(receipt_id):
            _fail("N143 missing physical paid N9/research receipt: " + receipt_id)
            return
        var row: Dictionary = world["research_receipts"][receipt_id]
        var ledger_receipt: Dictionary = money["receipts"][receipt_id]
        if str(ledger_receipt.get("kind", "")) != "n143_native_research_shift":
            _fail("research money was not booked as original paid shift")
            return
        if ledger_receipt["legs"].size() != 3 or _sum_legs(ledger_receipt["legs"]) != 0:
            _fail("source science treasury/station/wage receipt is not balanced")
            return
        var treasury_change: int = 0
        for leg in ledger_receipt["legs"]:
            if str(leg["account"]) == "faction/" + str(fid):
                treasury_change = int(leg["delta"])
        if treasury_change != -int(row["cost"]):
            _fail("source N143 treasury debited incorrect paid amount")
            return
        var head: Dictionary = world["research_directors"][fid]
        if int(head["progress"]) != 10 or head["research"] == null:
            _fail("N143 did not record real ten-worker science work")
            return
        # The authoritative market and station IDs are verified from the
        # actual original rows, never reconstructed by name conventions.
        if not world["facilities"].has(str(row["facility_id"])):
            _fail("research paid a fictitious facility")
            return
        if not world["populations"].has(str(row["population_id"])):
            _fail("research paid a fictitious household")
            return
    var before_repeat: Dictionary = runner.checkpoint()
    var repeat: Dictionary = runner.production.apply_native_research_phase(
        1, source_factions, 32)
    if not repeat.get("ok", false):
        _fail("replayed same tick should be harmless source refusal")
        return
    var after_repeat: Dictionary = runner.checkpoint()
    if after_repeat["native_production"]["ledger"] != before_repeat["native_production"]["ledger"]:
        _fail("N143 charged the same faction twice for one tick")
        return
    if after_repeat["native_production"]["world"]["research_receipts"] != world["research_receipts"]:
        _fail("N143 replay duplicated a research receipt")
        return
    # Real disk save/reload, not an in-memory restore of a conveniently
    # supplied dictionary. A restart must keep faction/tech progress.
    var save_path: String = "user://tests/p2-n143-" + str(Time.get_ticks_usec()) + ".json"
    if SaveState.save_runner(runner, save_path) != OK:
        _fail("N38 failed to persist real native science")
        return
    var restored = Runtime.new()
    if not restored.start_from_seed(seed):
        _fail("new native runner could not initialize")
        return
    var load: Dictionary = SaveState.load_runner(restored, seed, save_path)
    if not load.get("ok", false):
        _fail("N38 could not restore N143 research and accounts: " + str(load))
        return
    if restored.economy_snapshot()["research_directors"] != world["research_directors"]:
        _fail("science progress changed across actual disk restart")
        return
    if restored.production.ledger_snapshot() != money:
        _fail("faction money or N9 receipts changed across restart")
        return
    # Source N82 root science needs 40–50 paid work: this must continue
    # past first shift, not award a technology immediately on tick 1.
    var before_tech: int = _completed(world["research"])
    for _step in range(5):
        restored.queue_control("step", 1)
        restored.advance_frame(0.0)
        if not restored.last_phase_failure().is_empty():
            _fail("N143 resumed science tick failed: " +
                str(restored.last_phase_failure()))
            return
    var continued: Dictionary = restored.checkpoint()["native_production"]["world"]
    if _completed(continued["research"]) <= before_tech:
        _fail("real research never completed an original N82 technology")
        return
    if continued["research_receipts"].size() < world["research_receipts"].size():
        _fail("research receipt history lost after restart")
        return
    if _sum(restored.production.ledger_snapshot()["balances"]) != total:
        _fail("N9 total money changed during continued research")
        return
    var absolute: String = ProjectSettings.globalize_path(save_path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_GATE4_ORIGINAL_N143_PAID_RESEARCH_N9_SAVE_PASS")
    quit(0)

func _sum(balances: Dictionary) -> int:
    var n: int = 0
    for val in balances.values():
        n += int(val)
    return n

func _sum_legs(legs: Array) -> int:
    var n: int = 0
    for item in legs:
        n += int(item.get("delta", 0))
    return n

func _completed(rows: Dictionary) -> int:
    var n: int = 0
    for ids in rows.values():
        n += ids.size()
    return n

func _fail(reason: String) -> void:
    push_error("P2_N143_PAID_RESEARCH_FAIL: " + reason)
    quit(1)
