extends RefCounted
## N157 transactional projection for frozen sim_db/persistence.rs::flush.
## Immutable candidate state: never mutates a live ECS or a SQLite database.
## Phase2 must commit candidate through existing SaveState/FileAccess once.
const Contract = preload("res://scripts/sim/phase1/n157_native_db_write_contract.gd")
const TABLES: PackedStringArray = PackedStringArray([
    "ships", "facilities", "markets", "factions", "populations",
    "bodies", "construction_sites", "contracts", "market_trend_samples",
    "retirements", "simulation_state"
])

static func empty_database() -> Dictionary:
    var result: Dictionary = {}
    for key in TABLES:
        result[key] = {}
    result["director"] = {}
    return result

static func valid_database(database: Variant) -> bool:
    if not (database is Dictionary):
        return false
    for key in TABLES:
        if not (database.get(key) is Dictionary):
            return false
    return database.get("director") is Dictionary

## Source SQL uses ONE transaction for all writes in an admitted economic
## frame or in its deduplicated sweep. Failure must leave base untouched.
static func transact(database: Dictionary, writes: Array,
        inject_failure: bool = false) -> Dictionary:
    if not valid_database(database):
        return {"ok": false, "reason": "invalid_database"}
    var ordered: Array = writes.duplicate(true)
    for write in ordered:
        var error: String = Contract.validate_write(write)
        if not error.is_empty():
            return {"ok": false, "reason": error}
    # Rust sorts by priority only; within an equal priority HashMap is
    # arbitrary. Stable kind/id ordering here avoids non-deterministic output.
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var pa: int = Contract.flush_priority(a)
        var pb: int = Contract.flush_priority(b)
        if pa != pb:
            return pa < pb
        return Contract.dedup_key(a) < Contract.dedup_key(b))
    var staged: Dictionary = database.duplicate(true)
    for write in ordered:
        var error: String = _apply(staged, write)
        if not error.is_empty():
            return {"ok": false, "reason": error}
    if inject_failure:
        return {"ok": false, "reason": "injected_transaction_failure"}
    return {"ok": true, "state": staged, "writes": ordered.size()}

static func _apply(db: Dictionary, write: Dictionary) -> String:
    var kind: String = str(write["kind"])
    var data: Dictionary = write["data"]
    var id: String = str(write.get("db_id", ""))
    match kind:
        "constructed_facility":
            var new_id: String = str(data["db_id"])
            if db["facilities"].has(new_id):
                return "duplicate_constructed_facility"
            var row: Dictionary = data.duplicate(true)
            row["construction_site_id"] = str(write["source_site_id"])
            db["facilities"][new_id] = row
        "colony_population":
            if db["populations"].has(id):
                return "duplicate_colony_population"
            var row: Dictionary = data.duplicate(true)
            row["db_id"] = int(write["db_id"])
            row["population_count"] = 0
            row["total_wealth"] = 0
            row["facility_id"] = int(write["db_id"])
            db["populations"][id] = row
        "colony_established":
            if not db["facilities"].has(id) or db["markets"].has(id):
                return "invalid_colony_establishment"
            if str(db["facilities"][id].get("type", "")) != "construction_dock":
                return "colony_requires_construction_dock"
            db["facilities"][id]["type"] = "station"
            db["facilities"][id]["services"] = ["market"]
            db["markets"][id] = {
                "db_id": int(write["db_id"]), "facility_db_id": int(write["db_id"]),
                "location": str(data["location"]), "supply": {},
                "prices": {}, "demand": {}, "shortage_ticks": {}
            }
        "ship", "market", "faction", "facility", "facility_orbit",
        "population", "body":
            var target: String = _table_for(kind)
            var key: String = str(write["id"]) if kind == "faction" else id
            if db[target].has(key):
                var existing: Dictionary = db[target][key].duplicate(true)
                existing.merge(data, true)
                db[target][key] = existing
            # Rust UPDATE WHERE id on absent rows affects zero rows (no resurrection).
        "delete_ship":
            db["ships"].erase(id)
        "delete_facility":
            db["facilities"].erase(id)
        "site_upsert":
            db["construction_sites"][str(write["agent_id"])] = data.duplicate(true)
        "site_delete":
            db["construction_sites"].erase(str(write["agent_id"]))
        "retire_ship":
            # Append-only retirements, dedup within sweep by agent+tick.
            var key: String = str(write["agent_id"]) + "-" + str(write["tick"])
            db["retirements"][key] = data.duplicate(true)
        "contract_board":
            # DELETE FROM contracts; INSERT all included board rows IN SAME TX.
            var board: Dictionary = {}
            for row in data["rows"]:
                board[str(row["id"])] = row.duplicate(true)
            db["contracts"] = board
        "market_trend":
            var market_id: String = str(write["market_db_id"])
            var tick: String = str(write["tick"])
            for entry in data["entries"]:
                var key: String = market_id + ":" + tick + ":" + str(entry["commodity"])
                db["market_trend_samples"][key] = {
                    "market_db_id": int(write["market_db_id"]),
                    "tick": int(write["tick"]),
                    "commodity": str(entry["commodity"]),
                    "price": float(entry["price"]), "supply": float(entry["supply"])
                }
        "tick":
            db["simulation_state"]["tick_counter"] = {
                "current_tick": int(data["current_tick"])
            }
        "director":
            db["director"] = data["state"].duplicate(true)
        _:
            return "unsupported_write_kind"
    return ""

static func _table_for(kind: String) -> String:
    match kind:
        "ship":
            return "ships"
        "market":
            return "markets"
        "faction":
            return "factions"
        "facility", "facility_orbit":
            return "facilities"
        "population":
            return "populations"
        "body":
            return "bodies"
    return ""
