extends "res://scripts/main.gd"
## Headless diagnostic wrapper for EXACT Sol Lab UI. No gameplay edits.
var measuring: bool = false
var samples: Array[Dictionary] = []
var perf_calls: int = 0
var map_calls: int = 0
var panel_calls: int = 0
var dock_calls: int = 0
var perf_last_usec: int = 0
var map_last_usec: int = 0
var panel_last_usec: int = 0
var dock_last_usec: int = 0

func _update_performance_label() -> void:
 var start: int = Time.get_ticks_usec()
 super._update_performance_label()
 perf_last_usec = Time.get_ticks_usec() - start
 perf_calls += 1

func _update_native_map(snap_freight: bool = false) -> void:
 var start: int = Time.get_ticks_usec()
 super._update_native_map(snap_freight)
 map_last_usec = Time.get_ticks_usec() - start
 map_calls += 1

func _show_selected() -> void:
 var start: int = Time.get_ticks_usec()
 super._show_selected()
 panel_last_usec = Time.get_ticks_usec() - start
 panel_calls += 1

func _refresh_construction_ui() -> void:
 var start: int = Time.get_ticks_usec()
 super._refresh_construction_ui()
 dock_last_usec = Time.get_ticks_usec() - start
 dock_calls += 1

func _process(delta: float) -> void:
 var previous: int = previous_process_started_usec
 var start: int = Time.get_ticks_usec()
 var before_perf: int = perf_calls
 var before_map: int = map_calls
 var before_panel: int = panel_calls
 var before_dock: int = dock_calls
 super._process(delta)
 if not measuring:
  return
 var perf_now: bool = perf_calls != before_perf
 var map_now: bool = map_calls != before_map
 var panel_now: bool = panel_calls != before_panel
 var dock_now: bool = dock_calls != before_dock
 samples.append({
  "dt_ms": (float(start - previous) / 1000.0 if previous >= 0 else 0.0),
  "process_ms": float(Time.get_ticks_usec() - start) / 1000.0,
  "ui_ms": float(frame_profiler._ui_us.back()) / 1000.0,
  "perf": perf_now, "perf_ms": float(perf_last_usec) / 1000.0 if perf_now else 0.0,
  "map": map_now, "map_ms": float(map_last_usec) / 1000.0 if map_now else 0.0,
  "panel": panel_now, "panel_ms": float(panel_last_usec) / 1000.0 if panel_now else 0.0,
  "dock": dock_now, "dock_ms": float(dock_last_usec) / 1000.0 if dock_now else 0.0
 })
