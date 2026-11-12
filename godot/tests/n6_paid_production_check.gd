extends SceneTree
const Production = preload("res://scripts/sim/economy/paid_production.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var ledger = Ledger.new()
    assert(ledger.import_accounts({"factory": 12, "household": 0}))
    var production = Production.new()
    var stock: Dictionary = {"ore": 20.0, "fuel": 2.0, "metals": 0.0}
    var initial: Dictionary = stock.duplicate(true)
    var no_labor = production.run_shift("refinery-1", "smelt_metals", "refinery",
        5, 4, 5, stock, {}, ledger, "factory", "household")
    assert(not no_labor["ok"] and stock == initial and ledger.balance("factory") == 12)
    var no_money = production.run_shift("refinery-1", "smelt_metals", "refinery",
        5, 3, 5, stock, {}, ledger, "factory", "household", 1.0, 1)
    assert(no_money["ok"] and is_equal_approx(stock["metals"], 8.0))
    assert(ledger.balance("factory") == 9 and ledger.balance("household") == 3)
    assert(stock["ore"] == 10.0 and stock["fuel"] == 1.0)
    var previous: Dictionary = stock.duplicate(true)
    var duplicate = production.run_shift("refinery-1", "smelt_metals", "refinery",
        5, 3, 5, stock, {}, ledger, "factory", "household")
    assert(not duplicate["ok"] and stock == previous and ledger.balance("factory") == 9)
    var too_small = production.run_shift("refinery-1", "smelt_metals", "refinery",
        6, 3, 5, stock, {"metals": 8.0}, ledger, "factory", "household")
    assert(not too_small["ok"] and stock == previous and ledger.balance("household") == 3)
    var restored = Production.new()
    assert(restored.restore(production.snapshot()))
    var replay = restored.run_shift("refinery-1", "smelt_metals", "refinery",
        5, 3, 5, stock, {}, ledger, "factory", "household")
    assert(not replay["ok"])
    # Genuine insufficient payroll, with ample raw material.
    var poor = Ledger.new()
    assert(poor.import_accounts({"factory": 1, "household": 0}))
    var poor_stock = initial.duplicate(true)
    var blocked = Production.new().run_shift("refinery-2", "smelt_metals", "refinery",
        6, 3, 5, poor_stock, {}, poor, "factory", "household")
    assert(not blocked["ok"] and poor_stock == initial and poor.balance("factory") == 1)
    print("N6 paid production smoke OK")
    quit(0)
