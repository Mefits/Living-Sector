extends SceneTree
## N39 A4/A5: N21 paid-dock shadow vs original Schema/N9 and stale versions.
## No invented economic tick, cargo or movement is ever published.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Local = preload("res://scripts/sim/phase1/n39_dock_delta_validator.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("source N39 initial world rejected")
        return
    var canonical: Dictionary = sim.production.snapshot()
    var world: Dictionary = canonical["world"]
    var bank: Dictionary = canonical["ledger"]
    var version: int = sim.production.n21_write_version()
    if not Schema.validate(world).is_empty() or (
            Local.validate_delta(world, world, bank) != ""):
        _fail("clean source World rejected by local/full oracle")
        return
    var proposal: Dictionary = {"ok": true, "changed": false,
        "status": "unchanged", "expected_n21_version": version,
        "world": world.duplicate(true), "ledger_snapshot": bank.duplicate(true)}
    var ship_ids: Array = world["ships"].keys()
    var fid: String = str(world["facilities"].keys()[0])
    ship_ids.sort()
    var sid: String = str(ship_ids[0])
    var op: String = "n21:dock:" + sid + ":1"
    var rejected: Dictionary = proposal.duplicate(true)
    rejected["world"]["dock_receipts"][op] = {
        "operation_id": op, "action": "dock", "ship_id": sid,
        "facility_id": fid, "tick": 1, "fee": 50,
        "financial_receipt": op, "source": "request_fast_path"}
    # The full Schema alone validates physical receipt shape. Local N21
    # must ALSO demand an actual immutable N9 two-legged paid receipt.
    if not Schema.validate(rejected["world"]).is_empty() or (
            Local.validate_delta(world, rejected["world"],
                rejected["ledger_snapshot"]) != "missing_native_n21_n9_payment"):
        _fail("forged docking invoice was not separated from Schema oracle")
        return
    var result: Dictionary = sim.production._commit_native_n21(rejected)
    if result.get("ok", false):
        _fail("N21 published paid dock invoice without N9 proof")
        return
    if sim.production.snapshot() != canonical or (
            sim.production.n21_write_version() != version):
        _fail("rejected paid dock touched World, N9 or revision")
        return
    rejected = proposal.duplicate(true)
    rejected["world"]["dock_receipts"][op] = {
        "operation_id": op, "action": "dock", "ship_id": sid,
        "facility_id": fid, "tick": 1, "fee": 0.5,
        "financial_receipt": op}
    if Local.validate_delta(world, rejected["world"],
            rejected["ledger_snapshot"]) != "invalid_native_n21_fee":
        _fail("fractional N21 dock fee escaped local validator")
        return
    result = sim.production._commit_native_n21(rejected)
    if result.get("ok", false):
        _fail("fractional dock receipt was committed")
        return
    rejected = proposal.duplicate(true)
    rejected["world"]["facilities"][fid]["dock_queue"] = [sid, sid]
    var local_fifo: String = Local.validate_delta(
        world, rejected["world"], rejected["ledger_snapshot"])
    var full_fifo: String = Schema.validate(rejected["world"])
    if local_fifo != "invalid_native_n21_fifo_identity" or (
            full_fifo != local_fifo):
        _fail("FIFO duplicate was not rejected identically by local and Schema")
        return
    result = sim.production._commit_native_n21(rejected)
    if result.get("ok", false) or str(result.get("reason", "")) != (
            "n21_schema_" + full_fifo):
        _fail("existing FIFO refusal reason changed: " + str(result))
        return
    # Explicit stale generation is rejected before cloning or publication.
    rejected = proposal.duplicate(true)
    rejected["expected_n21_version"] = version + 1
    result = sim.production._commit_native_n21(rejected)
    if result.get("ok", false) or str(result.get("reason", "")) != (
            "n21_stale_write_version"):
        _fail("stale N21 proposal accepted or refusal reason changed")
        return
    if sim.production.snapshot() != canonical:
        _fail("refused source N21 stage changed World/N9")
        return
    result = sim.production._commit_native_n21(proposal)
    if not result.get("ok", false) or (
            sim.production.n21_write_version() != version + 1):
        _fail("valid canonical N21 stage did not advance version")
        return
    if sim.production.snapshot() != canonical:
        _fail("no-change N21 publish changed canonical economic checkpoint")
        return
    if sim.production._commit_native_n21(proposal).get("ok", false):
        _fail("accepted N21 generation replayed")
        return
    var restored := N39.new()
    if not restored.restore(sim.production.snapshot()):
        _fail("strict N39/N38 snapshot restore rejected")
        return
    if restored.n21_write_version() >= 0 or (
            restored.n21_write_version() == version + 1):
        _fail("restored owner reused stale positive write-generation")
        return
    proposal["expected_n21_version"] = restored.n21_write_version()
    if not restored._commit_native_n21(proposal).get("ok", false):
        _fail("fresh restored generation cannot accept own valid stage")
        return
    if restored.snapshot() != canonical:
        _fail("restored no-delta N21 commit diverged")
        return
    if OS.get_environment("LS_PROFILE_NATIVE_PHASES") == "1" and (
            int(sim.production.n21_shadow_profile()["false_rejections"]) != 0):
        _fail("local shadow rejected a source-approved N21 stage")
        return
    print("P2_PARALLEL_A_N21_SHADOW_VERSION_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PARALLEL_A_N21_SHADOW_VERSION_FAIL: " + reason)
    quit(1)
