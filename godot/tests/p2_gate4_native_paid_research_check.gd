extends SceneTree
## Gate4: real 0.6.7 faction treasury -> N143 paid science -> N9 receipts
## -> saved N155 progress, without invented labs, labor or research accounts.
## One acceptance run, not a suite of micro-PR tests.
## godot --headless --path godot --script res://tests/p2_gate4_native_paid_research_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const N143 = preload("res://scripts/sim/phase2/unified_native_research_phase.gd")
const NativeCoherence = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")
const NativeTimeline = preload("res://scripts/sim/phase2/unified_native_timeline_integrity.gd")
const NativeFrameGuard = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const WorldSchema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const NativeProduction = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const ShipModules = preload("res://scripts/port/n108_shipyard_module_catalog.gd")

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
    # A tiny IEEE-754 JSON difference in a dimensionless N155
    # personality weight is permitted. Real money, stock, contracts,
    # scientific progress and material changes to personality are not.
    var before_disk: Dictionary = runner.checkpoint()
    var corrupted: Variant = JSON.parse_string(
        JSON.stringify(before_disk, "", true, true))
    if not (corrupted is Dictionary):
        _fail("N38 diagnostic JSON cannot decode canonical World")
        return
    var marked: Dictionary = corrupted
    var director: Dictionary = marked["native_production"]["world"][
        "research_directors"][str(faction_ids[0])]
    director["profile"]["science"] = float(
        director["profile"]["science"]) + 0.01
    if NativeFrameGuard.verify_authoritative_frame(
            before_disk, marked).get("ok", false):
        _fail("N38 erroneously accepted material personality corruption")
        return
    marked = JSON.parse_string(JSON.stringify(before_disk, "", true, true))
    marked["native_production"]["world"][
        "faction_treasuries"][str(faction_ids[0])] = int(
        marked["native_production"]["world"]["faction_treasuries"][
            str(faction_ids[0])]) + 1
    if NativeFrameGuard.verify_authoritative_frame(
            before_disk, marked).get("ok", false):
        _fail("N38 erroneously accepted even one invented treasury credit")
        return
    var save_path: String = "user://tests/p2-n143-" + str(Time.get_ticks_usec()) + ".json"
    var save_error: Error = SaveState.save_runner(runner, save_path)
    if save_error != OK:
        # No N38 integrity guard is weakened. Report the precise
        # read-only failed preflight when the real paid-world save fails.
        var live: Dictionary = runner.checkpoint()
        var parsed: Variant = JSON.parse_string(
            JSON.stringify(live, "", true, true))
        var consistency: Dictionary = NativeCoherence.validate(live)
        var timeline: Dictionary = NativeTimeline.validate(live)
        var json_frame: Dictionary = {"ok": false, "reason": "json_not_dictionary"}
        var encoded_bytes: int = 0
        if parsed is Dictionary:
            json_frame = NativeFrameGuard.verify_authoritative_frame(
                live, parsed)
            encoded_bytes = JSON.stringify(
                SaveState._wrap(live), "\t", true, true).to_utf8_buffer().size()
        _fail("N38 failed to persist real native science: Error=" +
            str(save_error) + " coherence=" + str(consistency) +
            " timeline=" + str(timeline) + " exact_native_json=" +
            str(json_frame) + " envelope_bytes=" + str(encoded_bytes))
        return
    var restored = Runtime.new()
    if not restored.start_from_seed(seed):
        _fail("new native runner could not initialize")
        return
    var load: Dictionary = SaveState.load_runner(restored, seed, save_path)
    if not load.get("ok", false):
        var on_disk: Dictionary = SaveState._read_checkpoint(save_path)
        var diagnostic: Dictionary = {"disk_read": not on_disk.is_empty()}
        if not on_disk.is_empty() and on_disk.get(
                "native_production") is Dictionary:
            var staged: Dictionary = on_disk.duplicate(true)
            var native_ok: bool = restored._normalize_native_snapshot(
                staged["native_production"])
            diagnostic["native_integer_normalization"] = native_ok
            if native_ok:
                diagnostic["native_world_schema"] = WorldSchema.validate(
                    staged["native_production"]["world"])
                if diagnostic["native_world_schema"] == "invalid_ship_state":
                    var invalid_ships: Array = []
                    for sid in staged["native_production"]["world"].get(
                            "ships", {}):
                        var row: Dictionary = staged["native_production"][
                            "world"]["ships"][sid]
                        if not ShipState.new().restore([row]):
                            var fitting: Dictionary = row.get("fitting", {})
                            var expected_derived: Dictionary = ShipModules.combine(
                                fitting.get("slots", {}))
                            var actual_derived: Dictionary = fitting.get(
                                "derived", {})
                            invalid_ships.append({"ship_id": sid,
                                "progression": row.get("progression", {}),
                                "fitting_exact": actual_derived == expected_derived,
                                "fitting_compatible": ShipState._derived_matches_slots(
                                    actual_derived, expected_derived),
                                "fuel": row.get("fuel", null),
                                "fuel_capacity": row.get("fuel_capacity", null),
                                "crew_size": row.get("crew_size", null),
                                "roles": row.get("crew_roles", [])})
                            if invalid_ships.size() >= 3:
                                break
                    diagnostic["invalid_ships"] = invalid_ships
                var isolated := NativeProduction.new()
                diagnostic["n39_restore"] = isolated.restore(
                    staged["native_production"])
            diagnostic["disk_timeline"] = NativeTimeline.validate(on_disk)
            diagnostic["disk_coherence"] = NativeCoherence.validate_serialized_candidate(
                on_disk)
        _fail("N38 could not restore N143 research and accounts: " +
            str(load) + " diagnostic=" + str(diagnostic))
        return
    # Source profile weights are floating-point, and Godot JSON may
    # round their last bit without changing the director's decisions.
    # Compare the GAME-CRITICAL state exactly, not non-authoritative
    # float formatting from a full recursive Dictionary equality.
    var reloaded_world: Dictionary = restored.economy_snapshot()
    if reloaded_world["research_receipts"] != world["research_receipts"] or reloaded_world["research"] != world["research"] or reloaded_world["faction_treasuries"] != world["faction_treasuries"]:
        _fail("research receipts, unlocks or faction treasury changed across disk restart")
        return
    for fid in faction_ids:
        var expected: Dictionary = world["research_directors"][fid]
        var actual: Dictionary = reloaded_world["research_directors"][fid]
        for key in ["progress", "research_required", "research",
                "technologies", "last_research_tick", "last_shift", "history"]:
            if actual.get(key) != expected.get(key):
                _fail("N143 science state lost across restart: " + str(fid) + "." + key +
                    " expected=" + str(expected.get(key)) +
                    " actual=" + str(actual.get(key)))
                return
        for key in ["industry", "science", "expansion", "caution", "aggression"]:
            if not is_equal_approx(float(actual["profile"].get(key, -1.0)),
                    float(expected["profile"].get(key, -2.0))):
                _fail("N155 science personality changed across restart: " + str(fid) + "." + key)
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
