extends SceneTree
## Source-only N151 regression (NOT RUN before full Rust integration).
## This test isolates head authorization just as existing p2_n151 site
## check does; no runtime AI grant or final colony success is claimed.
## Run only in final coordinated Godot gate:
## godot --headless --path godot --script res://tests/p2_n151_original_temporary_dock_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const Original = preload("res://scripts/sim/world_model.gd")
const Registry = preload("res://scripts/sim/world_registry.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("missing frozen 0.6.7 source")
        return
    var model = Original.new()
    var registry = Registry.new()
    if not model.load_seed(seed) or not registry.load_seed(seed):
        _fail("source N4/N43 failed")
        return
    var graph: RefCounted = registry.graph()
    if not graph.has_location("mars-colony") or (
            int(graph.shortest_path("earth-station", "mars-colony").get("distance", -1)) != 18):
        _fail("original N142 SQL colony route absent")
        return
    var physical: Dictionary = Adapter.from_seed(seed)
    if not physical.get("ok", false):
        _fail("canonical N39 seed absent")
        return
    var economy: Dictionary = physical["world"].duplicate(true)
    # Fixture-only original tech gate, not a grant in live N158.
    economy["research"]["terran-authority"].append("orbital_habitats")
    economy["research_directors"]["terran-authority"]["technologies"].append("orbital_habitats")
    var authoritative = N39.new()
    if not authoritative.initialize(economy) or not authoritative.run_tick(1, 1).get("ok", false):
        _fail("source N39 initial physical tick rejected")
        return
    var before: Dictionary = authoritative.world_snapshot()
    var baseline_money: Dictionary = authoritative.ledger_snapshot()
    if not authoritative.apply_native_colony_prepare_docks(1, graph).get("ok", false) or (
            authoritative.world_snapshot() != before):
        _fail("unapproved N151 project created a real dock or changed world")
        return
    var authorized: Dictionary = authoritative.apply_native_colony_foundation(
        1, "terran-authority", "mars", "earth-station", model, graph, true)
    if not authorized.get("ok", false):
        _fail("N151 original approved site not accepted: " + str(authorized.get("reason", "")))
        return
    var site_id: String = str(authorized.get("site_id", ""))
    var before_dock: Dictionary = authoritative.world_snapshot()
    if before_dock["facilities"].values().any(func(f):
            return str(f.get("location", "")) == "mars-colony"):
        _fail("founding site already made a free dock")
        return
    var commissioned: Dictionary = authoritative.apply_native_colony_prepare_docks(1, graph)
    if not commissioned.get("ok", false) or commissioned.get("created", []).size() != 1:
        _fail("N151 source prepare_docks rejected actual site: " + str(commissioned.get("reason", "")))
        return
    var world: Dictionary = authoritative.world_snapshot()
    var entry: Dictionary = commissioned["created"][0]
    var fid: String = str(entry["facility_id"])
    var pid: String = str(entry["population_id"])
    var dock: Dictionary = world["facilities"].get(fid, {})
    var household: Dictionary = world["populations"].get(pid, {})
    var receipt: Dictionary = world["construction_receipts"].get("n151_colony_dock:" + site_id, {})
    if str(dock.get("type", "")) != "construction_dock" or (
            str(dock.get("location", "")) != "mars-colony" or
            int(dock.get("docking_capacity", -1)) != 4 or
            int(dock.get("credits", -1)) != 0 or
            int(dock.get("crew_count", -1)) != 0 or
            str(household.get("location", "")) != "mars-colony" or
            int(household.get("count", -1)) != 0 or
            int(household.get("wealth", -1)) != 0 or
            world["markets"].has("mars-colony") or
            str(receipt.get("facility_id", "")) != fid):
        _fail("N151 invented commercial colony, people or wealth")
        return
    if Schema.validate(world) != "" or authoritative.ledger_snapshot()["balances"].size() != baseline_money["balances"].size() + 2:
        _fail("N151 did not add exactly two zero-asset N9 wallets")
        return
    var baseline_total: int = 0
    var after_total: int = 0
    for balance in baseline_money["balances"].values():
        baseline_total += int(balance)
    for balance in authoritative.ledger_snapshot()["balances"].values():
        after_total += int(balance)
    if baseline_total != after_total:
        _fail("N151 minted physical credits")
        return
    var replay: Dictionary = authoritative.apply_native_colony_prepare_docks(1, graph)
    if not replay.get("ok", false) or not replay.get("created", []).is_empty() or (
            world != authoritative.world_snapshot()):
        _fail("N151 duplicated a real dock on replay")
        return
    var checkpoint: Dictionary = authoritative.snapshot()
    var returned = N39.new()
    if not returned.restore(checkpoint) or returned.world_snapshot() != world or (
            returned.ledger_snapshot() != authoritative.ledger_snapshot()):
        _fail("N38 lost original dock/household and/or invented money")
        return
    var forged: Dictionary = checkpoint.duplicate(true)
    forged["world"]["populations"][pid]["colony_dock_id"] = "forged"
    if N39.new().restore(forged):
        _fail("N38 accepted forged marketless household")
        return
    print("P2_N151_REAL_SOURCE_EMPTY_DOCK_ZERO_CREDITS_N38_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N151_TEMPORARY_DOCK_FAIL: " + reason)
    quit(1)
