extends "res://scripts/sim/phase2/n158_production_runtime.gd"
## PERF E: opt-in N158 phase stopwatch. Detached scalar measurements only.
## One row per paid tick, bounded to 100; no World or N38 mutations.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]
const WINDOW_LIMIT: int = 100
var _phase_cost: Dictionary = {}
var _paid_rows: Array[Dictionary] = []
var _failed_tick: int = -1

func _execute_integrated_phase(phase: String, tick: int) -> bool:
    var began: int = Time.get_ticks_usec()
    var accepted: bool = super._execute_integrated_phase(phase, tick)
    var elapsed: int = maxi(0, Time.get_ticks_usec() - began)
    _record_phase_elapsed(phase, tick, elapsed, accepted)
    return accepted

## Failed stages are not charged as successful source-tick measurements.
## Multiple calls to a phase in one tick are accumulated, not overwritten.
func _record_phase_elapsed(phase: String, tick: int, elapsed: int, accepted: bool) -> void:
    if tick < 1 or not PHASES.has(phase):
        return
    if not accepted or elapsed < 0:
        # An aborted phase invalidates the entire paid-tick candidate, even
        # when earlier phases succeeded. Never certify a partial source tick.
        _failed_tick = tick
        _paid_rows.clear()
        return
    if tick == _failed_tick:
        return
    var stats: Dictionary = _phase_cost.get(phase, {
        "calls": 0, "total_usec": 0, "max_usec": 0})
    stats["calls"] = int(stats["calls"]) + 1
    stats["total_usec"] = int(stats["total_usec"]) + elapsed
    stats["max_usec"] = maxi(int(stats["max_usec"]), elapsed)
    _phase_cost[phase] = stats
    if _paid_rows.is_empty() or int(_paid_rows.back()["tick"]) != tick:
        # Discontinuities (restart, replay, or a skipped tick) cannot be
        # presented as contiguous paid-tick evidence.
        if not _paid_rows.is_empty() and tick != int(_paid_rows.back()["tick"]) + 1:
            _paid_rows.clear()
        var row: Dictionary = {"tick": tick}
        for name in PHASES:
            row[name] = 0
        row["_seen"] = {}
        _paid_rows.append(row)
        if _paid_rows.size() > WINDOW_LIMIT:
            _paid_rows.pop_front()
    _paid_rows[_paid_rows.size() - 1][phase] += elapsed
    _paid_rows[_paid_rows.size() - 1]["_seen"][phase] = true

func phase_metrics() -> Dictionary:
    return _phase_cost.duplicate(true)

## Return only a complete, contiguous 100-tick window with every required
## phase observed; callers must not interpret sparse rows as paid tick samples.
func paid_phase_window(end_tick: int) -> Array:
    if _failed_tick == end_tick or _paid_rows.size() != WINDOW_LIMIT or int(_paid_rows.back()["tick"]) != end_tick:
        return []
    for i in range(WINDOW_LIMIT):
        if int(_paid_rows[i]["tick"]) != end_tick - WINDOW_LIMIT + 1 + i:
            return []
        for phase in PHASES:
            if not _paid_rows[i]["_seen"].has(phase):
                return []
    return _paid_rows.duplicate(true)

## Only completed contiguous paid-tick candidates contribute to these totals.
## Unlike phase_metrics(), this never includes partial/aborted phase calls.
## Caller must still verify authoritative SourceClock/N38 completion separately.
func paid_phase_totals(end_tick: int) -> Dictionary:
    var rows: Array = paid_phase_window(end_tick)
    if rows.is_empty():
        return {}
    var totals: Dictionary = {}
    for phase in PHASES:
        totals[phase] = 0
    for row in rows:
        for phase in PHASES:
            totals[phase] = int(totals[phase]) + int(row[phase])
    return {"from_tick": end_tick - WINDOW_LIMIT + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW_LIMIT,
        "phase_total_usec": totals, "time_kind": "elapsed_wall_not_cpu"}

## Detached phase distribution for an independently confirmed paid-tick window.
## No source-tick certification is implied by phase execution alone.
func paid_phase_distribution(end_tick: int) -> Dictionary:
    var rows: Array = paid_phase_window(end_tick)
    if rows.is_empty():
        return {}
    var averages: Dictionary = {}
    var p95: Dictionary = {}
    var maxima: Dictionary = {}
    var totals: Dictionary = {}
    for phase in PHASES:
        var durations: Array[int] = []
        var total: int = 0
        for row in rows:
            var duration: int = int(row[phase])
            if duration < 0:
                return {}
            durations.append(duration)
            total += duration
        durations.sort()
        totals[phase] = total
        averages[phase] = float(total) / float(WINDOW_LIMIT)
        p95[phase] = durations[94]
        maxima[phase] = durations[99]
    return {"from_tick": end_tick - WINDOW_LIMIT + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW_LIMIT,
        "phase_total_usec": totals, "phase_avg_usec": averages,
        "phase_p95_usec": p95, "phase_max_usec": maxima,
        "time_kind": "elapsed_wall_not_cpu",
        "requires_authoritative_source_clock_confirmation": true}
