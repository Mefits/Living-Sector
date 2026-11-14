extends SceneTree
## Clean original Galaxy 0.6.7, no fixture or manual ship commands.
## One N158/N39 World, N9 accounts, N38 disk restart at tick 360.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const NativeCoherence = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")
const NativeTimeline = preload("res://scripts/sim/phase2/unified_native_timeline_integrity.gd")
const NativeFrame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const LAST_TICK: int = 420
const CHECK_TICKS: Array[int] = [1, 60, 120, 240, 360, 361, 420]

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("original Galaxy 0.6.7 seed absent: " + str(seed["error"]))
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("original N158 boot: " + sim.boot_error())
        return
    var initial: Dictionary = sim.checkpoint()
    if initial.is_empty() or not initial.has("native_production"):
        _fail("canonical N38 seed checkpoint missing")
        return
    var original: Dictionary = initial["native_production"]["world"]
    var stats: Dictionary = sim.production_stats()
    if stats.get("markets") != 3 or stats.get("active_facilities") != 15 or original.get("ships", {}).size() != 24:
        _fail("unexpected original 8/3 native markets, facilities or 24 ships")
        return
    var money: int = _money(initial["native_production"]["ledger"])
    var initial_receipts: Dictionary = initial["native_production"]["ledger"].get("receipts", {}).duplicate(true)
    var path: String = "user://tests/p2-clean-stage2-" + str(Time.get_ticks_usec()) + ".json"
    var started: int = Time.get_ticks_msec()
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("original clock rejected x8 speed or pause")
        return
    sim.advance_frame(0.0)
    if not sim.clock.paused or sim.clock.tick_multiplier() != 1:
        _fail("source clock did not apply x8 while paused")
        return
    var restarted: bool = false
    for tick in range(1, LAST_TICK + 1):
        if not sim.queue_control("step", 1):
            _fail("tick step rejected at " + str(tick))
            return
        sim.advance_frame(0.0)
        var failure: Dictionary = sim.last_phase_failure()
        if not failure.is_empty() or sim.tick_count != tick:
            _fail("factions/runtime failed tick=" + str(tick) +
                " actual=" + str(sim.tick_count) + " reason=" + str(failure))
            return
        if not CHECK_TICKS.has(tick):
            continue
        var checkpoint: Dictionary = sim.checkpoint()
        if checkpoint.is_empty() or not checkpoint.has("native_production"):
            _fail("N38 failed a healthy snapshot at " + str(tick))
            return
        var frame: Dictionary = checkpoint["native_production"]
        var world: Dictionary = frame["world"]
        var bank: Dictionary = frame["ledger"]
        var money_audit: Dictionary = _money_audit(money, initial_receipts, bank)
        if not money_audit.get("ok", false):
            _fail("unaccounted N9 balance mutation at tick " + str(tick) +
                ": " + str(money_audit))
            return
        if not (world.get("ships") is Dictionary) or not (world.get("contract_board") is Dictionary):
            _fail("N39 lost native fleet/contract board at " + str(tick))
            return
        print("P2_STAGE2_CLEAN_CHECK tick=" + str(tick) +
            " elapsed_ms=" + str(Time.get_ticks_msec() - started) +
            " ships=" + str(world["ships"].size()) +
            " contracts=" + str(world["contract_board"].get("contracts", {}).size()) +
            " receipts=" + str(bank.get("receipts", {}).size()) +
            " spendable_credits=" + str(money_audit["observed"]) +
            " native_wages_writeoffs=" + str(money_audit["documented_sinks"]))
        if tick != 360:
            continue
        var save_error: Error = Saves.save_runner(sim, path)
        if save_error != OK:
            # The N38 guard must stay strict. Diagnose the offending exact
            # source invariant or JSON field, never bypass it.
            var candidate: Variant = JSON.parse_string(JSON.stringify(
                checkpoint, "", true, true))
            var roundtrip: Dictionary = {"ok": false, "reason": "json_parse_failed"}
            var stock_exact: bool = false
            if candidate is Dictionary:
                roundtrip = NativeFrame.verify_authoritative_frame(
                    checkpoint, candidate)
                stock_exact = Saves._physical_stock_matches(
                    checkpoint, candidate)
            _fail("N38 disk save rejected at tick360 code=" + str(save_error) +
                " coherence=" + str(NativeCoherence.validate(checkpoint)) +
                " timeline=" + str(NativeTimeline.validate(checkpoint)) +
                " native_json=" + str(roundtrip) +
                " market_stock_exact=" + str(stock_exact) +
                " encoded_bytes=" + str(JSON.stringify(checkpoint,
                    "", true, true).to_utf8_buffer().size()))
            return
        var resumed = Runner.new()
        if not resumed.start_from_seed(seed):
            _fail("fresh N158 seed boot after checkpoint failed")
            return
        var loaded: Dictionary = Saves.load_runner(resumed, seed, path)
        if not loaded.get("ok", false) or resumed.tick_count != 360:
            _fail("N38 disk restore tick360 rejected: " + str(loaded))
            return
        var after: Dictionary = resumed.checkpoint()
        if after.is_empty() or after["native_production"]["ledger"].get("balances", {}) != bank.get("balances", {}) or after["native_production"]["ledger"].get("receipts", {}) != bank.get("receipts", {}):
            _fail("N38 changed canonical N9 balances or immutable receipts")
            return
        var restored_world: Dictionary = after["native_production"]["world"]
        if restored_world.get("contract_board", {}).get("contracts", {}) != world["contract_board"].get("contracts", {}):
            _fail("N38 changed real N104 obligations at tick360")
            return
        for id in world["ships"]:
            var before_ship: Dictionary = world["ships"][id]
            var after_ship: Dictionary = restored_world.get("ships", {}).get(id, {})
            if before_ship.get("cargo", {}) != after_ship.get("cargo", {}) or before_ship.get("credits") != after_ship.get("credits"):
                _fail("N38 changed physical cargo or wallet: " + str(id))
                return
        sim = resumed
        restarted = true
    _cleanup(path)
    if not restarted or sim.tick_count != LAST_TICK:
        _fail("N38 continuity through user tick361 not proven")
        return
    print("P2_STAGE2_CLEAN_NATIVE_TICK420_N38_RESTART_PASS elapsed_ms=" +
        str(Time.get_ticks_msec() - started))
    quit(0)


