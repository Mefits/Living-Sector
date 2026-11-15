extends SceneTree
## N9 trusted fork: original receipts and money remain immutable across
## rejected or committed staged transactions. No new monetary authority.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var original := Ledger.new()
    if not original.import_accounts({
            "facility/alpha": 500, "facility/beta": 50,
            "population/h": 40}):
        _fail("source N9 import rejected")
        return
    var paid: Dictionary = original.transfer("n9:old:1",
        "facility/alpha", "facility/beta", 30, 1, "source_payment")
    if not paid.get("ok", false):
        _fail("original paid receipt unavailable")
        return
    var pristine: Dictionary = original.snapshot()
    if original.receipt_count() != 1 or not original.retains_receipts(
            pristine["receipts"]):
        _fail("original receipt provenance mismatch")
        return
    var staged: RefCounted = original.fork()
    if staged == null or staged == original or staged.snapshot() != pristine:
        _fail("N9 fork is not an exact independent ledger")
        return
    var duplicate: Dictionary = staged.transfer("n9:old:1",
        "facility/alpha", "facility/beta", 1, 2, "source_payment")
    if duplicate.get("ok", true) or original.snapshot() != pristine:
        _fail("fork accepted duplicate immutable receipt")
        return
    var blocked: Dictionary = staged.transfer("n9:unfunded",
        "population/h", "facility/beta", 400, 2, "source_payment")
    if blocked.get("ok", true) or original.snapshot() != pristine or (
            staged.snapshot() != pristine):
        _fail("rejected fork transfer leaked partial mutation")
        return
    var next: Dictionary = staged.transfer("n9:new:2",
        "facility/beta", "population/h", 7, 2, "source_payment")
    if not next.get("ok", false) or staged.receipt_count() != 2 or (
            staged.total() != original.total()):
        _fail("new fork settlement not conservative")
        return
    if original.snapshot() != pristine or original.has_receipt("n9:new:2"):
        _fail("fork settlement mutated source N9")
        return
    if not original.retains_receipts(staged.snapshot()["receipts"]):
        _fail("fork lost or edited old immutable N9 history")
        return
    var edited: Dictionary = pristine["receipts"].duplicate(true)
    edited["n9:old:1"]["legs"][0]["delta"] = -999
    if original.retains_receipts(edited):
        _fail("old altered N9 receipt was accepted")
        return
    if original.retains_receipts({}):
        _fail("deleted old N9 receipt was accepted")
        return
    var detached: Dictionary = staged.snapshot()
    detached["balances"]["facility/beta"] = 999999
    detached["receipts"]["n9:old:1"]["legs"][0]["delta"] = -1
    if original.snapshot() != pristine or staged.balance(
            "facility/beta") != 73 or (
            staged.snapshot()["receipts"]["n9:old:1"] != pristine[
            "receipts"]["n9:old:1"]):
        _fail("detached snapshot alias changed owned ledger")
        return
    print("P2_N9_OWNED_FORK_HISTORY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N9_OWNED_FORK_HISTORY_FAIL: " + reason)
    quit(1)
