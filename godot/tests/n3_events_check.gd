extends SceneTree
## godot --headless --path godot --script res://tests/n3_events_check.gd
const Runner = preload("res://scripts/sim/tick_runner.gd")
const Events = preload("res://scripts/sim/event_queue.gd")
const Cadence = preload("res://scripts/sim/cadence.gd")
const NativeData = preload("res://scripts/native_data.gd")

var received: Array[String] = []

func _initialize() -> void:
    var q = Events.new()
    if not q.schedule("a", 2, 3, "ship-z", "audit"):
        _fail("schedule")
        return
    if q.schedule("a", 2, 3, "ship-z", "audit"):
        _fail("duplicate id")
        return
    if not q.schedule("b", 2, 3, "ship-a", "audit"):
        _fail("second schedule")
        return
    if not q.schedule("c", 2, 2, "ship-z", "audit"):
        _fail("phase schedule")
        return
    if not q.schedule("d", 3, 2, "ship-a", "audit"):
        _fail("cancel schedule")
        return
    if not q.cancel("d") or q.cancel("d"):
        _fail("cancel idempotence")
        return
    var saved: Dictionary = q.snapshot()
    var restored = Events.new()
    if not restored.restore(saved, 0, 20):
        _fail("restore")
        return
    if restored.take_due(2, 2)[0]["id"] != "c":
        _fail("phase order")
        return
    var ordered: Array[Dictionary] = restored.take_due(2, 3)
    if ordered.size() != 2 or ordered[0]["id"] != "b" or ordered[1]["id"] != "a":
        _fail("entity order")
        return
    if restored.pending_count() != 0:
        _fail("pending drain")
        return
    var bad: Dictionary = saved.duplicate(true)
    bad["pending"][0]["due_tick"] = 0
    if restored.restore(bad, 0, 20) or restored.pending_count() != 0:
        _fail("transactional invalid restore")
        return

    var cadence = Cadence.new()
    if not cadence.configure("markets", 8, 3):
        _fail("cadence configure")
        return
    if cadence.is_due("markets", 2) or not cadence.is_due("markets", 3) or not cadence.is_due("markets", 11):
        _fail("cadence periodicity")
        return
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var a = Runner.new()
    var b = Runner.new()
    if not a.start_from_seed(seed) or not b.start_from_seed(seed):
        _fail("runner seed")
        return
    a.scheduled_event_due.connect(_on_event)
    if not a.schedule_event("later", 4, "markets", "market-2", "audit", {"value": 7}):
        _fail("runner schedule")
        return
    if not a.schedule_event("earlier", 2, "ships", "ship-1", "audit"):
        _fail("runner second schedule")
        return
    if a.schedule_event("past", 0, "ships", "ship-1", "audit"):
        _fail("past event accepted")
        return
    a.queue_control("pause")
    a.queue_control("step", 2)
    a.advance_frame(0.0)
    if received != ["earlier"] or a.tick_count != 2:
        _fail("due dispatch")
        return
    var checkpoint: Dictionary = a.checkpoint()
    if not b.restore_checkpoint(checkpoint, seed):
        _fail("runner restore")
        return
    if b.events.snapshot() != a.events.snapshot():
        _fail("event save parity")
        return
    b.scheduled_event_due.connect(_on_event)
    b.queue_control("pause")
    b.queue_control("step", 2)
    b.advance_frame(0.0)
    if received != ["earlier", "later"] or b.events.pending_count() != 0:
        _fail("resumed event")
        return
    if b.world.orbital_snapshot() == {}:
        _fail("orbit unexpectedly absent")
        return
    print("N3_EVENTS_PASS: order, dedup, cancellation, cadence, transactional save, phase dispatch")
    quit(0)

func _on_event(event: Dictionary) -> void:
    received.append(str(event["id"]))

func _fail(message: String) -> void:
    push_error("N3_EVENTS_FAIL: " + message)
    quit(1)
