extends SceneTree
## Regression: autonomous N104 cargo must dock at the warehouse owner,
## never at a different station chosen by free-slot ranking.
const Docking = preload("res://scripts/sim/ships/docking_registry.gd")

func _initialize() -> void:
    var docks = Docking.new()
    if not docks.register_facility("wrong_station", "sol", 20, "station"):
        _fail("fixture wrong station")
        return
    if not docks.register_facility("contract_warehouse", "sol", 1, "station"):
        _fail("fixture contract warehouse")
        return
    if not docks.register_ship("hauler", "sol"):
        _fail("fixture ship")
        return
    var chosen: Dictionary = docks.request_dock("hauler", "contract:1:dock", "station", "contract_warehouse")
    if not chosen.get("ok", false) or str(chosen.get("facility_id", "")) != "contract_warehouse":
        _fail("N21 ignored explicit N104 warehouse owner")
        return
    if docks.request_dock("hauler", "contract:1:duplicate", "station", "wrong_station").get("ok", false):
        _fail("N21 docked same ship twice")
        return
    if not docks.undock("hauler", "contract:1:undock").get("ok", false):
        _fail("N21 cannot release exact dock")
        return
    if not docks.register_ship("other", "sol"):
        _fail("fixture other ship")
        return
    if not docks.request_dock("other", "contract:2:dock", "station", "contract_warehouse").get("ok", false):
        _fail("N21 capacity fixture")
        return
    var denied: Dictionary = docks.request_dock("hauler", "contract:3:dock", "station", "contract_warehouse")
    if denied.get("ok", false) or str(denied.get("reason", "")) != "no_available_dock":
        _fail("N21 fell back to unrelated station instead of refusing")
        return
    if not docks.snapshot().has("occupants"):
        _fail("N21 snapshot unavailable")
        return
    var restored = Docking.new()
    if not restored.restore(docks.snapshot()) or str(restored.ships["other"]["docked_at"]) != "contract_warehouse":
        _fail("N21 exact reservation lost on save/restore")
        return
    print("P2_N21_EXACT_MARKET_DOCK_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N21_EXACT_MARKET_DOCK_FAIL: " + reason)
    quit(1)
