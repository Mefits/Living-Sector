extends SceneTree
## N39 ship-domain copy-on-write ownership and N9 balances-only read.
## A canonical committed World must not alias an external ship proposal,
## and forbidden ship wallet mutations must still be rejected.
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var bank := Bank.new()
    if not bank.import_accounts({"a": 50, "b": 20}):
        _fail("N9 source wallet fixture rejected")
        return
    var balances: Dictionary = bank.balances_snapshot()
    if balances != {"a": 50, "b": 20}:
        _fail("balances-only view changed authoritative N9 accounts")
        return
    balances["a"] = -123
    balances.erase("b")
    if bank.balance("a") != 50 or bank.balance("b") != 20 or (
            not bank.snapshot()["receipts"].is_empty()):
        _fail("detached N9 balances accessor exposed live mutable state")
        return
    var sim = Runtime.new()
    if not sim.start_from_seed(NativeData.load_current_world()):
        _fail("original N39 production seed rejected")
        return
    var original: Dictionary = sim.production.snapshot()
    var world: Dictionary = original["world"]
    var ids: Array = world["ships"].keys()
    ids.sort()
    if ids.size() != 24:
        _fail("missing original physical fleet")
        return
    var sid: String = str(ids[0])
    var proposal: Dictionary = {"ok": true, "changed": true,
        "ships": world["ships"].duplicate(true),
        "next_token": int(world["ship_next_token"])}
    # This no-delta commit deliberately exercises full canonical validation
    # and isolation without inventing flight, money, orders or cargo.
    if not sim.production.apply_ship_phase(1, proposal):
        _fail("N39 rejected unchanged valid owned fleet proposal")
        return
    if sim.production.snapshot() != original:
        _fail("no-delta ship-domain commit changed N39 or N9")
        return
    proposal["ships"][sid]["credits"] = -4321
    if sim.production.snapshot() != original:
        _fail("live N39 ship wallet aliases mutable external proposal")
        return
    var rejected: Dictionary = {"ok": true, "changed": true,
        "ships": world["ships"].duplicate(true),
        "next_token": int(world["ship_next_token"])}
    rejected["ships"][sid]["credits"] = int(
        rejected["ships"][sid]["credits"]) + 1
    if sim.production.apply_ship_phase(1, rejected):
        _fail("N39 accepted unreceipted ship-wallet mutation")
        return
    if sim.production.snapshot() != original:
        _fail("rejected ship-wallet proposal mutated canonical N39/N9")
        return
    print("P2_N39_SHIP_DOMAIN_COPY_BOUNDARY_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_N39_SHIP_DOMAIN_COPY_BOUNDARY_FAIL: " + message)
    quit(1)
