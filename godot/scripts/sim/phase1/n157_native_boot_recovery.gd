extends RefCounted
## N157 frozen sim_db/spawner.rs::load_agents / load_contracts /
## load_market_trend_samples / load_construction_sites.
## A read-only boot plan; actual ECS Entity recreation remains Phase2.
const Transaction = preload("res://scripts/sim/phase1/n157_native_persist_transaction.gd")
const Contract = preload("res://scripts/sim/phase1/n157_native_db_write_contract.gd")
const Commodities = preload("res://scripts/sim/economy/commodity_catalog.gd")
const MARKET_TREND_KEEP: int = 200
const LOAD_ORDER: PackedStringArray = PackedStringArray([
    "bodies", "factions", "facilities", "markets", "market_trends",
    "populations", "ships", "contracts", "construction_sites",
    "gate_pairs", "seed_ship_price_knowledge"
])

static func build_read_only_boot_plan(database: Dictionary) -> Dictionary:
    if not Transaction.valid_database(database):
        return _fail("invalid_database")
    var state: Dictionary = database["simulation_state"]
    var tick_row: Variant = state.get("tick_counter", {"current_tick": 0})
    if not (tick_row is Dictionary) or typeof(tick_row.get("current_tick", null)) != TYPE_INT or int(tick_row["current_tick"]) < 0:
        return _fail("invalid_persisted_tick")
    # Rust sim_db saves a u64 world_seed. JSON can lose >2^53 precision;
    # a source loader must pass it through unchanged, never use random().
    var world_seed: Variant = state.get("world_seed", null)
    if world_seed != null and not (world_seed is Dictionary):
        return _fail("invalid_persisted_seed")
    var facility_ids: Dictionary = {}
    var facility_by_agent: Dictionary = {}
    var facilities: Array = []
    var generator = RegEx.new()
    if generator.compile("[^\\p{L}\\p{N}]") != OK:
        return _fail("slug_regex_unavailable")
    for db_id in _sorted_keys(database["facilities"]):
        var row: Dictionary = database["facilities"][db_id]
        if not _name(row.get("name", null)) or not _name(row.get("location_name", row.get("location", null))):
            return _fail("invalid_facility_identity")
        var location: String = str(row.get("location_name", row.get("location", "")))
        var slug: String = generator.sub(str(row["name"]).to_lower(), "-", true)
        while slug.begins_with("-"):
            slug = slug.substr(1)
        while slug.ends_with("-"):
            slug = slug.substr(0, slug.length() - 1)
        if slug.is_empty():
            return _fail("empty_facility_slug")
        var agent_id: String = "facility-" + location + "-" + slug
        if facility_by_agent.has(agent_id):
            return _fail("duplicate_stable_facility_identity")
        facility_ids[db_id] = agent_id
        facility_by_agent[agent_id] = db_id
        facilities.append({"db_id": db_id, "agent_id": agent_id, "row": row.duplicate(true)})
    var market_by_db: Dictionary = {}
    var markets: Array = []
    for db_id in _sorted_keys(database["markets"]):
        var row: Dictionary = database["markets"][db_id]
        var owner_id: String = str(row.get("facility_db_id", row.get("facility_id", "")))
        if not facility_ids.has(owner_id):
            return _fail("orphan_market_owner")
        market_by_db[db_id] = true
        markets.append({"db_id": db_id, "owner": facility_ids[owner_id],
            "row": row.duplicate(true)})
    var populations: Array = []
    for db_id in _sorted_keys(database["populations"]):
        var row: Dictionary = database["populations"][db_id]
        var host: String = str(row.get("facility_id", ""))
        if not host.is_empty() and not facility_ids.has(host):
            return _fail("orphan_population_home")
        populations.append({"db_id": db_id,
            "host": facility_ids.get(host, ""), "row": row.duplicate(true)})
    var ships: Array = []
    for db_id in _sorted_keys(database["ships"]):
        var row: Dictionary = database["ships"][db_id]
        var resume: Variant = row.get("resume", row.get("resume_json", {}))
        if resume is String:
            var parsed: Variant = JSON.parse_string(resume)
            if not (parsed is Dictionary):
                return _fail("malformed_ship_resume_json")
            resume = parsed
        if not (resume is Dictionary):
            return _fail("malformed_ship_resume_json")
        var dock: Variant = resume.get("docked_db_id", null)
        var docking_agent: String = ""
        if dock != null:
            docking_agent = str(facility_ids.get(str(dock), ""))
            # Rust loaders reconstruct by stable DB id; orphaned dock
            # cannot become a newly spawned, fictitious facility.
        var normalized: Dictionary = resume.duplicate(true)
        normalized["docked_at_agent"] = docking_agent
        for key in ["cargo_age", "cargo_origin", "contract_rejections"]:
            if not normalized.has(key):
                normalized[key] = {}
            if not (normalized[key] is Dictionary):
                return _fail("invalid_ship_resume_" + key)
        ships.append({"db_id": db_id, "resume": normalized,
            "row": row.duplicate(true)})
    var trends: Dictionary = {}
    for id in _sorted_keys(database["market_trend_samples"]):
        var row: Dictionary = database["market_trend_samples"][id]
        var market_id: String = str(row.get("market_db_id", ""))
        if not market_by_db.has(market_id):
            continue  # Rust skips orphan samples after market deletion.
        if not Commodities.contains(str(row.get("commodity", ""))):
            continue  # Rust skips unknown commodities.
        var tick_value: Variant = row.get("tick", null)
        if typeof(tick_value) != TYPE_INT or int(tick_value) < 0:
            return _fail("invalid_trend_tick")
        var key: String = market_id + ":" + str(tick_value)
        if not trends.has(key):
            trends[key] = {"market_db_id": market_id, "tick": int(tick_value),
                "prices": {}, "supply": {}}
        var commodity: String = str(row["commodity"])
        trends[key]["prices"][commodity] = float(row["price"])
        trends[key]["supply"][commodity] = float(row["supply"])
    var trend_by_market: Dictionary = {}
    for key in _sorted_keys(trends):
        var sample: Dictionary = trends[key]
        var mid: String = str(sample["market_db_id"])
        if not trend_by_market.has(mid):
            trend_by_market[mid] = []
        trend_by_market[mid].append(sample.duplicate(true))
    for mid in trend_by_market:
        var items: Array = trend_by_market[mid]
        items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return int(a["tick"]) < int(b["tick"]))
        if items.size() > MARKET_TREND_KEEP:
            trend_by_market[mid] = items.slice(items.size() - MARKET_TREND_KEEP)
    var board: Array = []
    var skipped_contracts: Array = []
    for id in _sorted_keys(database["contracts"]):
        var row: Dictionary = database["contracts"][id]
        # Rust skips unknown type/status/commodity; malformed funding fails.
        if (not Contract.CONTRACT_TYPES.has(str(row.get("contract_type", "")))
                or not Contract.CONTRACT_STATUSES.has(str(row.get("status", "")))
                or not Commodities.contains(str(row.get("commodity", "")))):
            skipped_contracts.append(str(id))
            continue
        var normal: Dictionary = row.duplicate(true)
        if int(normal.get("initial_payment", 0)) <= 0:
            normal["initial_payment"] = int(normal.get("payment", 0))
        normal["min_reputation"] = clampi(int(normal.get("min_reputation", 0)), 0, 100)
        normal["initial_min_reputation"] = clampi(int(normal.get("initial_min_reputation", 0)), 0, 100)
        normal["renewal_count"] = clampi(int(normal.get("renewal_count", 0)), 0, 255)
        var funding: Variant = normal.get("funding", normal.get("funding_json", null))
        if funding is String:
            funding = JSON.parse_string(funding)
            if funding == null:
                return _fail("invalid_contract_funding_json")
        if funding != null and not (funding is Dictionary):
            return _fail("invalid_contract_funding")
        normal["funding"] = funding
        board.append(normal)
    var sites: Array = []
    for id in _sorted_keys(database["construction_sites"]):
        var row: Dictionary = database["construction_sites"][id]
        if bool(row.get("completed", false)):
            continue
        if not Commodities.contains(str(row.get("commodity", ""))):
            continue
        sites.append({"agent_id": id, "row": row.duplicate(true)})
    var pairs: Dictionary = {}
    for item in facilities:
        var row: Dictionary = item["row"]
        if str(row.get("facility_type", row.get("type", ""))) != "gate":
            continue
        var paired: String = str(row.get("gate_paired_id", ""))
        if facility_by_agent.has(paired):
            var paired_db: String = str(facility_by_agent[paired])
            var matched: Dictionary = database["facilities"][paired_db]
            pairs[str(row.get("location_name", row.get("location", "")))] = str(
                matched.get("location_name", matched.get("location", "")))
    return {"ok": true, "tick": int(tick_row["current_tick"]),
        "world_seed": world_seed, "load_order": LOAD_ORDER,
        "stable_facility_ids": facility_ids,
        "bodies": _rows(database["bodies"]),
        "factions": _rows(database["factions"]),
        "facilities": facilities, "markets": markets, "market_trends": trend_by_market,
        "populations": populations, "ships": ships,
        "contracts": board, "skipped_unknown_contracts": skipped_contracts,
        "construction_sites": sites, "gate_pairs": pairs,
        "director": database["director"].duplicate(true),
        "needs_real_price_knowledge_seed": true}

static func _rows(records: Dictionary) -> Array:
    var result: Array = []
    for key in _sorted_keys(records):
        result.append({"id": key, "row": records[key].duplicate(true)})
    return result

static func _sorted_keys(records: Dictionary) -> Array:
    var keys: Array = records.keys()
    keys.sort_custom(func(a: Variant, b: Variant) -> bool:
        return str(a) < str(b))
    return keys

static func _name(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
