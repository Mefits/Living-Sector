extends SceneTree
## Structural negative regression for N84's single-use BeginTransit preview.
## Full behavioral oracle and N38 replay remain required before acceptance.
const SOURCE = "res://scripts/sim/phase2/unified_ship_ai_execution.gd"

func _initialize() -> void:
    var file := FileAccess.open(SOURCE, FileAccess.READ)
    assert(file != null, "N84 source must exist")
    var source: String = file.get_as_text()
    assert(source.contains('dock_ticks["_n84_pending_departure"] ='), "Travel must stage its validated preview")
    assert(source.contains('dock_ticks.erase("_n84_pending_departure")'), "Preview must be consumed only once")
    assert(source.contains('pending_departure.get("ship", "")'), "Reject stale ship identity")
    assert(source.contains('pending_departure.get("to", "")'), "Reject stale destination")
    assert(source.contains('pending_departure.get("token", -1)'), "Reject stale transit token")
    assert(source.contains('native_move = ShipPhase.preview_depart(staged, graph,'), "Keep authoritative fallback")
    assert(source.contains('int(actual.get("arrival_tick", -1)) != int(command["arrival_tick"])'), "Keep receipt parity guard")
    assert(source.contains('staged["ship_next_token"] = int(native_move["next_token"])'), "Keep token update")
    print("PASS p2_perf_c_n84_single_departure_preview_regression (structural)")
    quit(0)
