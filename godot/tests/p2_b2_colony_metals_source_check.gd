extends SceneTree
## Miro B2 source regression (NOT RUN pending full Rust→Godot migration).
## The fixture authorizes an existing site only: it does not teleport a
## ship or invent a delivered 200-Metals cargo hold to claim runtime PASS.
const NativeData = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const WorldRegistry = preload("res://scripts/sim/world_registry.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Materials = preload("res://scripts/sim/phase2/unified_n144_colony_metals.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("source Galaxy data unavailable")
        return
    var original := WorldModel.new()
    var locations := WorldRegistry.new()
    if not original.load_seed(seed) or not locations.load_seed(seed):
        _fail("original N142 chart missing")
        return
    var graph: RefCounted = locations.graph()
    var projection: Dictionary = Adapter.from_seed(seed)
    if not projection.get("ok", false):
        _fail("canonical source physical world missing")
        return
    # Detached tech fixture ONLY: source says orbital_habitats must have
    # been researched before an original Director can found Mars.
    var physical: Dictionary = projection["world"].duplicate(true)
    physical["research"]["terran-authority"].append("orbital_habitats")
    physical["research_directors"]["terran-authority"]["technologies"].append(
        "orbital_habitats")
    var n39 := N39.new()
    if not n39.initialize(physical) or not n39.run_tick(1, 1).get("ok", false):
        _fail("canonical N39 source clock not available")
        return
    var founded: Dictionary = n39.apply_native_colony_foundation(
        1, "terran-authority", "mars", "earth-station",
        original, graph, true)
    if not founded.get("ok", false):
        _fail("isolated source-authorized construction site missing")
        return
    var prepared: Dictionary = n39.apply_native_colony_prepare_docks(1, graph)
    if not prepared.get("ok", false) or prepared.get("created", []).size() != 1:
        _fail("original N151 physical construction_dock missing")
        return
    var pristine: Dictionary = n39.world_snapshot()
    var bank: Dictionary = n39.ledger_snapshot()
    var id: String = str(founded["site_id"])
    if Materials.source_quote(pristine, id).get("ok", false):
        _fail("empty founding household illegally ordered construction Metals")
        return
    # Detached test-only after-arrival condition: this fixture starts
    # after a prior actual N104 passenger flight; NOT a free resident
    # grant in production N39 and NOT proof that the physical flight ran.
    var before: Dictionary = pristine.duplicate(true)
    var pop: String = str(prepared["created"][0]["population_id"])
    before["populations"][pop]["count"] = 50
    var quote: Dictionary = Materials.source_quote(before, id)
    if not quote.get("ok", false) or int(quote.get("quantity", -1)) != 200 or (
            int(quote.get("payment", -1)) != 10000):
        _fail("Rust 200-Metals / 10000 quote mismatch: " + str(quote.get("reason", "")))
        return
    var posted: Dictionary = Materials.post(before, bank, id, 1, 1, graph)
    if not posted.get("ok", false):
        _fail("N144 paid construction original N104 post refused: " + str(posted.get("reason", "")))
        return
    var candidate: Dictionary = posted["world"]
    var cid: String = str(posted["contract_id"])
    var c: Dictionary = candidate["contract_board"]["contracts"].get(cid, {})
    var expected: int = 10000
    var faction: String = "terran-authority"
    if str(c.get("contract_type", "")) != "construction" or (
            str(c.get("commodity", "")) != "metals" or
            int(c.get("quantity", 0)) != 200 or
            str(c.get("mission_category", "")) != "strategy.colony.v1" or
            str(c.get("colony_site_id", "")) != id or
            str(candidate.get("construction_contracts", {}).get(cid, "")) != id or
            int(candidate["escrow_balances"].get("escrow:" + cid, -1)) != expected or
            int(candidate["faction_treasuries"][faction]) != int(before["faction_treasuries"][faction]) - expected):
        _fail("N144 real 200 Metals contract funding diverged")
        return
    if candidate["markets"] != before["markets"] or (
            candidate["ships"] != before["ships"] or
            candidate["facilities"] != before["facilities"] or
            candidate["populations"] != before["populations"] or
            candidate["construction_sites"] != before["construction_sites"]):
        _fail("N144 invented market, ship, metal stock or site progress")
        return
    var ledger := Ledger.new()
    if not ledger.restore(posted["ledger_snapshot"]):
        _fail("original N9 paid commission not restorable")
        return
    var old_total: int = 0
    for balance in bank.get("balances", {}).values():
        old_total += int(balance)
    if ledger.total() != old_total or not posted["ledger_snapshot"]["receipts"].has(
            "contract:" + cid + ":post"):
        _fail("N144 escrow minted credits or lacks prepaid receipt")
        return
    if not Schema.validate(candidate).is_empty():
        _fail("N39 contract+site schema rejected legitimate preflight")
        return
    if Materials.post(candidate, posted["ledger_snapshot"], id,
            1, 1, graph).get("ok", false):
        _fail("N144 paid Metals replay created another claim")
        return
    var unloaded: Dictionary = Materials.deliver(candidate,
        posted["ledger_snapshot"], cid, "nonexistent_ship", 2)
    if unloaded.get("ok", false):
        _fail("unbacked N15 construction unload was accepted")
        return
    print("P2_B2_N144_PREPAID_MARKETLESS_METALS_NO_GHOST_STOCK_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_B2_COLONY_METALS_FAIL: " + reason)
    quit(1)
