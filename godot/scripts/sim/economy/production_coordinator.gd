extends RefCounted
## N8 integration boundary: deterministic, explicitly supplied local shifts.
## CODE_UNVERIFIED. Source: frozen Rust engine.rs facilities phase, workforce.rs.
## No hidden population, inventory, funds or cross-location transfers.
const Production = preload("res://scripts/sim/economy/paid_production.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")

var _ledger: RefCounted = Ledger.new()
var _production: RefCounted = Production.new()
var _facilities: Dictionary = {}
var _last_tick: int = -1

func initialize(accounts: Dictionary, facilities: Dictionary) -> bool:
    if not _facilities.is_empty() or _last_tick != -1:
        return false
    var candidate = Ledger.new()
    if not candidate.import_accounts(accounts):
        return false
    if not _valid_facilities(facilities):
        return false
    _ledger = candidate
    _facilities = facilities.duplicate(true)
    return true

func run_tick(tick: int) -> Dictionary:
    if tick < 0 or tick <= _last_tick or _facilities.is_empty():
        return {"ok": false, "reason": "invalid_or_replayed_tick"}
    # A stable facility order is essential for shared accounts and replay.
    var ids: Array = _facilities.keys()
    ids.sort()
    var receipts: Array = []
    var failures: Dictionary = {}
    # Per-location labor budget prevents independently scheduled facilities
    # from hiring the same worker twice in one simulation tick.
    var labor_used: Dictionary = {}
    for id in ids:
        var f: Dictionary = _facilities[id]
        var location: String = str(f["location"])
        var population: int = int(f["population"])
        var capacity: int = int(population * 3 / 5)
        var workers: int = int(f["workers"])
        var used: int = int(labor_used.get(location, 0))
        if workers > capacity - used:
            failures[id] = "shared_labor_exhausted"
            continue
        var stock: Dictionary = f["stock"]
        var result: Dictionary = _production.run_shift(str(id), str(f["recipe"]),
                str(f["facility_type"]), tick, workers, population, stock,
                f["limits"], _ledger, str(f["employer"]), str(f["household"]))
        if result.get("ok", false):
            labor_used[location] = used + workers
            receipts.append(result.duplicate(true))
        else:
            failures[id] = str(result.get("reason", "unknown"))
    _last_tick = tick
    return {"ok": true, "tick": tick, "receipts": receipts, "failures": failures}

func balance(account: String) -> int:
    return _ledger.balance(account)

func stock_of(facility_id: String) -> Dictionary:
    if not _facilities.has(facility_id):
        return {}
    return _facilities[facility_id]["stock"].duplicate(true)

func snapshot() -> Dictionary:
    return {"version": 1, "tick": _last_tick,
        "facilities": _facilities.duplicate(true),
        "ledger": _ledger.snapshot(), "production": _production.snapshot()}

func restore(data: Dictionary) -> bool:
    if data.get("version") != 1 or typeof(data.get("tick")) != TYPE_INT or int(data["tick"]) < -1:
        return false
    if not (data.get("facilities") is Dictionary) or not _valid_facilities(data["facilities"]):
        return false
    if not (data.get("ledger") is Dictionary) or not (data.get("production") is Dictionary):
        return false
    var candidate_ledger = Ledger.new()
    var candidate_production = Production.new()
    if not candidate_ledger.restore(data["ledger"]) or not candidate_production.restore(data["production"]):
        return false
    for id in data["facilities"]:
        var f: Dictionary = data["facilities"][id]
        if candidate_ledger.balance(str(f["employer"])) < 0 or candidate_ledger.balance(str(f["household"])) < 0:
            return false
    # Commit only after every part has passed validation.
    _facilities = data["facilities"].duplicate(true)
    _ledger = candidate_ledger
    _production = candidate_production
    _last_tick = int(data["tick"])
    return true

func _valid_facilities(items: Dictionary) -> bool:
    if items.is_empty():
        return false
    for id in items:
        if not (id is String) or id.is_empty() or not (items[id] is Dictionary):
            return false
        var f: Dictionary = items[id]
        for key in ["location", "recipe", "facility_type", "employer", "household"]:
            if not (f.get(key) is String) or str(f[key]).is_empty():
                return false
        if typeof(f.get("workers")) != TYPE_INT or typeof(f.get("population")) != TYPE_INT:
            return false
        if f["workers"] <= 0 or f["population"] < 0:
            return false
        if not (f.get("stock") is Dictionary) or not (f.get("limits") is Dictionary):
            return false
        if Inventory.validate(f["stock"], f["limits"]) != "":
            return false
    return true
