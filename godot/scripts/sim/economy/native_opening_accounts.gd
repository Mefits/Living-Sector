extends RefCounted
## N57: source-only other-world opening balances. Frozen Rust seeder.rs
## INSERT factions.treasury, facilities.credits, populations.total_wealth.
## Never use this function when RESTORING a running world, and never
## inject a guessed account with zero balance. No financial transfers here.
const MAX_CREDITS: int = 9223372036854775807

static func source_opening_accounts(seed: Dictionary) -> Dictionary:
    if not (seed.get("factions", null) is Array) or not (seed.get("worlds", null) is Array):
        return _fail("missing_frozen_sources")
    var accounts: Dictionary = {}
    var totals: Dictionary = {"factions": 0, "facilities": 0, "populations": 0}
    var counts: Dictionary = {"factions": 0, "facilities": 0, "populations": 0}
    for source in seed["factions"]:
        if not (source is Dictionary):
            return _fail("invalid_faction")
        var faction: Dictionary = source
        if not _record(accounts, "faction:" + str(faction.get("id", "")),
                faction.get("treasury", null), totals, counts, "factions"):
            return _fail("invalid_faction_wallet")
    for value in seed["worlds"]:
        if not (value is Dictionary):
            return _fail("invalid_world")
        var world: Dictionary = value
        var system_value: Variant = world.get("system", null)
        if not (system_value is Dictionary):
            return _fail("invalid_system")
        var system_id: String = str(system_value.get("id", ""))
        if system_id.is_empty():
            return _fail("empty_system_id")
        var facilities: Variant = world.get("facilities", null)
        var populations: Variant = world.get("populations", null)
        if not (facilities is Array) or not (populations is Array):
            return _fail("missing_facility_or_population_source")
        for facility_value in facilities:
            if not (facility_value is Dictionary):
                return _fail("invalid_facility")
            var facility: Dictionary = facility_value
            if not _record(accounts, "facility:" + str(facility.get("id", "")),
                    facility.get("credits", null), totals, counts, "facilities"):
                return _fail("invalid_facility_wallet")
        for i in range(populations.size()):
            if not (populations[i] is Dictionary):
                return _fail("invalid_population")
            var population: Dictionary = populations[i]
            # Native population JSON has NO permanent ID. This is a
            # provisional Godot key, NOT Rust's SQLite primary key.
            var key: String = "population:@" + system_id + "/" + str(i)
            if not _record(accounts, key, population.get("total_wealth", null),
                    totals, counts, "populations"):
                return _fail("invalid_population_wallet")
    if counts["factions"] == 0 or counts["facilities"] == 0 or counts["populations"] == 0:
        return _fail("incomplete_opening_world")
    return {"ok": true, "accounts": accounts, "totals": totals,
        "counts": counts, "source": "frozen-rust-sim_db-seeder-open-balances"}

static func _record(accounts: Dictionary, account: String, value: Variant,
        totals: Dictionary, counts: Dictionary, domain: String) -> bool:
    if account.get_slice(":", 1).is_empty() or accounts.has(account):
        return false
    if typeof(value) != TYPE_INT or int(value) < 0:
        return false
    var total: int = int(totals[domain])
    if total > MAX_CREDITS - int(value):
        return false
    accounts[account] = int(value)
    totals[domain] = total + int(value)
    counts[domain] = int(counts[domain]) + 1
    return true

## A saved ledger may have changed actual balances, but it must preserve
## exactly the opening account identities (N57 does not support dynamic
## economy/escrow domains yet). Never reseed balances during restore.
static func same_account_ids(seed: Dictionary, balances: Dictionary) -> bool:
    var projection: Dictionary = source_opening_accounts(seed)
    if not bool(projection.get("ok", false)):
        return false
    var native_other: Dictionary = projection["accounts"]
    for id in native_other:
        if not balances.has(id):
            return false
        if typeof(balances[id]) != TYPE_INT or int(balances[id]) < 0:
            return false
    var expected: int = native_other.size()
    # Ship IDs are sourced by the N46/N52 module and checked separately.
    var ship_count: int = 0
    for id in balances:
        if str(id).begins_with("ship:"):
            ship_count += 1
        elif not native_other.has(id):
            return false
    return expected + ship_count == balances.size()

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
