extends SceneTree
## Selector-valid N153 replicas from the original paid N104 offer and real
## N4 graph. These clones are never committed as authoritative N39 ships.
## Per-function latency is NOT whole-simulation speedup.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
const Selector = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Oracle = preload("res://tests/p2_parallel_b_n153_source_oracle.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    var sim = Runtime.new()
    if seed.has("error") or not sim.start_from_seed(seed):
        _fail("original N158 seed unavailable")
        return
    var checkpoint: Dictionary = sim.checkpoint()
    var w: Dictionary = checkpoint["native_production"]["world"]
    w["markets"]["alpha-station"]["prices"]["food"] = 60.0
    w["markets"]["earth-station"]["prices"]["food"] = 4.0
    var stock: float = float(w["markets"]["alpha-station"]["supply"]["food"])
    w["markets"]["alpha-station"]["consumption_window"]["food"] = [
        {"tick": 0, "qty": stock + 5.0}]
    if not sim.restore_checkpoint(checkpoint, seed):
        _fail("N39 fixture restore failed")
        return
    var needs: Dictionary = Demand.propose(sim.economy_snapshot(), 0)
    var matched: Dictionary = {}
    for row in needs.get("proposals", []):
        if str(row.get("location", "")) == "alpha-station" and str(row.get("source_location", "")) == "earth-station" and str(row.get("commodity", "")) == "food":
            matched = row
            break
    if matched.is_empty():
        _fail("no native N135 demand")
        return
    var funded: Dictionary = sim.production.post_funded_contract(0, matched)
    if not funded.get("ok", false):
        _fail("paid original N104 offer not posted: " + str(funded))
        return
    var world: Dictionary = sim.checkpoint()["native_production"]["world"]
    var roster = Roster.new()
    var resolver = Resolver.new()
    if not roster.load_seed(seed) or not resolver.load_seed(seed):
        _fail("native route source unavailable")
        return
    var pos: Dictionary = resolver.positions_from_world(
        sim.world, sim.calendar.native_time_units, sim.calendar.origin_known)
    if not pos.get("ok", false):
        _fail("native N80 positions unavailable")
        return
    var f: Dictionary = {}
    for row in seed["factions"]:
        f[str(row["id"])] = row
    var graph = roster.registry.graph()
    var prototype: Dictionary = {}
    for id in world["ships"]:
        var ship: Dictionary = world["ships"][id]
        if str(ship.get("class", "")) == "hauler" and str(ship.get("faction_id", "")) == "terran-authority":
            prototype = ship
            break
    if prototype.is_empty():
        _fail("real hauler prototype unavailable")
        return
    for count in [24, 100, 500]:
        var batch: Dictionary = world.duplicate(true)
        var original_count: int = batch["ships"].size()
        for i in range(original_count, count):
            var sid: String = "n153-test-" + str(i).pad_zeros(4)
            var clone: Dictionary = prototype.duplicate(true)
            clone["id"] = sid
            clone["active_contract_id"] = ""
            clone["transit"] = {}
            clone["cargo"] = {}
            batch["ships"][sid] = clone
        if batch["ships"].size() != count:
            _fail("invalid fixture fleet count=" + str(count))
            return
        var old_start: int = Time.get_ticks_usec()
        var baseline: Dictionary = Oracle.propose(batch, graph, pos["positions"],
            resolver, 0, sim.clock.tick_scale(), f)
        var old_us: int = Time.get_ticks_usec() - old_start
        var new_start: int = Time.get_ticks_usec()
        var candidate: Dictionary = Selector.propose(batch, graph, pos["positions"],
            resolver, 0, sim.clock.tick_scale(), f)
        var new_us: int = Time.get_ticks_usec() - new_start
        if baseline != candidate:
            _fail("selector differs at " + str(count) + " ships: " +
                str(baseline) + " versus " + str(candidate))
            return
        var ids: Array = batch["contract_board"]["contracts"].keys()
        print("P2_PARALLEL_B_N153_SCALE_PASS ships=" + str(count) +
            " contracts=" + str(ids.size()) + " contract_ship_upper_bound=" +
            str(ids.size() * count) + " old_us=" + str(old_us) +
            " new_us=" + str(new_us) + " parity=true")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PARALLEL_B_N153_SCALE_FAIL: " + message)
    quit(1)
