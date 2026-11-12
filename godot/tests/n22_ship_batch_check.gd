extends SceneTree
## Run: godot --headless --path godot --script res://tests/n22_ship_batch_check.gd
const Model = preload("res://scripts/view/ship_batch_model.gd")
const Canvas = preload("res://scripts/view/ship_batch_canvas.gd")

func _initialize() -> void:
    var model = Model.new()
    var records: Array = []
    for i in range(10000):
        records.append({"id": "ship-%05d" % i, "position": [float(i), 0.0], "class": "miner"})
    assert(model.set_records(records))
    assert(model.total_count() == 10000)
    assert(model.visible_records(Rect2(Vector2(100, -10), Vector2(20, 20))).size() == 21)
    assert(model.pick(Vector2(500.0, 0.0), 1.0) == "ship-00500")
    assert(not model.set_records([{"id": "dup", "position": [0, 0]}, {"id": "dup", "position": [1, 1]}]))
    assert(model.total_count() == 10000)
    assert(not model.set_records([{"id": "bad", "position": [INF, 0]}]))
    assert(model.total_count() == 10000)
    var canvas = Canvas.new()
    root.add_child(canvas)
    canvas.size = Vector2(200, 100)
    assert(canvas.set_ships([{"id": "s1", "position": [0, 0], "class": "miner"}]))
    assert(canvas.set_camera(Vector2.ZERO, 2.0))
    assert(canvas.world_to_screen(Vector2.ZERO).is_equal_approx(Vector2(100, 50)))
    assert(canvas.screen_to_world(Vector2(100, 50)).is_equal_approx(Vector2.ZERO))
    assert(not canvas.set_camera(Vector2.ZERO, 0.0))
    canvas.queue_free()
    print("N22_SHIP_BATCH_OK 10000 records, culling, selection, atomic rejection, transforms")
    quit(0)
