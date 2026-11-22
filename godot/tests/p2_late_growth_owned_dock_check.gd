extends SceneTree
## A4: one exact source N21 paid-dock fixture without changing live game.
## The source stage builds its real N9 transfer and immutable receipt;
## only owned N39 commit publishes it after all original validations.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const Local = preload("res://scripts/sim/phase1/n39_dock_delta_validator.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("clean source Galaxy boot failed")
        return
    var world: Dictionary = sim.production.snapshot()["world"].duplicate(true)
    var chosen_ship: String = ""
    var chosen_dock: String = ""
    var keys: Array = world["ships"].keys()
    keys.sort()
    for sid in keys:
        var ship: Dictionary = world["ships"][sid]
        if not str(ship.get("active_contract_id", "")).is_empty() or (
                not (ship.get("transit") is Dictionary)) or (
                not ship["transit"].is_empty()):
            continue
        for fid in world["facilities"]:
            var fac: Dictionary = world["facilities"][fid]
            if int(fac.get("docking_capacity", 0)) <= 0 or (
                    bool(fac.get("abandoned", false))):
                continue
            var occupants: int = 0
            for other in world["ships"].values():
                if str(other.get("docked_at", "")) == str(fid):
                    occupants += 1
            if occupants >= int(fac["docking_capacity"]):
                continue
            chosen_ship = str(sid)
            chosen_dock = str(fid)
            break
        if not chosen_ship.is_empty():
            break
    if chosen_ship.is_empty():
        _fail("no actual source ship/facility for paid N21 test fixture")
        return
    # Fixture only: position an uncontracted source actor at a vacant
    # original dock, with an explicitly accounted starting N9 budget.
    world["ships"][chosen_ship]["location"] = world["facilities"][chosen_dock]["location"]
    world["ships"][chosen_ship]["docked_at"] = ""
    world["ships"][chosen_ship]["transit"] = {}
    world["ships"][chosen_ship]["credits"] = maxi(
        int(world["ships"][chosen_ship]["credits"]), 1000)
    if world["ships"][chosen_ship].has("dock_attempt_start_tick"):
        world["ships"][chosen_ship]["dock_attempt_start_tick"] = null
    var before_issue: String = Schema.validate(world)
    if not before_issue.is_empty():
        _fail("paid source fixture invalid BEFORE N21: " + before_issue)
        return
    var owner := N39.new()
    if not owner.initialize(world):
        _fail("N39 cannot import accounted source dock fixture")
        return
    var before: Dictionary = owner.snapshot()
    var version: int = owner.n21_write_version()
    var owned: RefCounted = owner.get("_ledger").fork()
    var paid: Dictionary = Dock._admit(before["world"].duplicate(true),
        owned,
        chosen_dock, chosen_ship, 1, "request_fast_path")
    if not paid.get("ok", false) or int(paid.get("fee", 0)) <= 0:
        _fail("original N21 stage did not produce real paid N9 transfer: " + str(paid))
        return
    var op: String = str(paid["receipt"]["operation_id"])
    var local_issue: String = Local.validate_delta(
        before["world"], paid["world"], paid["ledger_snapshot"].snapshot())
    var full_issue: String = Schema.validate(paid["world"])
    if not local_issue.is_empty() or not full_issue.is_empty():
        _fail("source-owned N21 paid outcome rejected by local/Schema: " +
            local_issue + " / " + full_issue)
        return
    paid["expected_n21_version"] = version
    var result: Dictionary = owner._commit_native_n21(paid, owned)
    if not result.get("ok", false) or owner.n21_write_version() != version + 1:
        _fail("real N21 paid stage not committed atomically: " + str(result))
        return
    var after: Dictionary = owner.snapshot()
    var fee: int = int(paid["fee"])
    var ship_account: String = Schema.ship_account(chosen_ship)
    var facility_account: String = Schema.facility_account(chosen_dock)
    if after["ledger"]["balances"][ship_account] != int(
            before["ledger"]["balances"][ship_account]) - fee or (
            after["ledger"]["balances"][facility_account] != int(
                before["ledger"]["balances"][facility_account]) + fee):
        _fail("N21 actual funds not transferred between source N9 wallets")
        return
    if after["ledger"]["receipts"][op]["legs"] != [
            {"account": ship_account, "delta": -fee},
            {"account": facility_account, "delta": fee}]:
        _fail("original N9 receipt has different economic debit/credit")
        return
    if after["world"]["ships"][chosen_ship]["docked_at"] != chosen_dock or (
            after["world"]["dock_receipts"].get(op) != paid["receipt"]):
        _fail("one authentic N21 source dock receipt was lost")
        return
    var replay: Dictionary = before["world"].duplicate(true)
    replay["dock_receipts"][op] = paid["receipt"].duplicate(true)
    var replay_result: Dictionary = Dock._admit(
        replay, before["ledger"].duplicate(true), chosen_dock,
        chosen_ship, 1, "request_fast_path")
    if replay_result.get("ok", false) or str(
            replay_result.get("reason", "")) != "n21_fifo_duplicate_real_dock_receipt":
        _fail("original source did not reject repeated docking operation ID: " +
            str(replay_result))
        return
    paid["world"]["ships"][chosen_ship]["credits"] = -100
    assert(owned.transfer("after_publication", ship_account, facility_account, 1, 2, "test").get("ok",false))
    if owner.snapshot() != after:
        _fail("original paid N21 external proposal aliases live N39 or N9")
        return
    if OS.get_environment("LS_PROFILE_NATIVE_PHASES") == "1" and (
            int(owner.n21_shadow_profile()["false_rejections"]) != 0):
        _fail("shadow validator falsely rejected legitimate paid N21")
        return
    print("P2_LATE_GROWTH_OWNED_DOCK_PASS fee=" + str(fee) +
        " verified_N9_receipt=true no_alias=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_LATE_GROWTH_OWNED_DOCK_FAIL: " + reason)
    quit(1)
