extends SceneTree
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")

func _initialize() -> void:
    var errors: Array[String] = []
    var station := {"ore": 12.0, "fuel": 2.5}
    var market := {"ore": 3.0, "fuel": 1.0}
    if not Inventory.transfer(station, market, {"ore": 4.0, "fuel": 0.5}, {}, {"ore": 7.0}):
        errors.append("valid multi-commodity transfer")
    if station["ore"] != 8.0 or station["fuel"] != 2.0 or market["ore"] != 7.0 or market["fuel"] != 1.5:
        errors.append("transfer conservation")
    var before_station := station.duplicate(true)
    var before_market := market.duplicate(true)
    if Inventory.transfer(station, market, {"ore": 1.0}, {}, {"ore": 7.0}):
        errors.append("destination cap ignored")
    if Inventory.transfer(station, market, {"ore": 1.0, "fuel": 99.0}):
        errors.append("partial transfer allowed")
    if Inventory.transfer(station, station, {"ore": 1.0}):
        errors.append("self transfer")
    if station != before_station or market != before_market:
        errors.append("failed transfer mutated stock")
    if Inventory.transfer(station, market, {"unobtainium": 1.0}):
        errors.append("unknown commodity")
    if Inventory.transfer(station, market, {"ore": -1.0}):
        errors.append("negative amount")
    if Inventory.transfer(station, market, {"ore": INF}):
        errors.append("nonfinite amount")
    var hold := {"ore": 2.0}
    if not Inventory.transfer_to_ship(station, hold, {"ore": 3.0}, 5):
        errors.append("ship loading")
    if hold["ore"] != 5.0 or station["ore"] != 5.0:
        errors.append("ship inventory conservation")
    var before_hold := hold.duplicate(true)
    if Inventory.transfer_to_ship(station, hold, {"ore": 1.0}, 5):
        errors.append("ship capacity")
    if Inventory.transfer_to_ship(station, hold, {"fuel": 0.5}, 8):
        errors.append("fractional ship cargo")
    if hold != before_hold:
        errors.append("failed ship load mutated hold")
    if Inventory.canonical({"water": 2.0, "ore": 1.0}) != Inventory.canonical({"ore": 1.0, "water": 2.0}):
        errors.append("noncanonical snapshot")
    if errors.is_empty():
        print("N9 PASS: conserved transfers, atomic failures, caps, integer ship hold, canonical state")
        quit(0)
    for error in errors:
        push_error("N9 FAIL: " + error)
    quit(1)
