extends SceneTree
## Local N9 escrow wallet + N104 ContractBoard checkpoint smoke.
## No second ledger or funds. Run with Godot 4.7.2 --headless --script.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")

func _initialize() -> void:
    var ledger = Ledger.new()
    if not ledger.import_accounts({"facility/buyer": 100, "ship:carrier": 0}):
        _fail("seed accounts rejected")
        return
    var initial_total: int = ledger.total()
    var escrow: String = "escrow:n135:need:dst:Water"
    if not ledger.register_empty_account(escrow):
        _fail("zero escrow registration failed")
        return
    if ledger.register_empty_account(escrow) or ledger.register_empty_account(""):
        _fail("duplicate or empty escrow account admitted")
        return
    if ledger.balance(escrow) != 0 or ledger.total() != initial_total:
        _fail("registration minted credits")
        return
    var board = Board.new(ledger)
    var posted: Dictionary = board.post("n135:need:dst:Water", "delivery",
        "facility/buyer", escrow, "Water", 5, "src", "dst", 20, 5, 50, "facility")
    if not posted.get("ok", false):
        _fail("funded N104 contract rejected: " + str(posted))
        return
    if ledger.balance("facility/buyer") != 80 or ledger.balance(escrow) != 20 or ledger.total() != initial_total:
        _fail("escrow funding lost or minted credits")
        return
    if board.post("n135:need:dst:Water", "delivery",
        "facility/buyer", escrow, "Water", 5, "src", "dst", 20, 5, 50, "facility").get("ok", false):
        _fail("duplicate contract posted")
        return
    var saved_ledger: Dictionary = ledger.snapshot()
    var saved_board: Dictionary = board.snapshot()
    var restored = Ledger.new()
    if not restored.restore(saved_ledger):
        _fail("N9 checkpoint restore rejected")
        return
    var restored_board = Board.new(restored)
    if not restored_board.restore(saved_board):
        _fail("N104 checkpoint restore rejected")
        return
    if restored.total() != initial_total or restored.balance(escrow) != 20:
        _fail("escrow balance not persistent")
        return
    if restored_board.get_contract("n135:need:dst:Water").get("status") != "posted":
        _fail("contract not persistent")
        return
    if not restored_board.expire_posted("n135:need:dst:Water", 50).get("ok", false):
        _fail("expiry rejected")
        return
    var refund: Dictionary = restored_board.refund_closed("n135:need:dst:Water", 50)
    if not refund.get("ok", false) or restored.balance("facility/buyer") != 100 or restored.balance(escrow) != 0:
        _fail("escrow refund incorrect: " + str(refund))
        return
    if restored_board.refund_closed("n135:need:dst:Water", 50).get("refunded", -1) != 0:
        _fail("refund replay changed money")
        return
    if restored.total() != initial_total:
        _fail("credits changed after contract roundtrip")
        return
    print("P2_LEDGER_ESCROW_ACCOUNT_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_LEDGER_ESCROW_ACCOUNT_FAIL: " + reason)
    quit(1)
