extends RefCounted
## N152/N104 P2 close/refund candidate. The canonical authority is N39:
## this file stages a DETACHED copy of its existing N104 ContractBoard and
## N9 Ledger. It never installs a second live board, wallet or tick runner.
## Rust: economy/contracts.rs::ContractBoard / contract_funding::refund_closed.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const ContractBoard = preload("res://scripts/sim/economy/contract_board.gd")

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
    var ids: Array = original["contracts"].keys()
    ids.sort()
    var expired: Array = []
    var refunds: Array = []
    var blocked: Array = []
    for id in ids:
        var before: Dictionary = original["contracts"][id]
        var status: String = str(before.get("status", ""))
        if status == "posted":
            if typeof(before.get("expires_at_tick", null)) != TYPE_INT:
                return _bad("missing_source_expiry_tick")
            if tick >= int(before["expires_at_tick"]):
                # Only POSTED contracts expire automatically. Accepted and
                # physically picked-up freight remain real obligations.
                var close: Dictionary = board.expire_posted(str(id), tick)
                if not close.get("ok", false):
                    return _bad("n152_posted_expiry_" + str(close.get("reason", "rejected")))
                expired.append(str(id))
                status = "expired"
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
        "expired": expired, "refunded": refunds, "blocked": blocked,
        "changed": not expired.is_empty() or not refunds.is_empty()}

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
