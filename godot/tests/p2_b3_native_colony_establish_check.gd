extends SceneTree
## Miro B3 source regression, NOT RUN until coordinated full Godot F5.
## NO fake 600 Metals, 150 paid workers, new population or ship in
## gameplay. Genuine positive path awaits B2 physical travel integration.
const Data = preload("res://scripts/native_data.gd")
const Seed = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const Est = preload("res://scripts/sim/phase2/unified_n151_colony_establish.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")

func _initialize() -> void:
    var raw: Dictionary = Data.load_current_world()
    if raw.has("error"):
        _fail("frozen Galaxy seed unavailable")
        return
    var built: Dictionary = Seed.from_seed(raw)
    if not built.get("ok", false):
        _fail("N39 frozen physical source projection unavailable")
        return
    var world: Dictionary = built["world"].duplicate(true)
    var money := Ledger.new()
    if not money.import_accounts(Schema.accounts(world)):
        _fail("cannot open one source N9 ledger")
        return
    var snapshot: Dictionary = money.snapshot()
    if Est.stage(world, snapshot, "imaginary-site", 1, 1).get("ok", false):
        _fail("B3 minted a colony without an actual N151 site")
        return
    var market: Dictionary = Est.native_market(
        "mars-colony", "real-temporary-dock", 2)
    if market.is_empty() or market.get("supply", {"x": 1}) != {} or (
            market.get("demand", {}) != {"food": 5.0, "water": 3.0} or
            market.get("seed_demand", {}) != {"food": 5.0, "water": 3.0} or
            market.get("owner", "") != "real-temporary-dock" or
            int(market.get("orders", {}).get("order_expiry_ticks", -1)) != 100 or
            market.get("prices", {}).size() != Catalog.ORDER.size()):
        _fail("B3 Rust MarketPricing/MarketFlow/MarketOrders mismatch")
        return
    for slug in Catalog.ORDER:
        if float(market["prices"].get(str(slug), -1.0)) != Catalog.base_price(str(slug)):
            _fail("B3 not frozen Rust Commodity::ALL base prices")
            return
    if Est.native_market("", "dock", 1) != {} or (
            Est.native_market("colony", "", 1) != {} or
            Est.native_market("colony", "dock", 0) != {}):
        _fail("B3 allowed phantom N151 original market")
        return
    if world.get("markets", {}).has("mars-colony") or money.snapshot() != snapshot:
        _fail("B3 pure Market proposal mutated original N39 World or N9")
        return
    print("P2_B3_SOURCE_NEGATIVE_GUARDS_MARKET_SHAPE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_B3_SOURCE_CHECK_FAIL: " + reason)
    quit(1)
