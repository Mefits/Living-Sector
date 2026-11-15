extends SceneTree
## Real N104 funded contract fixture and immutable source N153 oracle.
## Exact candidate/order/BT/rejection-count parity; mutated scenarios are
## test-only copies, never written into the canonical N39 World.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
const Selector = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Oracle = preload("res://tests/p2_parallel_b_n153_source_oracle.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")

var checks: int = 0

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("real frozen seed unavailable")
        return
    var sim = Runtime.new()
    if not sim.start_from_seed(seed):
        _fail("N158 boot: " + sim.boot_error())
        return
    var saved: Dictionary = sim.checkpoint()
    var world: Dictionary = saved["native_production"]["world"]
    if world["ships"].size() != 24:
        _fail("frozen original fleet is not 24")
        return
    world["markets"]["alpha-station"]["prices"]["food"] = 60.0
    world["markets"]["earth-station"]["prices"]["food"] = 4.0
    var stock: float = float(world["markets"]["alpha-station"]["supply"]["food"])
    world["markets"]["alpha-station"]["consumption_window"]["food"] = [
        {"tick": 0, "qty": stock + 5.0}]
    var roster = Roster.new()
    var resolver = Resolver.new()
    if not roster.load_seed(seed) or not resolver.load_seed(seed):
        _fail("real N4 graph or N80 resolver unavailable")
        return
    var pos_result: Dictionary = resolver.positions_from_world(
        sim.world, sim.calendar.native_time_units, sim.calendar.origin_known)
    if not pos_result.get("ok", false):
        _fail("real moving-world position adapter unavailable")
        return
    var positions: Dictionary = pos_result["positions"]
    var factions: Dictionary = {}
    for f in seed["factions"]:
        factions[str(f["id"])] = f
    var graph = roster.registry.graph()
    var scale: float = sim.clock.tick_scale()
    if not _parity(world, graph, positions, resolver, 0, scale, factions, "no_offer"):
        return
    if not sim.restore_checkpoint(saved, seed):
        _fail("real controlled price fixture refused by N39")
        return
    var demand: Dictionary = Demand.propose(sim.economy_snapshot(), 0)
    if not demand.get("ok", false):
        _fail("real N135 demand failed")
        return
    var matched: Dictionary = {}
    for row in demand.get("proposals", []):
        if str(row.get("location", "")) == "alpha-station" and str(row.get("source_location", "")) == "earth-station" and str(row.get("commodity", "")) == "food":
            matched = row
            break
    if matched.is_empty():
        _fail("original N135 directed food demand unavailable")
        return
    var paid: Dictionary = sim.production.post_funded_contract(0, matched)
    if not paid.get("ok", false):
        _fail("real N104 paid contract post rejected: " + str(paid))
        return
    var live: Dictionary = sim.checkpoint()["native_production"]["world"]
    var cid: String = str(paid["contract_id"])
    if not _parity(live, graph, positions, resolver, 0, scale, factions, "real_paid_posted"):
        return
    var variants: Array = [
        "expired", "status_accepted", "stock_empty", "market_missing",
        "owner_missing", "faction_unknown", "quote_missing",
        "ship_busy", "ship_cargo", "ship_capacity", "ship_fuel_zero",
        "ship_no_location", "ship_reputation", "payer_empty",
        "no_positions", "source_endpoint_unmapped", "source_reversed",
        "knowledge_nested", "knowledge_at_source", "knowledge_price_missing",
        "invalid_sensor", "bad_comms_bonus", "duplicate_offer",
        "ship_credits_zero"]
    for name in variants:
        var w: Dictionary = live.duplicate(true)
        var f: Dictionary = factions.duplicate(true)
        var points: Dictionary = positions.duplicate(true)
        var contract: Dictionary = w["contract_board"]["contracts"][cid]
        var source: String = str(contract["source_location"])
        var dest: String = str(contract["destination_location"])
        var commodity: String = str(contract["commodity"])
        var ids: Array = w["ships"].keys()
        ids.sort()
        match name:
            "expired":
                contract["expires_at_tick"] = -1
            "status_accepted":
                contract["status"] = "accepted"
            "stock_empty":
                w["markets"][source]["supply"][commodity] = 0.0
            "market_missing":
                w["markets"].erase(source)
            "owner_missing":
                w["facilities"].erase(str(w["markets"][source]["owner"]))
            "faction_unknown":
                f.clear()
            "quote_missing":
                w["markets"][source]["prices"].erase(commodity)
            "ship_busy":
                for id in ids:
                    w["ships"][id]["active_contract_id"] = cid
            "ship_cargo":
                for id in ids:
                    w["ships"][id]["cargo"] = {"food": 1}
            "ship_capacity":
                for id in ids:
                    w["ships"][id]["cargo_capacity"] = 0
            "ship_fuel_zero":
                for id in ids:
                    w["ships"][id]["fuel"] = 0.0
            "ship_no_location":
                for id in ids:
                    w["ships"][id]["location"] = ""
            "ship_reputation":
                for id in ids:
                    w["ships"][id]["faction_reputation"][str(w["facilities"][str(w["markets"][source]["owner"])]["faction"])] = -100
            "payer_empty":
                var payer_faction: String = str(w["facilities"][str(w["markets"][dest]["owner"])]["faction"])
                w["faction_treasuries"][payer_faction] = 0
                w["facilities"][str(w["markets"][dest]["owner"])]["credits"] = 0
            "no_positions":
                points.clear()
            "source_endpoint_unmapped":
                contract["source_location"] = "unmapped-test-location"
                w["markets"]["unmapped-test-location"] = w["markets"][source].duplicate(true)
            "source_reversed":
                contract["source_location"] = dest
                contract["destination_location"] = source
            "knowledge_nested":
                for id in ids:
                    w["ships"][id]["price_knowledge"] = {
                        "earth-station": {"food": {"price": 999.0},
                            "fuel": {"price": 13.5}},
                        "alpha-station": {"food": {"price": 1.0}},
                        "unrelated-source": {"food": {"price": 42.0}}}
            "knowledge_at_source":
                for id in ids:
                    w["ships"][id]["location"] = source
                    w["ships"][id]["docked_at"] = ""
                    w["ships"][id]["price_knowledge"] = {
                        source: {commodity: {"price": 987654.0},
                            "fuel": {"price": 31.0}}}
            "knowledge_price_missing":
                for id in ids:
                    w["ships"][id]["price_knowledge"] = {}
            "invalid_sensor":
                for id in ids:
                    w["ships"][id]["sensor_range_au"] = -1.0
            "bad_comms_bonus":
                for id in ids:
                    w["ships"][id]["comms_bonus"] = 0.11
            "duplicate_offer":
                var duplicate: Dictionary = contract.duplicate(true)
                duplicate["id"] = "n153-parity-another-offer"
                w["contract_board"]["contracts"][duplicate["id"]] = duplicate
            "ship_credits_zero":
                for id in ids:
                    w["ships"][id]["credits"] = 0
        if not _parity(w, graph, points, resolver, 0, scale, f, name):
            return
    # Test no persistent cache even if the same source dictionary is mutated
    # in place between independent propose() calls (including N38 restore).
    var changed: Dictionary = live.duplicate(true)
    if not _parity(changed, graph, positions, resolver, 0, scale, factions, "before_invalidation"):
        return
    changed["contract_board"]["contracts"][cid]["expires_at_tick"] = -1
    if not _parity(changed, graph, positions, resolver, 0, scale, factions, "after_invalidation"):
        return
    # New independent calls must observe in-place knowledge changes, too.
    var memories: Dictionary = live.duplicate(true)
    if not _parity(memories, graph, positions, resolver, 0, scale, factions, "before_knowledge_change"):
        return
    for id in memories["ships"]:
        memories["ships"][id]["price_knowledge"] = { "earth-station": {"food": {"price": 7.0}}}
    if not _parity(memories, graph, positions, resolver, 0, scale, factions, "after_knowledge_change"):
        return
    print("P2_PARALLEL_B_N153_ORACLE_PARITY_PASS checks=" + str(checks) +
        " baseline=fb8dc0c3a9df3fbdb722a13d214be72ab67bf9df")
    quit(0)

func _parity(world: Dictionary, graph: RefCounted, positions: Dictionary,
        resolver: RefCounted, tick: int, scale: float, factions: Dictionary,
        scenario: String) -> bool:
    var before: Dictionary = world.duplicate(true)
    var baseline: Dictionary = Oracle.propose(world, graph, positions, resolver,
        tick, scale, factions)
    var candidate: Dictionary = Selector.propose(world, graph, positions, resolver,
        tick, scale, factions)
    if world != before:
        _fail(scenario + ": dispatch mutated live world")
        return false
    if baseline != candidate:
        _fail(scenario + ": exact source parity difference, old=" +
            str(baseline) + ", new=" + str(candidate))
        return false
    checks += 1
    return true

func _fail(message: String) -> void:
    push_error("P2_PARALLEL_B_N153_PARITY_FAIL: " + message)
    quit(1)
