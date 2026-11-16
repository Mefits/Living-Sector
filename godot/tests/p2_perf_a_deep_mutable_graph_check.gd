extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_perf_a_deep_mutable_graph_check.gd
const Guard = preload("res://scripts/sim/phase1/n39_market_owned_write_guard.gd")
var failed: bool = false

func _initialize() -> void:
    # Build depth without recursive helpers. Both graphs are independently
    # allocated; sharing a deep leaf must be rejected without stack recursion.
    var old_leaf: Dictionary = {"stock": [1, 2, 3]}
    var new_leaf: Dictionary = {"stock": [1, 2, 3]}
    var old_tree: Variant = old_leaf
    var new_tree: Variant = new_leaf
    for i in range(256):
        old_tree = {"next": [old_tree]}
        new_tree = {"next": [new_tree]}
    _expect(not Guard._shares_mutable_storage(old_tree, new_tree),
        "deep_independent_graph")
    new_leaf["stock"] = old_leaf["stock"]
    _expect(Guard._shares_mutable_storage(old_tree, new_tree),
        "deep_shared_array_leaf")
    # Repeated references must terminate rather than repeatedly expand.
    var repeated: Array = []
    var child: Dictionary = {"payload": [7]}
    for i in range(128):
        repeated.append(child)
    var separate: Array = []
    for i in range(128):
        separate.append({"payload": [7]})
    _expect(not Guard._shares_mutable_storage(repeated, separate),
        "repeated_nodes_detached")
    separate[127] = child
    _expect(Guard._shares_mutable_storage(repeated, separate),
        "repeated_nodes_alias")
    if not failed:
        print("P2_PERF_A_DEEP_MUTABLE_GRAPH_PASS")
    quit(1 if failed else 0)

func _expect(ok: bool, label: String) -> void:
    if not ok:
        failed = true
        push_error("P2_PERF_A_DEEP_MUTABLE_GRAPH_FAIL: " + label)
