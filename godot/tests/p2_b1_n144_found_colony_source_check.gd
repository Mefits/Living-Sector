extends SceneTree
## Miro Chat2 B1 / Frozen Rust colony.rs::proposals + N134::HeadDecision.
## SOURCE INTEGRATION REGRESSION -- NOT RUN before full Rust transfer.
## This intentionally does not test a complete N14/N21/N97 shipment
## or N154 final station establishment.
const NativeData = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Registry = preload("res://scripts/sim/world_registry.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const N134Construction = preload("res://scripts/sim/phase2/unified_n134_construction_head.gd")
const N144Found = preload("res://scripts/sim/phase2/unified_n144_new_colony_head.gd")
const N144Orders = preload("res://scripts/sim/phase2/unified_n144_colony_contracts.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("no actual frozen Galaxy seed")
        return
    var model := Model.new()
    var registry := Registry.new()
    if not model.load_seed(seed) or not registry.load_seed(seed):
        _fail("N4 real body identities or N142 chart missing")
        return
    var graph: RefCounted = registry.graph()
    if not graph.has_location("mars-colony"):
        _fail("original Rust spawner did not chart Mars")
        return
    var projection: Dictionary = Adapter.from_seed(seed)
    if not projection.get("ok", false):
        _fail("canonical N39 seed projection failed")
        return
    var world_data: Dictionary = projection["world"].duplicate(true)
    # Deliberately detached fixture, never a live initial free tech or
    # faction/personality rebalance: a Head can only found after the
    # original N143 orbital_habitats research has actually completed.
    var faction: String = "terran-authority"
    world_data["research"][faction].append("orbital_habitats")
    world_data["research_directors"][faction]["technologies"].append("orbital_habitats")
    world_data["research_directors"][faction]["profile"]["expansion"] = 10.0
    var sources: Dictionary = {}
    for f in seed["factions"]:
        sources[str(f["id"])] = f.duplicate(true)
    var canonical := N39.new()
    if not canonical.initialize(world_data):
        _fail("N39 rejected original source world")
        return
    if not canonical.run_tick(1, 1).get("ok", false):
        _fail("N158/N39 original tick not available")
        return
    var before: Dictionary = canonical.world_snapshot()
    var prior_bank: Dictionary = canonical.ledger_snapshot()
    var new_site: Dictionary = N144Found.propose(
        before, model, graph, faction, 1, 1)
    if not new_site.get("ok", false) or not new_site.get("ready", false):
        _fail("source new site proposal blocked: " + str(new_site.get("reason", "")))
        return
    var baseline: Dictionary = N134Construction.choose(
        before, sources, model, graph, faction, 1, 1)
    if not baseline.get("ok", false):
        _fail("N111/N134 original market comparator failed")
        return
    var vote: Dictionary = N144Orders.approval(
        before, baseline, new_site, faction, 1, 1)
    if not vote.get("ok", false) or not vote.get("authorized", false):
        _fail("native N113/N134 did not authorize source-prioritized found_colony")
        return
    if str(vote.get("head", {}).get("selected_option", "")) != "found_colony":
        _fail("original N134 HeadDecision did not choose founding")
        return
    if canonical.world_snapshot() != before or canonical.ledger_snapshot() != prior_bank:
        _fail("read-only B1 HeadDecision changed canonical world or treasury")
        return
    var applied: Dictionary = canonical.apply_native_n144_found_colony(
        1, faction, baseline, model, graph, sources, 1)
    if not applied.get("ok", false) or not applied.get("founded", false):
        _fail("N39 refused the real N134 founding grant: " + str(applied.get("reason", "")))
        return
    var after: Dictionary = canonical.world_snapshot()
    var site_id: String = str(applied["site_id"])
    var site: Dictionary = after.get("construction_sites", {}).get(site_id, {})
    var receipt: Dictionary = after.get("construction_receipts", {}).get(
        "n151_colony_approved:" + site_id, {})
    if str(site.get("body_id", "")) != str(new_site["plan"]["body_id"]) or (
            str(site.get("location_name", "")) != str(new_site["plan"]["destination"]) or
            str(site.get("labor", {}).get("colony_source", "")) != str(new_site["plan"]["source"]) or
            int(site.get("progress_delivered", -1)) != 0 or
            str(receipt.get("kind", "")) != "colony_approved" or
            int(receipt.get("capital", -1)) != 0 or
            not after["research_directors"][faction].has("strategic")):
        _fail("N39 founding site or source N113 Director is not canonical")
        return
    var loc: String = str(site["location_name"])
    if after["markets"].has(loc) or (
            after["facilities"] != before["facilities"] or
            after["populations"] != before["populations"] or
            after["ships"] != before["ships"] or
            after["markets"] != before["markets"] or
            after["bodies"] != before["bodies"] or
            after["faction_treasuries"] != before["faction_treasuries"] or
            canonical.ledger_snapshot() != prior_bank):
        _fail("B1 invented colony station, passenger, material, ship or credits")
        return
    if Schema.validate(after) != "" or (
            after["construction_sites"].size() != before["construction_sites"].size() + 1):
        _fail("N39 schema or single-site cardinality lost")
        return
    var replay: Dictionary = canonical.apply_native_n144_found_colony(
        1, faction, baseline, model, graph, sources, 1)
    if replay.get("founded", false) or canonical.world_snapshot()["construction_sites"].size() != after["construction_sites"].size():
        _fail("B1 duplicate same-head colony site produced")
        return
    var checkpoint: Dictionary = canonical.snapshot()
    var restored := N39.new()
    if not restored.restore(checkpoint) or (
            restored.world_snapshot() != canonical.world_snapshot() or
            restored.ledger_snapshot() != canonical.ledger_snapshot()):
        _fail("N38 lost N113 source decision or N151 unfunded site")
        return
    print("P2_B1_SOURCE_N134_NEW_COLONY_SITE_NO_FREE_ACTORS_N38_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_B1_N144_FOUND_COLONY_FAIL: " + reason)
    quit(1)
