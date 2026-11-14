extends RefCounted
## N152/N104 P2 close/refund candidate. The canonical authority is N39:
## this file stages a DETACHED copy of its existing N104 ContractBoard and
## N9 Ledger. It never installs a second live board, wallet or tick runner.
## Rust: economy/contracts.rs::ContractBoard / contract_funding::refund_closed.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const ContractBoard = preload("res://scripts/sim/economy/contract_board.gd")
const NativeAging = preload("res://scripts/sim/native_contract_aging.gd")

static func stage(world: Dictionary, bank: Dictionary, tick: int) -> Dictionary:
    if tick < 0 or not (world.get("contract_board", null) is Dictionary):
        return _bad("missing_single_n104_board")
    if not (world.get("escrow_balances", null) is Dictionary):
        return _bad("missing_canonical_escrow_accounts")
    var original: Dictionary = world["contract_board"]
    if not (original.get("contracts", null) is Dictionary):
        return _bad("invalid_n104_contracts")
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return _bad("invalid_live_n9_ledger")
    var original_total: int = ledger.total()
    var board := ContractBoard.new(ledger)
    if not board.restore(original):
        return _bad("invalid_live_n104_board")
    # Frozen N145 order: age reputation, escalate the currently offered
    # reward, then renew eligible POSTED types (delivery/construction 3x,
    # subsidy 1x). Do NOT auto-expire an already accepted shipment.
    var aging: Dictionary = NativeAging.advance_posted(original["contracts"],
        tick, NativeAging.DEFAULT_LIFESPAN)
    if not aging.get("ok", false):
        return _bad("source_n145_aging_" + str(aging.get("error", "rejected")))
    var aged_board: Dictionary = original.duplicate(true)
    aged_board["contracts"] = aging["contracts"]
    if not board.restore(aged_board):
        return _bad("source_n145_board_reconstruction_failed")
    var expired: Array = []
    var renewed: Array = aging.get("renewed", []).duplicate(true)
    for entry in aging.get("expired", []):
        expired.append(str(entry.get("id", "")))
    var aged: bool = aged_board["contracts"] != original["contracts"]
    var ids: Array = original["contracts"].keys()
    ids.sort()
    var refunds: Array = []
    var blocked: Array = []
    for id in ids:
        var status: String = str(board.get_contract(str(id)).get("status", ""))
        if status not in ["paid", "expired"]:
            continue
        var current: Dictionary = board.get_contract(str(id))
        var amount: int = int(current.get("reserved", 0))
        if amount <= 0:
            continue
        var payer: String = str(current.get("requestor_id", ""))
        var escrow: String = str(current.get("escrow_account", ""))
        if not bank.get("balances", {}).has(payer):
            # Original N104 does not redirect a missing beneficiary's
            # money to faction treasury or silently discard escrow.
            blocked.append({"contract_id": str(id),
                "reason": "missing_original_payer"})
            continue
        var refund: Dictionary = board.refund_closed(str(id), tick)
        if not refund.get("ok", false):
            var reason: String = str(refund.get("reason", "rejected"))
            if reason in ["integer_overflow", "invalid_account_or_delta", "insufficient_funds"]:
                # Retain the funded closed row so an administrator can
                # repair the beneficiary without losing held credits.
                blocked.append({"contract_id": str(id), "reason": reason})
                continue
            return _bad("n104_canonical_refund_" + reason)
        if int(refund.get("refunded", -1)) != amount:
            return _bad("n104_partial_or_fabricated_refund")
        refunds.append({"contract_id": str(id), "payer": payer,
            "escrow": escrow, "amount": amount,
            "receipt_id": "contract:" + str(id) + ":refund"})
    if ledger.total() != original_total:
        return _bad("n9_money_conservation_failed")
    return {"ok": true, "tick": tick,
        "board_snapshot": board.snapshot(),
        "ledger_snapshot": ledger.snapshot(),
        "expired": expired, "renewed": renewed, "aged": aged,
        "refunded": refunds, "blocked": blocked,
        "changed": aged or not refunds.is_empty()}

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
