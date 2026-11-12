extends SceneTree
## Run: godot --headless --path godot --script res://tests/n17_construction_check.gd
const Construction = preload("res://scripts/sim/construction/construction_cycle.gd")

func _initialize() -> void:
    var model = Construction.new()
    assert(model.create_site("site-food", "civ", "port", "earth", "metals", "refinery"))
    assert(not model.create_site("duplicate", "civ", "port", "mars", "metals", "refinery"))
    var ship = {"id": "builder", "faction": "civ", "location": "port", "in_transit": false,
        "docked": true, "engineer": true, "active_site": "site-food", "cargo": {"metals": 600}}
    var sponsor = {"faction": "civ", "credits": 150}
    var family = {"id": "workers", "faction": "civ", "location": "port", "population": 10, "credits": 0}
    assert(model.work("site-food", 5, ship, sponsor, [family], {}) == "awaiting_materials")
    assert(model.deliver("site-food", "delivery-1", ship, 600) == "ok")
    assert(ship["cargo"]["metals"] == 0)
    assert(model.deliver("site-food", "delivery-1", ship, 600) == "duplicate_receipt")
    assert(model.materialize("site-food") == "requirements_incomplete")
    var occupied: Dictionary = {}
    assert(model.work("site-food", 5, ship, sponsor, [family], occupied) == "ok")
    assert(model.sites["site-food"]["labor_completed"] == 6)
    assert(sponsor["credits"] == 144 and family["credits"] == 6)
    assert(model.work("site-food", 5, ship, sponsor, [family], occupied) == "already_worked_this_tick")
    assert(sponsor["credits"] == 144)
    var checkpoint = model.snapshot()
    var loaded = Construction.new()
    assert(loaded.restore(checkpoint))
    assert(loaded.deliver("site-food", "delivery-1", ship, 600) == "duplicate_receipt")
    for tick in range(6, 30):
        occupied.clear()
        assert(loaded.work("site-food", tick, ship, sponsor, [family], occupied) == "ok")
    assert(loaded.sites["site-food"]["labor_completed"] == 150)
    assert(sponsor["credits"] == 0 and family["credits"] == 150)
    assert(loaded.materialize("site-food") == "ok")
    assert(loaded.facilities.size() == 1)
    assert(loaded.materialize("site-food") == "completed_site")
    var restored = Construction.new()
    assert(restored.restore(loaded.snapshot()))
    assert(restored.facilities.size() == 1)
    var bad = restored.snapshot()
    bad["sites"]["site-food"]["labor_completed"] = 151
    assert(not Construction.new().restore(bad))
    print("N17 construction: PASS")
    quit(0)
