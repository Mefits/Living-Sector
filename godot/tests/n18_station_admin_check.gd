extends SceneTree
## N18 CODE_UNVERIFIED. Run: godot --headless --path godot --script res://tests/n18_station_admin_check.gd
const Admin = preload("res://scripts/sim/strategy/station_administrator.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var ledger: RefCounted = Ledger.new()
    assert(ledger.import_accounts({"market": 100, "household": 0}))
    var admin: RefCounted = Admin.new()
    var station: Dictionary = {"faction_id": "civ", "location": "port",
        "population_count": 10, "occupied_workers": 0, "market_owner": "market",
        "stock": {"ice": 80.0, "water": 0.0, "food": 0.0},
        "limits": {}, "shortages": {}, "head_priority": "food",
        "facilities": [
            {"id": "a-farm", "type": "farm", "crew": 6, "owner": "market", "household": "household"},
            {"id": "z-refinery", "type": "refinery", "crew": 6, "owner": "market", "household": "household"}
        ]}
    var before: Dictionary = station["stock"].duplicate(true)
    var shadow: Dictionary = admin.plan(5, station, ledger, false)
    assert(shadow["ok"] and shadow["head_priority"] == "water")
    assert(shadow["assigned_workers"] == 6)
    assert(shadow["modules"][0]["assigned_workers"] == 0)
    assert(shadow["modules"][1]["assigned_workers"] == 6)
    assert(station["stock"] == before and ledger.total() == 100)
    assert(not admin.dispatch(shadow, station, ledger)["ok"])
    # Same-tick shadow plan cannot be silently promoted to execution.
    var live: RefCounted = Admin.new()
    var planned: Dictionary = live.plan(5, station, ledger)
    var first: Dictionary = live.dispatch(planned, station, ledger)
    assert(first["ok"] and first["results"].size() == 1)
    assert(first["results"][0]["ok"])
    assert(float(station["stock"].get("water", 0.0)) > 0.0)
    assert(ledger.balance("market") == 94 and ledger.balance("household") == 6)
    assert(ledger.total() == 100)
    var replay: Dictionary = live.dispatch(planned, station, ledger)
    assert(not replay["results"][0]["ok"])
    assert(ledger.total() == 100 and ledger.balance("market") == 94)
    var saved: Dictionary = live.snapshot()
    var restored: RefCounted = Admin.new()
    assert(restored.restore(saved))
    assert(not restored.dispatch(planned, station, ledger)["results"][0]["ok"])
    # On the next work cadence, real water enables farm, head food wins.
    var next: Dictionary = restored.plan(10, station, ledger)
    assert(next["head_priority"] == "food")
    assert(next["modules"][0]["assigned_workers"] == 6)
    assert(next["modules"][1]["assigned_workers"] == 0)
    var result: Dictionary = restored.dispatch(next, station, ledger)
    assert(result["results"][0]["ok"])
    assert(float(station["stock"]["food"]) > 0.0)
    assert(ledger.total() == 100 and ledger.balance("market") == 88)
    # Cash shortage is a read-only decision, not a negative wallet.
    var poor: RefCounted = Ledger.new()
    assert(poor.import_accounts({"market": 2, "household": 0}))
    var denied: Dictionary = Admin.new().plan(15, station, poor)
    assert(denied["assigned_workers"] == 0)
    assert(denied["modules"][0]["reason"] == "insufficient_existing_budget")
    assert(poor.balance("market") == 2)
    # Locality: population belongs to station, not to an adjacent market.
    station["population_count"] = 0
    var no_workers: Dictionary = Admin.new().plan(20, station, ledger)
    assert(no_workers["assigned_workers"] == 0)
    assert(no_workers["modules"][0]["reason"] == "insufficient_station_workers")
    print("N18 station administrator: PASS")
    quit(0)
