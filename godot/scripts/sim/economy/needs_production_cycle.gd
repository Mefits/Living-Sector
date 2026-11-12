extends RefCounted
## N7: one-location vertical slice, Rust agents/population.rs and workforce.rs.
## CODE_UNVERIFIED. Facility and market share a physical stock dictionary.
## No household self-production, teleported supplies or duplicate wallets.
const Needs = preload("res://scripts/sim/population/needs.gd")
const Production = preload("res://scripts/sim/economy/paid_production.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")

var _ledger: RefCounted = Ledger.new()
var _production: RefCounted = Production.new()
var _stock: Dictionary = {}
var _limits: Dictionary = {}
var _pop: Dictionary = {}
var _facility: Dictionary = {}
var _market: Dictionary = {}
var _last_tick: int = -1

func initialize(accounts: Dictionary, facility: Dictionary, population: Dictionary, market: Dictionary, stock: Dictionary, limits: Dictionary = {}) -> bool:
    if not _facility.is_empty() or not _ledger.import_accounts(accounts):
        return false
    for key in ["id", "recipe", "facility_type", "employer", "household", "seller", "location"]:
        if not (facility.get(key) is String) or str(facility[key]).is_empty():
            return false
    if typeof(facility.get("workers")) != TYPE_INT or int(facility["workers"]) <= 0:
        return false
    if str(population.get("facility_location", "")) != str(facility["location"]) or str(market.get("facility_location", "")) != str(facility["location"]):
        return false
    if not (market.get("prices") is Dictionary) or Inventory.validate(stock, limits) != "":
        return false
    for account in ["employer", "household", "seller"]:
        if _ledger.balance(str(facility[account])) < 0:
            return false
    if str(facility["household"]) == str(facility["seller"]) or str(facility["employer"]) == str(facility["household"]):
        return false
    _facility = facility.duplicate(true)
    _pop = population.duplicate(true)
    _market = market.duplicate(true)
    _market["supply"] = stock.duplicate(true)
    _market["seller_credits"] = _ledger.balance(str(facility["seller"]))
    _pop["total_wealth"] = _ledger.balance(str(facility["household"]))
    _stock = stock.duplicate(true)
    _limits = limits.duplicate(true)
    return true

func run_tick(tick: int) -> Dictionary:
    if _facility.is_empty() or tick < 0 or tick <= _last_tick:
        return {"ok": false, "reason": "invalid_or_replayed_tick"}
    var result := {"ok": true, "tick": tick, "production": {}, "purchases": [], "reason": ""}
    # Production first: wages are credited to the SAME household account
    # later used for purchases. Both operations use one balanced ledger.
    var shift: Dictionary = _production.run_shift(str(_facility["id"]), str(_facility["recipe"]),
        str(_facility["facility_type"]), tick, int(_facility["workers"]),
        int(_pop.get("population_count", 0)), _stock, _limits, _ledger,
        str(_facility["employer"]), str(_facility["household"]))
    result["production"] = shift
    if tick % Needs.CONSUMPTION_INTERVAL_BASE == 0:
        var pop_candidate: Dictionary = _pop.duplicate(true)
        var market_candidate: Dictionary = _market.duplicate(true)
        pop_candidate["total_wealth"] = _ledger.balance(str(_facility["household"]))
        market_candidate["seller_credits"] = _ledger.balance(str(_facility["seller"]))
        market_candidate["supply"] = _stock.duplicate(true)
        var events: Array = Needs.consume_cycle(pop_candidate, market_candidate, tick)
        var payment: int = _ledger.balance(str(_facility["household"])) - int(pop_candidate["total_wealth"])
        if Inventory.validate(market_candidate["supply"], _limits) != "":
            return {"ok": false, "reason": "invalid_purchase_stock"}
        if payment > 0:
            var receipt: Dictionary = _ledger.transfer("population/%s/%d" % [str(_pop.get("id", "")), tick],
                str(_facility["household"]), str(_facility["seller"]), payment, tick, "population_purchase")
            if not receipt.get("ok", false):
                return {"ok": false, "reason": str(receipt.get("reason", "purchase_payment_failed"))}
        # Purchase effects commit only after payment. Never keep duplicate
        # household wealth or seller credits as independent monetary truth.
        pop_candidate["total_wealth"] = _ledger.balance(str(_facility["household"]))
        market_candidate["seller_credits"] = _ledger.balance(str(_facility["seller"]))
        _pop = pop_candidate
        _market = market_candidate
        _stock = market_candidate["supply"].duplicate(true)
        result["purchases"] = events
    _market["supply"] = _stock.duplicate(true)
    _last_tick = tick
    return result

func snapshot() -> Dictionary:
    return {"version": 1, "tick": _last_tick, "facility": _facility.duplicate(true),
        "population": _pop.duplicate(true), "market": _market.duplicate(true),
        "stock": _stock.duplicate(true), "limits": _limits.duplicate(true),
        "ledger": _ledger.snapshot(), "production": _production.snapshot()}

func restore(data: Dictionary) -> bool:
    if data.get("version") != 1 or typeof(data.get("tick")) != TYPE_INT or int(data["tick"]) < -1:
        return false
    for key in ["facility", "population", "market", "stock", "limits", "ledger", "production"]:
        if not (data.get(key) is Dictionary):
            return false
    if Inventory.validate(data["stock"], data["limits"]) != "":
        return false
    var candidate_ledger = Ledger.new()
    var candidate_production = Production.new()
    if not candidate_ledger.restore(data["ledger"]) or not candidate_production.restore(data["production"]):
        return false
    var f: Dictionary = data["facility"]
    if str(f.get("location", "")) != str(data["population"].get("facility_location", "")) or str(f.get("location", "")) != str(data["market"].get("facility_location", "")):
        return false
    if candidate_ledger.balance(str(f.get("household", ""))) != int(data["population"].get("total_wealth", -1)):
        return false
    if candidate_ledger.balance(str(f.get("seller", ""))) != int(data["market"].get("seller_credits", -1)):
        return false
    if data["market"].get("supply") != data["stock"]:
        return false
    _ledger = candidate_ledger
    _production = candidate_production
    _facility = f.duplicate(true)
    _pop = data["population"].duplicate(true)
    _market = data["market"].duplicate(true)
    _stock = data["stock"].duplicate(true)
    _limits = data["limits"].duplicate(true)
    _last_tick = int(data["tick"])
    return true

func balance(account: String) -> int:
    return _ledger.balance(account)

func stock() -> Dictionary:
    return _stock.duplicate(true)

func population() -> Dictionary:
    return _pop.duplicate(true)
