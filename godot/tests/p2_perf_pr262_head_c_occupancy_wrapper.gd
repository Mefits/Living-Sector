extends SceneTree
## CLI wrapper around C's pure RefCounted .run() oracle, so current-HEAD
## GitHub smoke actually executes the 2000-ship occupancy comparison.
const Oracle = preload("res://tests/p2_perf_c_n21_request_occupancy_oracle_20261116.gd")

func _initialize() -> void:
    var result: Dictionary = Oracle.run()
    if not bool(result.get("ok", false)):
        push_error("P2_PR262_N21_REQUEST_OCCUPANCY_FAIL "
            + str(result.get("reason", "unknown")))
        quit(1)
        return
    print("P2_PR262_N21_REQUEST_OCCUPANCY_PASS")
    quit(0)
