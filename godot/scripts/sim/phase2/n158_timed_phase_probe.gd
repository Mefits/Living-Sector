extends "res://scripts/sim/phase2/n158_production_runtime.gd"
## E: isolated transparent N158 phase stopwatch for same-seed profiling.
## No production runtime changes, new economies, timers in checkpoints, or
## modifications to source N1 cadence, AI budget, finance or market actions.
var _phase_cost: Dictionary = {}

func _execute_integrated_phase(phase: String, tick: int) -> bool:
    var began: int = Time.get_ticks_usec()
    var accepted: bool = super._execute_integrated_phase(phase, tick)
    var elapsed: int = maxi(0, Time.get_ticks_usec() - began)
    var stats: Dictionary = _phase_cost.get(phase, {
        "calls": 0, "total_usec": 0, "max_usec": 0})
    stats["calls"] = int(stats["calls"]) + 1
    stats["total_usec"] = int(stats["total_usec"]) + elapsed
    stats["max_usec"] = maxi(int(stats["max_usec"]), elapsed)
    _phase_cost[phase] = stats
    return accepted

func phase_metrics() -> Dictionary:
    return _phase_cost.duplicate(true)
