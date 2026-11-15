extends SceneTree
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Shift = preload("res://scripts/sim/strategy/paid_research_shift.gd")

func _initialize() -> void:
    var money = Ledger.new()
    assert(money.import_accounts({"faction":20000,"station":100,"workers":0}))
    var executor = Shift.new(money)
    var stock: Dictionary = {"electronics":3.0}
    var mandate: Dictionary = {"mode":"delegated","budget":300,"floor":10000,"spent":0}
    var result: Dictionary = executor.paid_shift("shift-1","f1",1,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,false,true)
    assert(result.get("ok",false))
    assert(result["receipt"]["technology"] == "industrial_methods")
    assert(result["receipt"]["cost"] == 30)
    assert(stock["electronics"] == 2.0)
    assert(money.balance("faction") == 19970)
    assert(money.balance("station") == 120)
    assert(money.balance("workers") == 10)
    assert(money.total() == 20100)
    assert(mandate["spent"] == 30)
    assert(not executor.paid_shift("shift-1","f1",1,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,false,true).get("ok",false))
    assert(not executor.paid_shift("shift-2","f1",1,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,false,true).get("ok",false))
    assert(stock["electronics"] == 2.0)
    assert(not executor.paid_shift("shift-3","f1",2,"automation",[],mandate,
        19.2,stock,"faction","station","workers",9,false,true).get("ok",false))
    assert(not executor.paid_shift("shift-4","f1",2,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,false,false).get("ok",false))
    assert(not executor.paid_shift("shift-5","f1",2,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,true,true).get("ok",false))
    var saved: Dictionary = executor.snapshot()
    var copy = Shift.new(money)
    assert(not copy.restore(saved,false))
    assert(copy.restore(saved,true))
    assert(not copy.paid_shift("shift-1","f1",2,"automation",[],mandate,
        19.2,stock,"faction","station","workers",10,false,true).get("ok",false))
    var low: Dictionary = {"mode":"delegated","budget":100,"floor":19960,"spent":90}
    assert(not copy.paid_shift("shift-6","f1",2,"automation",[],low,
        19.2,stock,"faction","station","workers",10,false,true).get("ok",false))
    assert(money.total() == 20100)
    assert(stock["electronics"] == 2.0)
    print("N45 paid research shift smoke PASS")
    quit(0)
