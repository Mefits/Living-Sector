extends SceneTree
## Clean original Galaxy 0.6.7, no fixture or manual ship commands.
## One N158/N39 World, N9 accounts, N38 disk restart at tick 360.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const NativeCoherence = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")
const NativeTimeline = preload("res://scripts/sim/phase2/unified_native_timeline_integrity.gd")
const NativeFrame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")
const NativeWorldSchema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const NativeProduction = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
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
    # The default acceptance remains the official 420-tick gate. Longer
    # runs are explicit, bounded diagnostics of the same real seed and
    # checkpoint: e.g. LS_STAGE2_LONG_TICKS=900 for the N129 tick825 case.
    var limit: int = LAST_TICK
    var requested: String = OS.get_environment("LS_STAGE2_LONG_TICKS")
    if requested.is_valid_int():
        limit = clampi(int(requested), LAST_TICK, 1000)
    var restarted: bool = false
    for tick in range(1, limit + 1):
        if not sim.queue_control("step", 1):
            _fail("tick step rejected at " + str(tick))
            return
        sim.advance_frame(0.0)
        var failure: Dictionary = sim.last_phase_failure()
        if not failure.is_empty() or sim.tick_count != tick:
            _fail("factions/runtime failed tick=" + str(tick) +
                " actual=" + str(sim.tick_count) + " reason=" + str(failure))
            return
        if not CHECK_TICKS.has(tick) and tick != limit and tick != 825:
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
            # Check the actual hashed/tagged N38 envelope, not only an
            # unauthenticated raw JSON preview that is expected to lose
            # binary64 precision. Diagnose SHA/codec vs disk/platform.
            var envelope: Dictionary = Saves._wrap(checkpoint)
            var wire: Variant = JSON.parse_string(JSON.stringify(
                envelope, "\t", true, true))
            var actual_decoded: Dictionary = Saves._unwrap(wire)
            var actual_frame: Dictionary = {"ok": false, "reason": "sha_or_codec_rejected"}
            var actual_stock: bool = false
            if not actual_decoded.is_empty():
                actual_frame = NativeFrame.verify_authoritative_frame(
                    checkpoint, actual_decoded)
                actual_stock = Saves._physical_stock_matches(
                    checkpoint, actual_decoded)
            _fail("N38 disk save rejected at tick360 code=" + str(save_error) +
                " coherence=" + str(NativeCoherence.validate(checkpoint)) +
                " timeline=" + str(NativeTimeline.validate(checkpoint)) +
                " raw_json=" + str(roundtrip) +
                " raw_stock_exact=" + str(stock_exact) +
                " tagged_unwrap=" + str(not actual_decoded.is_empty()) +
                " tagged_native_frame=" + str(actual_frame) +
                " tagged_stock_exact=" + str(actual_stock) +
                " encoded_bytes=" + str(JSON.stringify(envelope,
                    "\t", true, true).to_utf8_buffer().size()))
            return
        var resumed = Runner.new()
        if not resumed.start_from_seed(seed):
            _fail("fresh N158 seed boot after checkpoint failed")
            return
        var loaded: Dictionary = Saves.load_runner(resumed, seed, path)
        if not loaded.get("ok", false) or resumed.tick_count != 360:
            # Fail closed, but reveal which real N38/N39 checkpoint
            # preflight refused the source World. This diagnostic never
            # edits the save, source economy or the active sim.
            var raw_disk: Dictionary = Saves._read_checkpoint(path)
            var restore_probe: Dictionary = {
                "disk_decoded": not raw_disk.is_empty()}
            if not raw_disk.is_empty():
                restore_probe["timeline"] = NativeTimeline.validate(raw_disk)
                restore_probe["serialized_coherence"] = (
                    NativeCoherence.validate_serialized_candidate(raw_disk))
                var isolated: Dictionary = raw_disk.duplicate(true)
                var normalization_ok: bool = resumed._normalize_number_at(
                    isolated, "native_production_multiplier")
                if normalization_ok and isolated.get("native_production") is Dictionary:
                    normalization_ok = resumed._normalize_native_snapshot(
                        isolated["native_production"])
                restore_probe["native_type_normalized"] = normalization_ok
                if normalization_ok:
                    restore_probe["world_schema"] = NativeWorldSchema.validate(
                        isolated["native_production"]["world"])
                    restore_probe["n39_restore"] = NativeProduction.new().restore(
                        isolated["native_production"])
            _fail("N38 disk restore tick360 rejected: " + str(loaded) +
                " diagnosis=" + str(restore_probe))
            return
        var after: Dictionary = resumed.checkpoint()
        if after.is_empty() or not after.has("native_production"):
            _fail("N38 restarted runner lost canonical native frame")
            return
        # Source ledger and contracts MUST remain bit-exact in their
        # authoritative values. JSON may express an integer as 1.0; the
        # original N38 guard permits only exact integers under 2^53,
        # never a changed cent, stock unit, cargo amount or receipt.
        # Raw Dictionary == incorrectly treats 1 vs 1.0 as different
        # before N158 normalizes source numeric fields on restore.
        var exact_restart: Dictionary = NativeFrame.verify_authoritative_frame(
            checkpoint, after)
        if not exact_restart.get("ok", false):
            _fail("N38 strict canonical N9/N104/N15 frame changed at tick360: " +
                str(exact_restart))
            return
        var restored_world: Dictionary = after["native_production"]["world"]
        if restored_world.get("ships", {}).size() != world["ships"].size() or (
                restored_world.get("contract_board", {}).get(
                "contracts", {}).size() != world["contract_board"].get(
                "contracts", {}).size()):
            _fail("N38 changed real actor or contract cardinality at tick360")
            return
        sim = resumed
        restarted = true
    _cleanup(path)
    if not restarted or sim.tick_count != limit:
        _fail("N38 continuity beyond saved tick360 not proven")
        return
    if limit == LAST_TICK:
        print("P2_STAGE2_CLEAN_NATIVE_TICK420_N38_RESTART_PASS elapsed_ms=" +
            str(Time.get_ticks_msec() - started))
    else:
        print("P2_STAGE2_LONG_NATIVE_PASS tick=" + str(limit) +
            " N38_restart_tick=360 elapsed_ms=" +
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
