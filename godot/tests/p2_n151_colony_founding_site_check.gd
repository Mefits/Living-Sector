extends SceneTree
## N151 colony founding N39 commit gate. Real frozen Sol data, with
## an EXPLICIT test-only navigation edge to a future colony destination.
## This is NOT proof that frozen live navigation currently has this edge.
const Native = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const SourceWorld = preload("res://scripts/sim/world_model.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Founding = preload("res://scripts/sim/phase2/unified_n151_colony_founding_phase.gd")

class TestColonyGraph extends RefCounted:
    var allow: bool = true
    func shortest_path(origin: String, destination: String) -> Dictionary:
        if origin == destination and origin == "earth-station":
            return {"reachable": true, "locations": [origin], "distance": 0.0}
        if allow and origin == "earth-station" and destination == "mars-colony":
            return {"reachable": true, "locations": [origin, destination], "distance": 22.0}
        return {"reachable": false, "reason": "no_source_route"}

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy seed unavailable")
        return
    var source = SourceWorld.new()
    if not source.load_seed(seed):
        _fail("frozen orbit/identities unavailable")
        return
    var projection: Dictionary = Adapter.from_seed(seed)
    if not projection.get("ok", false):
        _fail("native source economy rejected: " + str(projection.get("reason", "")))
        return
    var physical: Dictionary = projection["world"].duplicate(true)
    # The original source head only authorizes foundation after a
    # real N143 orbital_habitats research unlock. Test adds this
    # explicitly to a DETACHED snapshot; no gameplay tech is minted.
    physical["research"]["terran-authority"].append("orbital_habitats")
    physical["research_directors"]["terran-authority"]["technologies"].append("orbital_habitats")
    var world = N39.new()
    if not world.initialize(physical):
        _fail("authentic N39 populated founding fixture invalid")
        return
    var first_tick: Dictionary = world.run_tick(1, 1)
    if not first_tick.get("ok", false):
        _fail("source N39 tick 1 did not complete")
        return
    var before: Dictionary = world.world_snapshot()
    var cash_before: Dictionary = world.ledger_snapshot()
    var no_route = TestColonyGraph.new()
    no_route.allow = false
    var blocked: Dictionary = Founding.proposal(before, source, no_route,
        "terran-authority", "mars", "earth-station", 1, 1, true)
    if blocked.get("ok", false) or str(blocked.get("reason", "")) != "n151_colony_location_not_in_original_navigation":
        _fail("new colony was invented without a real directed route")
        return
    var directed = TestColonyGraph.new()
    var rejected: Dictionary = world.apply_native_colony_foundation(
        1, "terran-authority", "mars", "earth-station", source, directed, false)
    if rejected.get("ok", false):
        _fail("colony spawned without a native head grant")
        return
    if world.world_snapshot() != before or world.ledger_snapshot() != cash_before:
        _fail("read-only/unauthorized founding modified physical world")
        return
    var created: Dictionary = world.apply_native_colony_foundation(
        1, "terran-authority", "mars", "earth-station", source, directed, true)
    if not created.get("ok", false) or int(created.get("money_debited", -1)) != 0:
        _fail("N39 rejected real source commission for funded test expedition: " + str(created.get("reason", "")))
        return
    var world_after: Dictionary = world.world_snapshot()
    var site_id: String = str(created.get("site_id", ""))
    var site: Dictionary = world_after.get("construction_sites", {}).get(site_id, {})
    if str(site.get("location_name", "")) != "mars-colony" or str(site.get("body_id", "")) != "mars" or str(site.get("labor", {}).get("colony_source", "")) != "earth-station" or int(site.get("progress_delivered", -1)) != 0:
        _fail("site missing real source identity, correct body or zero materials")
        return
    if world_after["markets"].has("mars-colony") or world_after["populations"].size() != before["populations"].size() or world_after["facilities"].size() != before["facilities"].size():
        _fail("N151 invented market, households or finished facility on approval")
        return
    if world.ledger_snapshot() != cash_before:
        _fail("N151 source zero-cost site spawn minted or charged credits")
        return
    if world.apply_native_colony_foundation(
            1, "terran-authority", "mars", "earth-station", source, directed, true).get("ok", false):
        _fail("native founding site was duplicated")
        return
    var checkpoint: Dictionary = world.snapshot()
    var restored = N39.new()
    if not restored.restore(checkpoint) or restored.world_snapshot() != world_after or restored.ledger_snapshot() != cash_before:
        _fail("N38 did not preserve unbuilt site and unchanged N9 bank")
        return
    var forged: Dictionary = checkpoint.duplicate(true)
    forged["world"]["construction_sites"][site_id]["progress_delivered"] = 600
    var tampered = N39.new()
    if tampered.restore(forged):
        _fail("N38 accepted 600 ghost metals at a nonexistent colony market")
        return
    print("P2_N151_SOURCE_COLONY_SITE_REAL_WORLD_NO_GHOST_MARKET_OR_CITIZEN_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N151_COLONY_SITE_FAIL: " + reason)
    quit(1)
