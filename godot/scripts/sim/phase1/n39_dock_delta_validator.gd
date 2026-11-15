extends RefCounted
## N39 II-B — side-effect-free N21 ship/dock/facility write-set oracle.
## A *shadow* diagnostic only. It cannot authorize payment, docking, or
## replace source Schema.validate, original refusal reasons, or N9.restore.
## The caller passes detached read-only values; this method never mutates.
static func validate_delta(before: Dictionary, after: Dictionary,
        proposed_bank: Dictionary) -> String:
    if not (before.get("ships") is Dictionary) or not (
            before.get("facilities") is Dictionary) or not (
            before.get("dock_receipts") is Dictionary) or not (
            after.get("ships") is Dictionary) or not (
            after.get("facilities") is Dictionary) or not (
            after.get("dock_receipts") is Dictionary):
        return "n21_invalid_domains"
    var ships: Dictionary = after["ships"]
    var facilities: Dictionary = after["facilities"]
    var receipts: Dictionary = after["dock_receipts"]
    var occupied: Dictionary = {}
    # A legal waiting FIFO is NOT itself a dock occupancy. Only docked_at
    # occupies one source slot; queued ships can outnumber the free slots.
    for sid in ships:
        if not (ships[sid] is Dictionary):
            return "invalid_ship"
        var ship: Dictionary = ships[sid]
        var dock: String = str(ship.get("docked_at", ""))
        if dock.is_empty():
            continue
        if not facilities.has(dock) or not (facilities[dock] is Dictionary):
            return "invalid_ship_docked_at"
        if str(ship.get("location", "")) != str(facilities[dock].get("location", "")):
            return "invalid_ship_dock_location"
        var cap: Variant = facilities[dock].get("docking_capacity", null)
        if typeof(cap) != TYPE_INT:
            return "missing_dock_capacity"
        occupied[dock] = int(occupied.get(dock, 0)) + 1
        if int(occupied[dock]) > int(cap):
            return "dock_capacity_exceeded"
    var waiters: Dictionary = {}
    for fid in facilities:
        if not (facilities[fid] is Dictionary):
            return "invalid_facility"
        var queue: Variant = facilities[fid].get("dock_queue", [])
        if not (queue is Array):
            return "invalid_native_n21_fifo_shape"
        for sid in queue:
            if not (sid is String) or str(sid).is_empty() or waiters.has(sid):
                return ("duplicate_native_n21_fifo_waiter"
                    if waiters.has(sid) and waiters[sid] != fid
                    else "invalid_native_n21_fifo_identity")
            waiters[sid] = fid
    if not (proposed_bank.get("balances") is Dictionary) or not (
            proposed_bank.get("receipts") is Dictionary):
        return "n21_invalid_bank_shape"
    var n9_receipts: Dictionary = proposed_bank["receipts"]
    # Old N9/World receipts are checked separately by the existing owner
    # using _ledger.retains_receipts() and the original exact reason.
    for op in receipts:
        if before["dock_receipts"].has(op):
            continue
        if not (receipts[op] is Dictionary):
            return "invalid_fleet_receipt_identity"
        var receipt: Dictionary = receipts[op]
        if not (op is String) or str(op).is_empty() or str(
                receipt.get("operation_id", "")) != str(op):
            return "invalid_fleet_receipt_identity"
        if typeof(receipt.get("tick", null)) != TYPE_INT or int(
                receipt["tick"]) < 0:
            return "invalid_fleet_receipt_tick"
        var action: String = str(receipt.get("action", ""))
        if action not in ["dock", "undock"]:
            return "invalid_native_n21_action"
        var sid: String = str(receipt.get("ship_id", ""))
        var fid: String = str(receipt.get("facility_id", ""))
        if sid.is_empty() or fid.is_empty():
            return "invalid_native_n21_actor"
        if typeof(receipt.get("fee", null)) != TYPE_INT or int(
                receipt["fee"]) < 0:
            return "invalid_native_n21_fee"
        var fee: int = int(receipt["fee"])
        if action == "undock" and fee != 0:
            return "invalid_native_n21_release_fee"
        var financial: String = str(receipt.get("financial_receipt", ""))
        if (fee > 0 and financial != str(op)) or (
                fee == 0 and not financial.is_empty()):
            return "invalid_native_n21_fee_provenance"
        if fee == 0:
            continue
        # Exact immutable N9 paid provenance; a synthetic receipt or
        # duplicated fee cannot satisfy a canonical two-legged transfer.
        if not n9_receipts.has(op) or not (n9_receipts[op] is Dictionary):
            return "missing_native_n21_n9_payment"
        var paid: Dictionary = n9_receipts[op]
        if str(paid.get("id", "")) != str(op) or str(
                paid.get("kind", "")) != "native_n21_dock" or (
                paid.get("tick", null) != receipt["tick"]):
            return "invalid_native_n21_n9_provenance"
        if paid.get("legs", null) != [
                {"account": "ship:" + sid, "delta": -fee},
                {"account": "facility/" + fid, "delta": fee}]:
            return "invalid_native_n21_n9_legs"
    return ""
