extends SceneTree
## Targeted negative ownership regression for N14's N140-owned fleet.
## The N14 advance path must never expose mutable N39 World rows.
const Gate = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")

func _initialize() -> void:
    var ship: Dictionary = {
        "id": "ship-a", "location": "sol", "transit": {},
        "cargo": {"ore": 7}, "memory": {"visited": ["sol"]},
        "current_bt": {"children": [{"index": 2}]},
        "fuel": 100.0
    }
    var world: Dictionary = {"ships": {"ship-a": ship}}
    var positions: Dictionary = {"sol": Vector2(0.0, 0.0)}
    var gate: Dictionary = Gate.stage(world, positions, 1, 1, [])
    if not gate.get("ok", false):
        push_error("N140 stage rejected valid minimal ownership fixture: " + str(gate))
        quit(1)
        return
    var owned: Dictionary = gate["ships"]
    if owned["ship-a"] == null:
        push_error("N140 detached fleet missing ship")
        quit(1)
        return
    # Negative mutation oracle: the returned owned fleet must not alias
    # nested cargo, memory, or BT in authoritative World.
    owned["ship-a"]["cargo"]["ore"] = 99
    owned["ship-a"]["memory"]["visited"].append("alpha")
    owned["ship-a"]["current_bt"]["children"][0]["index"] = 9
    if int(world["ships"]["ship-a"]["cargo"]["ore"]) != 7 or \
            (world["ships"]["ship-a"]["memory"]["visited"] as Array).size() != 1 or \
            int(world["ships"]["ship-a"]["current_bt"]["children"][0]["index"]) != 2:
        push_error("N140-owned N14 preview leaked mutable alias into World")
        quit(1)
        return
    # Guard the actual N14 return boundary against reintroducing a
    # full-fleet copy or accidentally returning the original World.
    var script: String = FileAccess.get_file_as_string(
        "res://scripts/sim/phase2/unified_ship_phase.gd")
    var advance_start: int = script.find("static func advance(")
    var depart_start: int = script.find("static func depart(", advance_start)
    if advance_start < 0 or depart_start <= advance_start:
        push_error("N14 advance/depart source boundaries missing")
        quit(1)
        return
    var advance_source: String = script.substr(advance_start, depart_start - advance_start)
    if not advance_source.contains('"ships": state.ships') or \
            advance_source.contains("updated[str(id)] = (state.ships[id] as Dictionary).duplicate(true)"):
        push_error("N14 advance no longer returns N140-owned fleet directly")
        quit(1)
        return
    print("PASS C N14 N140-owned fleet nested alias and advance return boundary")
    quit(0)
