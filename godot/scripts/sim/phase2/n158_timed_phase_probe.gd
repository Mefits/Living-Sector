extends "res://scripts/sim/phase2/n158_production_runtime.gd"
## PERF E: opt-in N158 phase stopwatch. Detached scalar measurements only.
## One row per paid tick, bounded to 100; no World or N38 mutations.
const PHASES: Array[String] = ["ships", "dock_queue", "markets", "factions"]
const WINDOW_LIMIT: int = 100
const MAX_PHASE_CALLS_PER_TICK: int = 64
const MAX_RETAINED_CALL_SAMPLES: int = WINDOW_LIMIT * PHASES.size() * MAX_PHASE_CALLS_PER_TICK
var _phase_cost: Dictionary = {}
var _paid_rows: Array[Dictionary] = []
var _failed_tick: int = -1
var _latest_observed_tick: int = 0
var _retained_call_samples: int = 0

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
    # A restarted or rewound source clock invalidates ALL old phase evidence.
    # This never changes the authoritative N158 tick or simulation state.
    if tick < _latest_observed_tick:
        _paid_rows.clear()
        _phase_cost.clear()
        _failed_tick = -1
        _retained_call_samples = 0
    _latest_observed_tick = tick
    if not accepted or elapsed < 0:
        _invalidate_paid_observation(tick)
        return
    if tick == _failed_tick:
        return
    if _paid_rows.is_empty() or int(_paid_rows.back()["tick"]) != tick:
        var row: Dictionary = {"tick": tick}
        for name in PHASES:
            row[name] = 0
        row["_seen"] = {}
        row["_calls"] = {}
        row["_durations"] = {}
        _paid_rows.append(row)
        while not _paid_rows.is_empty() and int(_paid_rows[0]["tick"]) <= tick - WINDOW_LIMIT:
            var expired: Dictionary = _paid_rows.pop_front()
            for name in PHASES:
                _retained_call_samples -= int(expired["_calls"].get(name, 0))
    var current: Dictionary = _paid_rows.back()
    var counts: Dictionary = current["_calls"]
    if int(counts.get(phase, 0)) >= MAX_PHASE_CALLS_PER_TICK or (
            _retained_call_samples >= MAX_RETAINED_CALL_SAMPLES):
        _invalidate_paid_observation(tick)
        return
    counts[phase] = int(counts.get(phase, 0)) + 1
    current[phase] = int(current[phase]) + elapsed
    current["_seen"][phase] = true
    var durations: Dictionary = current["_durations"]
    if not durations.has(phase):
        durations[phase] = []
    durations[phase].append(elapsed)
    _retained_call_samples += 1
    var stats: Dictionary = _phase_cost.get(phase, {
        "calls": 0, "total_usec": 0, "max_usec": 0})
    stats["calls"] = int(stats["calls"]) + 1
    stats["total_usec"] = int(stats["total_usec"]) + elapsed
    stats["max_usec"] = maxi(int(stats["max_usec"]), elapsed)
    _phase_cost[phase] = stats

func _invalidate_paid_observation(tick: int) -> void:
    _failed_tick = tick
    _paid_rows.clear()
    _retained_call_samples = 0

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
        var row: Dictionary = {"tick": tick, "_seen": {}, "_calls": {}, "_durations": {}}
        for phase in PHASES:
            row[phase] = 0
            row["_calls"][phase] = 0
        if by_tick.has(tick):
            var source: Dictionary = by_tick[tick]
            for phase in PHASES:
                row[phase] = int(source.get(phase, 0))
                row["_calls"][phase] = int(source.get("_calls", {}).get(phase, 0))
                row["_durations"][phase] = source.get("_durations", {}).get(phase, []).duplicate()
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

## Real integrated-phase callsites, not guessed from aggregate paid-tick time.
## Bounded by the same 100 paid-tick rows. All returned arrays are detached.
func paid_callsite_costs(end_tick: int) -> Dictionary:
    var rows: Array = paid_phase_window(end_tick)
    if rows.size() != WINDOW_LIMIT:
        return {}
    var costs: Dictionary = {}
    for phase in PHASES:
        var durations: Array[int] = []
        var total: int = 0
        var active: int = 0
        for row in rows:
            var observed: Array = row["_durations"].get(phase, [])
            var calls: int = int(row["_calls"].get(phase, 0))
            if observed.size() != calls or calls < 0 or calls > 10000:
                return {}
            if calls > 0:
                active += 1
            var tick_total: int = 0
            for sample in observed:
                if typeof(sample) != TYPE_INT or int(sample) < 0:
                    return {}
                durations.append(int(sample))
                tick_total += int(sample)
            if tick_total != int(row[phase]):
                return {}
            total += tick_total
        if durations.is_empty():
            return {}
        durations.sort()
        var p95_index: int = ceili(float(durations.size()) * 0.95) - 1
        costs[phase] = {"calls": durations.size(), "active_paid_ticks": active,
            "total_usec": total, "avg_per_call_usec": float(total) / float(durations.size()),
            "p95_per_call_usec": durations[p95_index],
            "max_per_call_usec": durations.back()}
    return {"from_tick": end_tick - WINDOW_LIMIT + 1, "to_tick": end_tick,
        "observed_paid_ticks": WINDOW_LIMIT, "sites": costs,
        "time_kind": "elapsed_wall_not_cpu"}