## Frozen Rust ShipCrew wages are accrued and nonspendable: N9 correctly
## debits a ship wallet with a SINGLE-leg native_ship_crew_wages receipt.
## Decommission/removal also closes a real wallet via explicit write-off.
## Everything else must be a balanced N9 transfer. Never mislabel these
## authored native sinks as a gameplay money-conservation failure.
func _money_audit(opening: int, initial: Dictionary, bank: Dictionary) -> Dictionary:
    var receipts: Dictionary = bank.get("receipts", {})
    for old_id in initial:
        if not receipts.has(old_id) or receipts[old_id] != initial[old_id]:
            return {"ok": false, "reason": "n9_original_receipt_missing_or_modified", "receipt": old_id}
    var expected: int = opening
    var sinks: int = 0
    for id in receipts:
        if initial.has(id):
            continue
        var row: Dictionary = receipts[id]
        if str(row.get("id", "")) != str(id) or not (row.get("legs") is Array) or row["legs"].is_empty():
            return {"ok": false, "reason": "n9_new_receipt_invalid", "receipt": id}
        var delta: int = 0
        for leg in row["legs"]:
            if not (leg is Dictionary) or typeof(leg.get("delta")) != TYPE_INT:
                return {"ok": false, "reason": "n9_new_receipt_leg_invalid", "receipt": id}
            delta += int(leg["delta"])
        if delta > 0 or (delta < 0 and str(row.get("kind", "")) not in [
                "native_ship_crew_wages", "ship_decommissioned", "facility_removed"]):
            return {"ok": false, "reason": "n9_unapproved_money_creation_or_sink", "receipt": id,
                "delta": delta, "kind": row.get("kind", "")}
        expected += delta
        sinks -= delta
    var observed: int = _money(bank)
    if observed != expected:
        return {"ok": false, "reason": "n9_balances_not_explained_by_receipts",
            "expected": expected, "observed": observed}
    return {"ok": true, "expected": expected, "observed": observed,
        "documented_sinks": sinks}

func _money(bank: Dictionary) -> int:
    var total: int = 0
    for credits in bank.get("balances", {}).values():
        total += int(credits)
    return total

func _cleanup(path: String) -> void:
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")

func _fail(reason: String) -> void:
    push_error("P2_STAGE2_CLEAN_NATIVE_ACCEPTANCE_FAIL: " + reason)
    quit(1)
