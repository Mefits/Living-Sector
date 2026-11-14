extends SceneTree
## ONE native Gate4 acceptance; don't schedule Actions on each edit.
## This verifies real source authorizations are fail-closed and that
## canonical N154/N141 state survives N38 disk, without fake builders,
## markets, treasury or constructed facilities.
## Godot command (future coordinated checkpoint only):
## godot --headless --path godot --script res://tests/p2_gate4_native_construction_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const World = preload("res://scripts/sim/world_model.gd")
const Construction = preload("res://scripts/sim/phase2/unified_native_construction_phase.gd")
const N134 = preload("res://scripts/sim/phase2/unified_n134_construction_head.gd")
const N91 = preload("res://scripts/sim/phase2/unified_n91_construction_dispatch.gd")
const Locations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen source unavailable")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("N39/N158 cannot load the real source world: " + runner.boot_error())
        return
    var state: Dictionary = runner.economy_snapshot()
    if state.get("construction_sites", {}).size() != 0 or state.get("construction_contracts", {}).size() != 0:
        _fail("clean Rust source has fabricated completed construction")
        return
    var source_factions: Dictionary = {}
    for faction in seed["factions"]:
        source_factions[str(faction["id"])] = faction.duplicate(true)
    var world = World.new()
    var roster = Roster.new()
    if not world.load_seed(seed) or not roster.load_seed(seed):
        _fail("source orbital/route graph unavailable")
        return
    var resolver = Locations.new()
    if not resolver.load_seed(seed):
        _fail("original source N91 location resolver failed")
        return
    var money: Dictionary = runner.production.ledger_snapshot()
    var initial_engineers: Dictionary = N91.propose(state, resolver, 1, money)
    if not initial_engineers.get("ok", false) or not initial_engineers.get("assignments", []).is_empty():
        _fail("N91 commissioned engineers without original physical construction sites")
        return
    # Security negative: editing only site.progress to 600/600 in a
    # detached fixture cannot create real N15/N104 delivery receipts.
    var fabricated: Dictionary = state.duplicate(true)
    var source_locations: Array = fabricated["markets"].keys()
    source_locations.sort()
    var test_loc: String = str(source_locations[0])
    var home_station_id: String = str(fabricated["markets"][test_loc]["owner"])
    var home_station: Dictionary = fabricated["facilities"][home_station_id]
    fabricated["construction_sites"]["site-negative-no-physical-delivery"] = {
        "id": "site-negative-no-physical-delivery",
        "location_name": test_loc, "faction_id": str(home_station["faction"]),
        "body_id": str(home_station["body_id"]), "facility_type": "farm",
        "name": "Not a real commissioned project",
        "commodity": "metals", "completed": false,
        "progress_required": 600, "progress_delivered": 600,
        "labor": {"required": 150, "completed": 0, "station_order": null}}
    var forged_eng: Dictionary = N91.propose(fabricated, resolver, 1, money)
    if not forged_eng.get("ok", false) or not forged_eng.get("assignments", []).is_empty():
        _fail("N91 accepted fake materials without a N15 unload/N9 settlement")
        return
    var before: Dictionary = runner.checkpoint()
    var ids: Array = source_factions.keys()
    ids.sort()
    for fid in ids:
        var proposal: Dictionary = Construction.observe(state,
            source_factions, world, roster.registry.graph(), str(fid), 1)
        if not proposal.get("ok", false) or not (proposal.get("view") is Dictionary):
            _fail("N154 cannot observe actual 0.6.7 faction/markets: " + str(fid))
            return
        var head: Dictionary = N134.choose(state, source_factions,
            world, roster.registry.graph(), str(fid), 1, 32)
        if not head.get("ok", false) or not (head.get("head") is Dictionary):
            _fail("N134 source N111 comparison unavailable on real seed: " + str(fid))
            return
        var refused: Dictionary = Construction.stage(state,
            source_factions, world, roster.registry.graph(), str(fid),
            1, 32, false)
        if refused.get("ok", true) or str(refused.get("reason", "")) != "n134_head_authorization_required":
            _fail("N154 minted a building without real N134 head authorization")
            return
    if runner.checkpoint() != before:
        _fail("native construction preview changed N9 wallets or World")
        return
    runner.queue_control("step", 1)
    runner.advance_frame(0.0)
    if runner.tick_count != 1 or not runner.last_phase_failure().is_empty():
        _fail("N154/N141 spoiled normal economic+AI tick: " +
            str(runner.last_phase_failure()))
        return
    if runner.economy_snapshot()["construction_sites"].size() != 0:
        _fail("N154 preview built facilities for free")
        return
    var saved: Dictionary = runner.checkpoint()
    var path: String = "user://tests/p2-n154-" + str(Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(runner, path) != OK:
        _fail("N38 construction-state save failed")
        return
    var restart = Runner.new()
    if not restart.start_from_seed(seed):
        _fail("N38 restart boot failed")
        return
    var loaded: Dictionary = Saves.load_runner(restart, seed, path)
    if not loaded.get("ok", false):
        _fail("N38 saved construction domain could not restore: " + str(loaded))
        return
    var restored: Dictionary = restart.economy_snapshot()
    for key in ["construction_sites", "construction_contracts",
            "construction_receipts", "construction_next_db_id"]:
        if restored.get(key) != saved["native_production"]["world"].get(key):
            _fail("N154 authoritative registry lost after disk restart: " + key)
            return
    if restart.production.ledger_snapshot() != saved["native_production"]["ledger"]:
        _fail("N154 preview/save silently altered the source N9 ledger")
        return
    var filepath: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(filepath)
    DirAccess.remove_absolute(filepath + ".bak")
    print("P2_GATE4_N134_N91_N154_REAL_SEED_SOURCE_HEAD_NO_PHANTOM_ENGINEER_AND_DISK_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_GATE4_N154_FAIL: " + message)
    quit(1)
