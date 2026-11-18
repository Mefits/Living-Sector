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
        if not _paid_rows.is_empty() and tick < int(_paid_rows.back()["tick"]):
            _paid_rows.clear()
        var row: Dictionary = {"tick": tick}
        for name in PHASES:
            row[name] = 0
        row["_seen"] = {}
        row["_calls"] = {}
        _paid_rows.append(row)
        while not _paid_rows.is_empty() and int(_paid_rows[0]["tick"]) <= tick - WINDOW_LIMIT:
            _paid_rows.pop_front()
    _paid_rows[_paid_rows.size() - 1][phase] += elapsed
    _paid_rows[_paid_rows.size() - 1]["_seen"][phase] = true
    var counts: Dictionary = _paid_rows[_paid_rows.size() - 1]["_calls"]
    counts[phase] = int(counts.get(phase, 0)) + 1

func phase_metrics() -> Dictionary:
    return _phase_cost.duplicate(true)

## Return only a complete, contiguous 100-tick window with every required
## phase observed; callers must not interpret sparse rows as paid tick samples.
func paid_phase_window(end_tick: int) -> Array:
    if end_tick < WINDOW_LIMIT or _failed_tick >= end_tick - WINDOW_LIMIT + 1 and _failed_tick <= end_tick:
        return []
    # Cadence legitimately skips phases and even whole phase-observation ticks.
    # Missing observations are zero calls, NOT a missing authoritative paid tick.
    # The caller must independently certify 100 contiguous committed SourceClock ticks.
    var by_tick: Dictionary = {}
    for source_row in _paid_rows:
        var observed_tick: int = int(source_row["tick"])
        if observed_tick >= end_tick - WINDOW_LIMIT + 1 and observed_tick <= end_tick:
            by_tick[observed_tick] = source_row
    var result: Array = []
    var coverage: Dictionary = {}
    for name in PHASES:
        coverage[name] = 0
    for tick in range(end_tick - WINDOW_LIMIT + 1, end_tick + 1):
        var row: Dictionary = {"tick": tick, "_seen": {}, "_calls": {}}
        for phase in PHASES:
            row[phase] = 0
            row["_calls"][phase] = 0
        if by_tick.has(tick):
            var source: Dictionary = by_tick[tick]
            for phase in PHASES:
                row[phase] = int(source.get(phase, 0))
                row["_calls"][phase] = int(source.get("_calls", {}).get(phase, 0))
                if row["_calls"][phase] > 0:
                    row["_seen"][phase] = true
                    coverage[phase] = int(coverage[phase]) + row["_calls"][phase]
        result.append(row)
    # A wholly uninstrumented phase is not valid profiling evidence.
    for phase in PHASES:
        if int(coverage[phase]) == 0:
            return []
    return result

## Only completed contiguous paid-tick candidates contribute to these totals.
## Unlike phase_metrics(), this never includes partial/aborted phase calls.
## Caller must still verify authoritative SourceClock/N38 completion separately.
func paid_phase_totals(end_tick: int) -> Dictionary:
    var rows: Array = paid_phase_window(end_tick)
    if rows.is_empty():
        return {}
    var totals: Dictionary = {}
    var calls: Dictionary = {}
    for phase in PHASES:
        totals[phase] = 0
        calls[phase] = 0
    for row in rows:
        for phase in PHASES:
            totals[phase] = int(totals[phase]) + int(row[phase])
            calls[phase] = int(calls[phase]) + int(row["_calls"][phase])
    return {"from_tick": end_tick - WINDOW_LIMIT + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW_LIMIT,
        "phase_total_usec": totals, "phase_calls": calls,
        "time_kind": "elapsed_wall_not_cpu"}

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
    var calls: Dictionary = {}
    var active_ticks: Dictionary = {}
    for phase in PHASES:
        calls[phase] = 0
        active_ticks[phase] = 0
        var durations: Array[int] = []
        var total: int = 0
        for row in rows:
            var duration: int = int(row[phase])
            if duration < 0:
                return {}
            durations.append(duration)
            total += duration
            calls[phase] = int(calls[phase]) + int(row["_calls"][phase])
            if int(row["_calls"][phase]) > 0:
                active_ticks[phase] = int(active_ticks[phase]) + 1
        durations.sort()
        totals[phase] = total
        averages[phase] = float(total) / float(WINDOW_LIMIT)
        p95[phase] = durations[94]
        maxima[phase] = durations[99]
    return {"from_tick": end_tick - WINDOW_LIMIT + 1,
        "to_tick": end_tick, "observed_paid_ticks": WINDOW_LIMIT,
        "phase_total_usec": totals, "phase_avg_usec": averages,
        "phase_p95_usec": p95, "phase_max_usec": maxima,
        "phase_calls": calls, "phase_active_paid_ticks": active_ticks,
        "time_kind": "elapsed_wall_not_cpu",
        "requires_authoritative_source_clock_confirmation": true}
