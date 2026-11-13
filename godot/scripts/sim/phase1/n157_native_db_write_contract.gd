extends RefCounted
## N157 Rust sim_db/persistence.rs::DbWrite::key and stable payload gate.
## 19 keyed DbWrite kinds + EconomicFrame wrapper = 20 source variants, stable DB IDs only.
## No path, account, contract or row identity may be invented by this layer.
const KINDS: PackedStringArray = PackedStringArray([
    "constructed_facility", "colony_population", "colony_established",
    "ship", "market", "faction", "facility", "facility_orbit",
    "population", "body", "tick", "director",
    "delete_ship", "delete_facility", "contract_board",
    "site_upsert", "site_delete", "retire_ship", "market_trend"
])
const DB_ID_KINDS: PackedStringArray = PackedStringArray([
    "ship", "market", "facility", "facility_orbit", "population", "body",
    "delete_ship", "delete_facility", "colony_population", "colony_established"
])
const NUMERIC_FIELDS: PackedStringArray = PackedStringArray([
    "credits", "treasury", "total_wealth", "population_count", "payment",
    "initial_payment", "reserved", "spent"
])
const CONTRACT_TYPES: PackedStringArray = PackedStringArray([
    "delivery", "courier", "passenger", "subsidy", "supply",
    "crew_mission", "construction"
])
const CONTRACT_STATUSES: PackedStringArray = PackedStringArray([
    "posted", "accepted", "picked_up", "delivered", "paid", "expired"
])

static func validate_write(write: Variant) -> String:
    if not (write is Dictionary):
        return "not_dictionary"
    var kind: Variant = write.get("kind", null)
    if not (kind is String) or not KINDS.has(kind):
        return "unknown_kind"
    if not (write.get("data") is Dictionary):
        return "missing_data"
    var data: Dictionary = write["data"]
    if DB_ID_KINDS.has(kind):
        if not _valid_db_id(write.get("db_id", null)):
            return "invalid_db_id"
    elif kind == "faction":
        if not _nonempty(write.get("id", null)):
            return "missing_faction_id"
    elif kind == "constructed_facility":
        if not _nonempty(write.get("source_site_id", null)):
            return "missing_source_site_id"
        if not _valid_db_id(data.get("db_id", null)):
            return "missing_constructed_facility_db_id"
    elif kind == "site_upsert" or kind == "site_delete":
        if not _nonempty(write.get("agent_id", null)):
            return "invalid_site_id"
    elif kind == "retire_ship":
        if not _nonempty(write.get("agent_id", null)) or not _int_from_zero(write.get("tick", null)):
            return "invalid_retirement_identity"
    elif kind == "market_trend":
        if not _valid_db_id(write.get("market_db_id", null)) or not _int_from_zero(write.get("tick", null)):
            return "invalid_market_trend_identity"
    if kind == "tick":
        if not _int_from_zero(data.get("current_tick", null)):
            return "invalid_tick"
    elif kind == "contract_board":
        var contracts: Variant = data.get("rows", null)
        if not (contracts is Array):
            return "invalid_contract_board"
        var seen: Dictionary = {}
        for row in contracts:
            var error: String = validate_contract(row)
            if not error.is_empty():
                return error
            if seen.has(row["id"]):
                return "duplicate_contract_id"
            seen[row["id"]] = true
    elif kind == "market_trend":
        if not (data.get("entries") is Array):
            return "invalid_trend_entries"
        var seen: Dictionary = {}
        for item in data["entries"]:
            if not (item is Dictionary) or not _nonempty(item.get("commodity", null)):
                return "invalid_trend_commodity"
            if seen.has(item["commodity"]):
                return "duplicate_trend_commodity"
            seen[item["commodity"]] = true
            if not _finite_nonnegative(item.get("price", null)) or not _finite_nonnegative(item.get("supply", null)):
                return "invalid_trend_amount"
    elif kind == "retire_ship":
        if not _nonempty(data.get("reason", null)):
            return "retirement_requires_reason"
    elif kind == "constructed_facility":
        if not _nonempty(data.get("name", null)) or not _nonempty(data.get("faction_id", null)):
            return "invalid_constructed_facility"
    elif kind == "colony_population":
        if not _nonempty(data.get("location", null)) or not _nonempty(data.get("faction", null)):
            return "invalid_colony_population"
    elif kind == "colony_established":
        if not _nonempty(data.get("location", null)):
            return "invalid_colony_established"
    elif kind == "director":
        if not (data.get("state") is Dictionary):
            return "invalid_director"
    for key in NUMERIC_FIELDS:
        if data.has(key) and (typeof(data[key]) != TYPE_INT or int(data[key]) < 0):
            return "invalid_money_or_count"
    return ""

static func validate_contract(row: Variant) -> String:
    if not (row is Dictionary):
        return "invalid_contract_row"
    if not _nonempty(row.get("id", null)) or not _nonempty(row.get("requestor_id", null)):
        return "invalid_contract_identity"
    if not CONTRACT_TYPES.has(str(row.get("contract_type", ""))):
        return "unknown_contract_type"
    if not CONTRACT_STATUSES.has(str(row.get("status", ""))):
        return "unknown_contract_status"
    for field in ["commodity", "source_location", "destination_location"]:
        if not _nonempty(row.get(field, null)):
            return "invalid_contract_location_or_commodity"
    for field in ["quantity", "payment", "initial_payment",
            "min_reputation", "initial_min_reputation", "renewal_count",
            "posted_at_tick", "expires_at_tick"]:
        if not _int_from_zero(row.get(field, null)):
            return "invalid_contract_" + field
    if int(row["quantity"]) <= 0 or int(row["min_reputation"]) > 100:
        return "invalid_contract_range"
    if row.has("funding") and row["funding"] != null and not (row["funding"] is Dictionary):
        return "invalid_funding"
    if row.has("accepted_at_tick") and row["accepted_at_tick"] != null and not _int_from_zero(row["accepted_at_tick"]):
        return "invalid_contract_acceptance"
    return ""

static func dedup_key(write: Dictionary) -> String:
    var kind: String = str(write.get("kind", ""))
    match kind:
        "constructed_facility":
            return "facility_create:" + str(write.get("source_site_id", ""))
        "colony_population":
            return "colony_population:" + str(write.get("db_id", ""))
        "colony_established":
            return "colony_established:" + str(write.get("db_id", ""))
        "ship", "market", "facility", "facility_orbit", "population", "body":
            return kind + ":" + str(write.get("db_id", ""))
        "delete_ship":
            return "ship_delete:" + str(write.get("db_id", ""))
        "delete_facility":
            return "facility_delete:" + str(write.get("db_id", ""))
        "faction":
            return "faction:" + str(write.get("id", ""))
        "tick", "director", "contract_board":
            return kind + ":"
        "site_upsert":
            return "site:" + str(write.get("agent_id", ""))
        "site_delete":
            return "site_delete:" + str(write.get("agent_id", ""))
        "retire_ship":
            return "retire:" + str(write.get("agent_id", "")) + "-" + str(write.get("tick", ""))
        "market_trend":
            return "market_trend:" + str(write.get("market_db_id", "")) + ":" + str(write.get("tick", ""))
    return ""

static func flush_priority(write: Dictionary) -> int:
    match str(write.get("kind", "")):
        "constructed_facility":
            return 0
        "colony_population", "colony_established":
            return 1
        "delete_ship", "delete_facility", "site_delete":
            return 3
    return 2

static func _nonempty(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _valid_db_id(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) > 0

static func _int_from_zero(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0

static func _finite_nonnegative(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= 0.0
