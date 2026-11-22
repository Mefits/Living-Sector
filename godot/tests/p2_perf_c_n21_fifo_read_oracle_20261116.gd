extends SceneTree
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
func _initialize() -> void:
    var source: Array = []
    for i in range(1200):
        source.append("ship_%04d" % (i % 317))
    var staged: Dictionary = {"dock_queue": source.duplicate(true)}
    var observed: Array = []
    while not staged["dock_queue"].is_empty():
        var legacy: String = str(Dock._queue(staged)[0])
        var optimized: String = str(staged["dock_queue"][0])
        if legacy != optimized:
            push_error("N21 FIFO head order diverged")
            quit(1)
            return
        observed.append(optimized)
        staged["dock_queue"].pop_front()
    if observed != source or source.size() != 1200 or source[0] != "ship_0000":
        push_error("N21 FIFO order/source ownership regression")
        quit(1)
        return
    print("PASS p2_perf_c_n21_fifo_read_oracle_20261116")
    quit(0)
