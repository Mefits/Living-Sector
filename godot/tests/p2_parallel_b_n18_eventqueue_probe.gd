extends SceneTree
## B6/B7 diagnostics. N18 uses actual original N39 market/facility/cohort
## data with a matching N9 ledger. EventQueue is NOT called by the active
## N158/N39 loop; its queue fixture below is synthetic and is NOT a FPS test.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Station = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")
const EventQueue = preload("res://scripts/sim/event_queue.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    var sim = Runtime.new()
    if seed.has("error") or not sim.start_from_seed(seed):
        _fail("original N158 N39 seed unavailable")
        return
    var world: Dictionary = sim.checkpoint()["native_production"]["world"]
    var account_data: Dictionary = Schema.accounts(world)
    var ledger = Ledger.new()
    if not ledger.import_accounts(account_data):
        _fail("real N9 source accounts rejected")
        return
    var market_count: int = world["markets"].size()
    var facilities: int = world["facilities"].size()
    var populations: int = world["populations"].size()
    var original: Dictionary = world.duplicate(true)
    var t0: int = Time.get_ticks_usec()
    var first: Dictionary = Station.propose(world, ledger, 5, 1)
    var first_us: int = Time.get_ticks_usec() - t0
    if not first.get("ok", false) or not first.get("due", false):
        _fail("actual N18 due cycle failed: " + str(first))
        return
    var iterations: int = 6
    var t1: int = Time.get_ticks_usec()
    for _i in range(iterations):
        var again: Dictionary = Station.propose(world, ledger, 5, 1)
        if again != first:
            _fail("source N18 nondeterministic plan")
            return
    var six_us: int = Time.get_ticks_usec() - t1
    if world != original:
        _fail("N18 proposed staffing mutated original N39 world")
        return
    print("P2_PARALLEL_B_N18_BASELINE_PASS markets=" + str(market_count) +
        " facilities=" + str(facilities) + " populations=" + str(populations) +
        " population_scan_upper_bound=" + str(market_count * populations) +
        " facility_scan_upper_bound=" + str(market_count * facilities) +
        " first_us=" + str(first_us) + " six_us=" + str(six_us) +
        " due_every_ticks=5")
    var events = EventQueue.new()
    if events.pending_count() != 0:
        _fail("new EventQueue is not empty")
        return
    if not events.schedule("a", 5, 1, "beta", "probe", {"n": 1}) or (
            not events.schedule("b", 5, 1, "alpha", "probe", {"n": 2})) or (
            not events.schedule("c", 5, 1, "alpha", "probe", {"n": 3})):
        _fail("EventQueue fixture cannot schedule")
        return
    if events.schedule("a", 5, 1, "beta", "probe"):
        _fail("EventQueue accepted duplicate active id")
        return
    if not events.cancel("a") or not events.schedule("a", 6, 1, "beta", "probe"):
        _fail("EventQueue cannot cancel and reuse an id")
        return
    var restored = EventQueue.new()
    if not restored.restore(events.snapshot(), 0, 4):
        _fail("EventQueue fixture N38 restore invalid")
        return
    if not restored.take_due(4, 1).is_empty():
        _fail("EventQueue emitted early event")
        return
    var due: Array[Dictionary] = restored.take_due(5, 1)
    if due.size() != 2 or str(due[0]["id"]) != "b" or str(due[1]["id"]) != "c":
        _fail("EventQueue changed entity/sequence ordering")
        return
    if restored.take_due(5, 1).size() != 0 or (
            restored.take_due(6, 1).size() != 1):
        _fail("EventQueue replayed or dropped an event")
        return
    var empty_q = EventQueue.new()
    var start_us: int = Time.get_ticks_usec()
    for tick in range(1, 421):
        for phase in range(4):
            empty_q.take_due(tick, phase)
    var empty_us: int = Time.get_ticks_usec() - start_us
    print("P2_PARALLEL_B_EVENT_QUEUE_NO_CHANGE_PASS source_runtime_bound=false" +
        " empty_420x4_us=" + str(empty_us) +
        " fixture_order_cancel_restore=true")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PARALLEL_B_OPTIONAL_PROBE_FAIL: " + reason)
    quit(1)
