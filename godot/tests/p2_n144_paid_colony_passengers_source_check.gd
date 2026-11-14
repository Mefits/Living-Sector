extends SceneTree
## N144 real contract source regression; added NOT EXECUTED until
## the project's final complete-Rust Godot integration test.
## No actor teleportation, free colony site, actual flight or final colony
## establishment is simulated by this isolated contract-source check.
const NativeData = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const WorldRegistry = preload("res://scripts/sim/world_registry.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const N144 = preload("res://scripts/sim/phase2/unified_n144_colony_contracts.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("original Galaxy data not found")
        return
    var model := WorldModel.new()
    var registry := WorldRegistry.new()
    if not model.load_seed(seed) or not registry.load_seed(seed):
        _fail("original N4/N43 chart unavailable")
        return
    var graph: RefCounted = registry.graph()
    if not graph.has_location("mars-colony"):
        _fail("original spawner chart for Mars missing")
        return
    var imported: Dictionary = Adapter.from_seed(seed)
    if not imported.get("ok", false):
        _fail("canonical N39 seed missing")
        return
    var world_data: Dictionary = imported["world"].duplicate(true)
    # The source N144 requires real paid orbital habitats. This is a
    # DETACHED regression fixture, not a tech grant in any N158 game.
    world_data["research"]["terran-authority"].append("orbital_habitats")
    world_data["research_directors"]["terran-authority"]["technologies"].append("orbital_habitats")
    var world := N39.new()
    if not world.initialize(world_data):
        _fail("original world initialize rejected")
        return
    if not world.run_tick(1, 1).get("ok", false):
        _fail("canonical source tick missing")
        return
    var founded: Dictionary = world.apply_native_colony_foundation(
        1, "terran-authority", "mars", "earth-station", model, graph, true)
    if not founded.get("ok", false):
        _fail("N151 isolated source-approved site unavailable")
        return
    var docked: Dictionary = world.apply_native_colony_prepare_docks(1, graph)
    if not docked.get("ok", false) or docked.get("created", []).size() != 1:
        _fail("original N151 dock not prepared")
        return
    var original: Dictionary = world.world_snapshot()
    var bank: Dictionary = world.ledger_snapshot()
    var treasury: int = int(original["faction_treasuries"]["terran-authority"])
    var result: Dictionary = N144.active_site(original, graph,
        "terran-authority", 1, 1)
    if not result.get("ok", false) or not result.get("ready", false):
        _fail("original N144 still blocks paid real settlers: " +
            str(result.get("reason", "")))
        return
    var offer: Dictionary = N144.stage_paid_passengers(original, bank,
        result, "terran-authority", 1, 1, graph)
    if not offer.get("ok", false):
        _fail("N144 canonical funding stage unavailable: " + str(offer.get("reason", "")))
        return
    var cid: String = str(offer["contract_id"])
    var funded: Dictionary = offer["world"]
    var c: Dictionary = funded["contract_board"]["contracts"].get(cid, {})
    var amount: int = int(result["plan"]["quantity"]) * 80
    if int(offer.get("money_debited", -1)) != amount or (
            int(funded["faction_treasuries"]["terran-authority"]) != treasury - amount or
            int(funded["escrow_balances"].get("escrow:" + cid, -1)) != amount or
            str(c.get("status", "")) != "posted" or
            str(c.get("contract_type", "")) != "passenger" or
            str(c.get("mission_category", "")) != "strategy.colony.v1" or
            str(c.get("colony_site_id", "")) != str(founded.get("site_id", "")) or
            str(c.get("destination_location", "")) != "mars-colony" or
            funded["markets"].has("mars-colony") or
            funded["populations"] != original["populations"] or
            funded["ships"] != original["ships"]):
        _fail("N144 fabricated funds, passengers, ships or a market")
        return
    if Schema.validate(funded) != "":
        _fail("single World does not accept original prepaid N144 commission")
        return
    var money := Ledger.new()
    if not money.restore(offer["ledger_snapshot"]):
        _fail("N144 attempted a second/invalid Ledger")
        return
    var contracts := Board.new(money)
    if not contracts.restore(funded["contract_board"]) or (
            contracts.get_contract(cid) != c):
        _fail("N144 did not use canonical N104")
        return
    if N144.stage_paid_passengers(funded, offer["ledger_snapshot"],
            result, "terran-authority", 1, 1, graph).get("ok", false):
        _fail("N144 contract ID / prepaid ledger replay accepted")
        return
    var before_total: int = 0
    var after_total: int = 0
    for credits in bank["balances"].values():
        before_total += int(credits)
    for credits in offer["ledger_snapshot"]["balances"].values():
        after_total += int(credits)
    if before_total != after_total or funded["facilities"] != original["facilities"]:
        _fail("N144 minted physical wealth or modified source dock")
        return
    print("P2_N144_ORIGINAL_SOURCE_PREPAID_PASSENGERS_ESCROW_NO_MINT_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N144_SOURCE_CONTRACT_FAIL: " + reason)
    quit(1)
