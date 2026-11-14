extends RefCounted
## V3 N38 pre-promotion audit of the ONE N39 physical World and N9 ledger.
## Frozen source: phase1/n39_native_world_schema.gd::accounts,
## phase1/n39_native_world_production.gd::snapshot/restore,
## economy/credit_ledger.gd::snapshot. Pure read-only preflight.
## No invented wallets, money conservation rule, new contracts or world state.
const MAX_I64: int = 9223372036854775807
const MAX_PHASE: int = 19 # tick_runner.gd::NATIVE_PHASE_ORDER has 20 source phases.

static func _bad(code: String) -> Dictionary:
    return {"ok": false, "reason": code}

static func _money(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0

static func _put(expected: Dictionary, account: String,
        amount: Variant) -> bool:
    if account.is_empty() or expected.has(account) or not _money(amount):
        return false
    expected[account] = int(amount)
    return true

## A checkpoint may be valid P1-only and lack the production frame. Never
## backfill it from a seed or silently manufacture the original 24 ships.
static func validate(snapshot: Dictionary) -> Dictionary:
    if not snapshot.has("native_production"):
        return {"ok": true, "scope": "legacy_p1_without_native_frame"}
    var source: Variant = snapshot["native_production"]
    if not (source is Dictionary):
        return _bad("missing_native_frame")
    var native: Dictionary = source
    var tick: Variant = snapshot.get("tick", null)
    if typeof(tick) != TYPE_INT or int(tick) < 0 or (
            typeof(native.get("tick", null)) != TYPE_INT) or (
            int(native["tick"]) != int(tick)):
        return _bad("native_world_tick_mismatch")
    if typeof(native.get("version", null)) != TYPE_INT or int(native["version"]) != 1:
        return _bad("unsupported_native_frame_version")
    if not (native.get("world") is Dictionary) or not (
            native.get("ledger") is Dictionary):
        return _bad("missing_native_world_or_ledger")
    var world: Dictionary = native["world"]
    var bank: Dictionary = native["ledger"]
    if typeof(bank.get("version", null)) != TYPE_INT or int(bank["version"]) != 1 or (
            not (bank.get("balances") is Dictionary)) or (
            not (bank.get("receipts") is Dictionary)):
        return _bad("invalid_native_n9_ledger")
    var expected: Dictionary = {}
    for field in ["facilities", "populations", "markets"]:
        if not (world.get(field) is Dictionary):
            return _bad("missing_native_" + field)
    var origins: Array = [
        ["facilities", "facility/", "credits"],
        ["populations", "population/", "wealth"],
        ["ships", "ship:", "credits"],
        ["faction_treasuries", "faction/", ""],
        ["escrow_balances", "", ""],
        ["passenger_manifests", "passengers/", "wealth"]]
    for group in origins:
        var field: String = str(group[0])
        var prefix: String = str(group[1])
        var amount_field: String = str(group[2])
        if not world.has(field):
            if field in ["facilities", "populations"]:
                return _bad("missing_native_" + field)
            continue
        if not (world[field] is Dictionary):
            return _bad("invalid_native_accounts_" + field)
        var ids: Array = world[field].keys()
        ids.sort()
        for id in ids:
            if not (id is String) or str(id).is_empty():
                return _bad("invalid_native_account_identity_" + field)
            var raw: Variant = world[field][id]
            var amount: Variant = raw
            if not amount_field.is_empty():
                if not (raw is Dictionary) or not raw.has(amount_field):
                    return _bad("missing_native_account_amount_" + field)
                amount = raw[amount_field]
            if not _put(expected, prefix + str(id), amount):
                return _bad("invalid_or_duplicate_native_account_" + field)
    var balances: Dictionary = bank["balances"]
    if balances.size() != expected.size():
        return _bad("n9_world_account_cardinality_diverged")
    for account in expected:
        if not balances.has(account) or not _money(balances[account]) or (
                int(balances[account]) != int(expected[account])):
            return _bad("n9_world_account_diverged:" + str(account))
    # Immovable paid receipts are history, not accounts to regenerate.
    # One-legged N149 wages and N152 administrative destruction are valid
    # original sinks. Do NOT require every receipt's legs to sum to zero.
    var receipts: Dictionary = bank["receipts"]
    var ids: Array = receipts.keys()
    ids.sort()
    for operation_id in ids:
        if not (operation_id is String) or str(operation_id).is_empty() or (
                not (receipts[operation_id] is Dictionary)):
            return _bad("invalid_n9_receipt_identity")
        var receipt: Dictionary = receipts[operation_id]
        if receipt.get("id", null) != operation_id:
            return _bad("n9_receipt_id_mismatch")
        if typeof(receipt.get("tick", null)) != TYPE_INT or (
                int(receipt["tick"]) < 0) or int(receipt["tick"]) > int(tick):
            return _bad("n9_receipt_from_future:" + str(operation_id))
        if not (receipt.get("kind") is String) or str(receipt["kind"]).is_empty() or (
                not (receipt.get("legs") is Array)):
            return _bad("invalid_n9_receipt_shape:" + str(operation_id))
        var legs: Array = receipt["legs"]
        if legs.is_empty():
            return _bad("empty_n9_receipt_legs:" + str(operation_id))
        for leg in legs:
            if not (leg is Dictionary) or not (leg.get("account") is String) or (
                    str(leg["account"]).is_empty()) or typeof(leg.get("delta", null)) != TYPE_INT:
                return _bad("invalid_n9_receipt_leg:" + str(operation_id))
            # Retired/decommissioned accounts may be absent now. Historical
            # receipt legs must remain intact and NEVER resurrect a wallet.
    # N38 event queue owns timed notifications only. Reject an already
    # expired pending event before promotion; never reschedule it here.
    var raw_events: Variant = snapshot.get("events", null)
    if raw_events != null:
        if not (raw_events is Dictionary) or not (
                raw_events.get("pending") is Array):
            return _bad("invalid_native_event_queue")
        for event in raw_events["pending"]:
            if not (event is Dictionary) or (
                    typeof(event.get("due_tick", null)) != TYPE_INT) or (
                    int(event["due_tick"]) <= int(tick)) or (
                    typeof(event.get("phase", null)) != TYPE_INT) or (
                    int(event["phase"]) < 0) or int(event["phase"]) > MAX_PHASE:
                return _bad("stale_or_invalid_native_event")
    return {"ok": true, "scope": "canonical_n39_n9_receipts_and_n38_clocks",
        "accounts_checked": expected.size(), "receipts_checked": receipts.size()}
