extends SceneTree
## Small projection/isolation regression; does not run simulation ticks.
const Production = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _init() -> void:
    var previous: String = OS.get_environment("LS_RUNTIME_FULL_WORLD_READS")
    OS.set_environment("LS_RUNTIME_FULL_WORLD_READS", "0")
    var production = Production.new()
    # Synthetic read-only fixture: exercise projection without admitting a World.
    var source: Dictionary = {
        "ships": {"s1": {"memory": {"route": ["a"]}}, "s2": {"id": "s2"}},
        "ship_next_token": 7,
        "markets": {"m1": {"id": "m1", "owner": "f1",
            "supply": {"ore": 3}, "prices": {"ore": 4},
            "consumption_window": {}, "history": {"samples": [1, 2]}}},
        "facilities": {"f1": {"location": "m1", "credits": 10,
            "faction": "p1", "type": "station", "docking_capacity": 2,
            "abandoned": false}},
        "populations": {},
        "contract_board": {"contracts": {"c1": {"id": "c1"}, "c2": {"id": "c2"}}},
        "construction_sites": {"site1": {"id": "site1"}},
        "construction_receipts": {
            "n151_colony_dock:site1": {"id": "proof"},
            "unrelated": {"id": "old"}},
        "cargo_receipts": {"old": {"id": "old"}},
        "faction_treasuries": {"p1": 20}}
    production.set("_world", source)
    production.set("_ready", true)
    var motion: Dictionary = production.native_runtime_read_snapshot("ship_motion")
    assert(motion.size() == 2 and motion.ships == source.ships)
    motion.ships.s1.memory.route.append("b")
    assert(source.ships.s1.memory.route == ["a"])
    var population: Dictionary = production.native_runtime_read_snapshot("population")
    assert(not population.markets.m1.has("history"))
    assert(population.facilities.f1 == {"credits": 10})
    population.markets.m1.supply.ore = 999
    assert(source.markets.m1.supply.ore == 3)
    source.facilities.f1.credits = 25
    var demand: Dictionary = production.native_runtime_read_snapshot("station_demand")
    assert(demand.facilities.f1.credits == 25)
    var dock: Dictionary = production.native_dock_read_snapshot("s1", "c1")
    assert(dock.ships.size() == 1 and dock.contract_board.contracts.size() == 1)
    assert(dock.construction_receipts == {"n151_colony_dock:site1": {"id": "proof"}})
    dock.construction_receipts["n151_colony_dock:site1"].id = "changed"
    assert(source.construction_receipts["n151_colony_dock:site1"].id == "proof")
    assert(production.native_runtime_read_snapshot("unknown") == source)
    OS.set_environment("LS_RUNTIME_FULL_WORLD_READS", "1")
    assert(production.native_runtime_read_snapshot("ship_motion") == source)
    assert(production.native_dock_read_snapshot("s1", "c1") == source)
    OS.set_environment("LS_RUNTIME_FULL_WORLD_READS", previous)
    print("runtime read projection isolation: PASS")
    quit()
