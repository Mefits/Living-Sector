extends RefCounted
## N52. Admission of initial *source balances* to the ONE N11 world ledger.
## Frozen Rust sim_db/seeder.rs INSERT ships.credits, and spawner.rs
## ShipEconomy.credits reads saved DB balances verbatim.
## No separate ship treasury, account mint after start, or phantom facility funds.
const FleetBootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const MAX_CREDITS: int = 9223372036854775807

static func project_initial_ship_accounts(seed: Dictionary) -> Dictionary:
    var new_game: Dictionary = FleetBootstrap.build_new_game(seed)
    if not bool(new_game.get("ok", false)) or new_game.get("provenance", "") != FleetBootstrap.PROVENANCE:
        return _failure("not_clean_new_game")
    var credits: Dictionary = new_game["credit_sources"]
    var fleet: RefCounted = new_game["fleet"]
    if credits.is_empty() or credits.size() != fleet.ships.size():
        return _failure("incomplete_ship_funding")
    var accounts: Dictionary = {}
    var total: int = 0
    var ids: Array = credits.keys()
    ids.sort()
    for id in ids:
        var ship_id: String = str(id)
        var value: Variant = credits[id]
        if not fleet.ships.has(ship_id) or ship_id.is_empty() or typeof(value) != TYPE_INT:
            return _failure("invalid_ship_credits")
        var amount: int = int(value)
        if amount < 0 or total > MAX_CREDITS - amount:
            return _failure("ship_credits_overflow")
        var account: String = "ship:" + ship_id
        if accounts.has(account):
            return _failure("duplicate_ship_wallet")
        accounts[account] = amount
        total += amount
    return {
        "ok": true, "accounts": accounts,
        "ship_count": accounts.size(), "total": total,
        "source": "Rust sim_db::seeder - first ships credit balances"
    }

## This is only a FRESH global-ledger import, not a second ledger.
## It combines externally authoritative station/faction/household accounts
## into one N11 import. Unknown other accounts are NOT assumed to be zero.
static func admit_into_empty_world_ledger(ledger: RefCounted, seed: Dictionary,
        other_authoritative_accounts: Dictionary) -> Dictionary:
    if ledger == null or not ledger.has_method("import_accounts") or not ledger.has_method("snapshot"):
        return _failure("missing_world_ledger")
    var current: Dictionary = ledger.snapshot()
    if not (current.get("balances", null) is Dictionary) or not (current.get("receipts", null) is Dictionary):
        return _failure("unsupported_ledger_schema")
    if not (current["balances"] as Dictionary).is_empty() or not (current["receipts"] as Dictionary).is_empty():
        return _failure("world_ledger_already_initialized")
    if other_authoritative_accounts.is_empty():
        return _failure("missing_other_authoritative_accounts")
    var result: Dictionary = project_initial_ship_accounts(seed)
    if not bool(result.get("ok", false)):
        return result
    var combined: Dictionary = (result["accounts"] as Dictionary).duplicate(true)
    var total: int = int(result["total"])
    for key in other_authoritative_accounts:
        if not (key is String) or key.is_empty() or combined.has(key):
            return _failure("duplicate_or_invalid_account")
        var amount: Variant = other_authoritative_accounts[key]
        if typeof(amount) != TYPE_INT or int(amount) < 0 or total > MAX_CREDITS - int(amount):
            return _failure("invalid_or_overflowed_external_source")
        combined[key] = int(amount)
        total += int(amount)
    # Atomic at N11 import boundary. It must be invoked once per fresh world,
    # with ALL authoritative other accounts present — not independently on
    # already running facility/player/faction ledgers.
    if not ledger.import_accounts(combined):
        return _failure("world_ledger_import_rejected")
    return {
        "ok": true, "ship_count": int(result["ship_count"]),
        "ship_total": int(result["total"]), "world_total": total
    }

static func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
