extends RefCounted
## V3 N38 pre-promotion audit of the ONE N39 physical World and N9 ledger.
## Frozen source: phase1/n39_native_world_schema.gd::accounts,
## phase1/n39_native_world_production.gd::snapshot/restore,
## economy/credit_ledger.gd::snapshot. Pure read-only preflight.
## No invented wallets, money conservation rule, new contracts or world state.
const NativePhases = preload("res://scripts/sim/tick_runner.gd")
const OriginalPolicyCheckpoint = preload("res://scripts/sim/phase2/unified_n109_n110_policy_checkpoint.gd")

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
                    int(event["phase"]) < 0) or int(event["phase"]) >= NativePhases.NATIVE_PHASE_ORDER.size():
                return _bad("stale_or_invalid_native_event")
    return {"ok": true, "scope": "canonical_n39_n9_receipts_and_n38_clocks",
        "accounts_checked": expected.size(), "receipts_checked": receipts.size()}

## N38 reads serialized JSON *before* N158 source restore normalizes
## known integer fields. A restored Godot JSON number can be a float;
## preserve exactness while validating the same canonical N9/N39 model.
## This is a read-only staging view; never update the source checkpoint.
const MAX_EXACT_JSON_INTEGER: float = 9007199254740991.0

static func _exact_integer_in_place(row: Dictionary, key: Variant) -> bool:
    if not row.has(key):
        return false
    var raw: Variant = row[key]
    if typeof(raw) == TYPE_INT:
        return true
    if typeof(raw) != TYPE_FLOAT:
        return false
    var number: float = float(raw)
    if not is_finite(number) or absf(number) > MAX_EXACT_JSON_INTEGER or (
            number != floorf(number)):
        return false
    row[key] = int(number)
    return true

## Called ONLY by N38 backup rotation against a SHA-valid on-disk payload.
## Full restore still belongs to the actual Runner and frozen seed.
static func validate_serialized_candidate(saved: Dictionary) -> Dictionary:
    if not saved.has("native_production"):
        return validate(saved)
    var staged: Dictionary = saved.duplicate(true)
    if not _exact_integer_in_place(staged, "tick"):
        return _bad("serialized_native_clock_not_exact")
    if not (staged["native_production"] is Dictionary):
        return _bad("serialized_native_frame_not_object")
    var native: Dictionary = staged["native_production"]
    for field in ["version", "tick"]:
        if not _exact_integer_in_place(native, field):
            return _bad("serialized_native_" + field + "_not_exact")
    if not (native.get("world") is Dictionary) or not (
            native.get("ledger") is Dictionary):
        return _bad("serialized_world_or_ledger_not_object")
    var world: Dictionary = native["world"]
    var ledger: Dictionary = native["ledger"]
    # Trust no digest-valid checkpoint as a backup without checking the
    # original N109/N110 budget counters and charter authority. Share
    # exactly the SAME pure policy validator used by N39.restore.
    var policy: Dictionary = OriginalPolicyCheckpoint.normalize(world)
    if not policy.get("ok", false):
        return _bad("serialized_original_policy_rejected:" + str(
            policy.get("reason", "invalid")))
    native["world"] = policy["world"]
    world = native["world"]
    if not _exact_integer_in_place(ledger, "version"):
        return _bad("serialized_ledger_version_not_exact")
    for group in ["facilities", "populations", "ships", "passenger_manifests"]:
        if not world.has(group):
            continue
        if not (world[group] is Dictionary):
            return _bad("serialized_account_group_invalid:" + group)
        var money_field: String = "wealth" if group in [
            "populations", "passenger_manifests"] else "credits"
        for id in world[group]:
            if not (world[group][id] is Dictionary):
                return _bad("serialized_account_actor_invalid:" + str(id))
            if not _exact_integer_in_place(world[group][id], money_field):
                return _bad("serialized_actor_money_not_exact:" + str(id))
    for group in ["faction_treasuries", "escrow_balances"]:
        if not world.has(group):
            continue
        if not (world[group] is Dictionary):
            return _bad("serialized_wallets_invalid:" + group)
        for account in world[group]:
            if not _exact_integer_in_place(world[group], account):
                return _bad("serialized_wallet_money_not_exact:" + str(account))
    for group in ["balances", "receipts"]:
        if not (ledger.get(group) is Dictionary):
            return _bad("serialized_ledger_" + group + "_not_object")
    for account in ledger["balances"]:
        if not _exact_integer_in_place(ledger["balances"], account):
            return _bad("serialized_n9_money_not_exact:" + str(account))
    for operation in ledger["receipts"]:
        var record: Variant = ledger["receipts"][operation]
        if not (record is Dictionary):
            return _bad("serialized_receipt_invalid:" + str(operation))
        if not _exact_integer_in_place(record, "tick"):
            return _bad("serialized_receipt_tick_not_exact:" + str(operation))
        var legs: Variant = record.get("legs", null)
        if not (legs is Array):
            return _bad("serialized_receipt_legs_invalid:" + str(operation))
        for leg in legs:
            if not (leg is Dictionary) or not _exact_integer_in_place(
                    leg, "delta"):
                return _bad("serialized_receipt_delta_not_exact:" + str(operation))
    if staged.has("events"):
        if not (staged["events"] is Dictionary) or not (
                staged["events"].get("pending") is Array):
            return _bad("serialized_event_queue_invalid")
        for event in staged["events"]["pending"]:
            if not (event is Dictionary):
                return _bad("serialized_pending_event_invalid")
            for field in ["due_tick", "phase"]:
                if not _exact_integer_in_place(event, field):
                    return _bad("serialized_event_" + field + "_not_exact")
    return validate(staged)
