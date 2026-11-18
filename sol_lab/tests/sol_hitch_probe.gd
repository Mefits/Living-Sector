extends SceneTree
## Real-frame probe on ONE scene, modes x1, x16, pause.
const TraceUI = preload("res://tests/sol_hitch_trace_ui.gd")
const CAPTURE_SECONDS := 4.0

func _initialize() -> void:
 call_deferred("_run_probe")

func _median(values: Array[float]) -> float:
 if values.is_empty():
  return 0.0
 values.sort()
 return values[values.size() / 2]

func _p95(values: Array[float]) -> float:
 if values.is_empty():
  return 0.0
 values.sort()
 return values[mini(values.size() - 1, ceili(float(values.size()) * 0.95) - 1)]

func _report(label: String, samples: Array[Dictionary]) -> void:
 var frame_ms: Array[float] = []
 var process_ms: Array[float] = []
 var perf_times: Array[float] = []
 var map_times: Array[float] = []
 var panel_times: Array[float] = []
 var dock_times: Array[float] = []
 for row in samples:
  frame_ms.append(float(row["dt_ms"]))
  process_ms.append(float(row["process_ms"]))
  if row["perf"]:
   perf_times.append(float(row["perf_ms"]))
  if row["map"]:
   map_times.append(float(row["map_ms"]))
  if row["panel"]:
   panel_times.append(float(row["panel_ms"]))
  if row["dock"]:
   dock_times.append(float(row["dock_ms"]))
 var biggest_dt: Array[Dictionary] = samples.duplicate()
 biggest_dt.sort_custom(func(a: Dictionary, b: Dictionary)->bool:
  return float(a["dt_ms"]) > float(b["dt_ms"]))
 var biggest_cpu: Array[Dictionary] = samples.duplicate()
 biggest_cpu.sort_custom(func(a: Dictionary, b: Dictionary)->bool:
  return float(a["process_ms"]) > float(b["process_ms"]))
 print("SOL_HITCH_MODE ", label, " ", JSON.stringify({
  "frames":samples.size(),
  "frame_median_ms":_median(frame_ms),
  "frame_p95_ms":_p95(frame_ms),
  "frame_max_ms":biggest_dt[0]["dt_ms"] if not biggest_dt.is_empty() else 0,
  "cpu_median_ms":_median(process_ms),
  "cpu_p95_ms":_p95(process_ms),
  "cpu_max_ms":biggest_cpu[0]["process_ms"] if not biggest_cpu.is_empty() else 0,
  "perf_events":perf_times.size(), "perf_max_ms":perf_times.max() if not perf_times.is_empty() else 0,
  "map_events":map_times.size(), "map_max_ms":map_times.max() if not map_times.is_empty() else 0,
  "panel_events":panel_times.size(), "panel_max_ms":panel_times.max() if not panel_times.is_empty() else 0,
  "dock_events":dock_times.size(), "dock_max_ms":dock_times.max() if not dock_times.is_empty() else 0,
  "top_frame":biggest_dt.slice(0, 6),
  "top_cpu":biggest_cpu.slice(0, 6)
 }))

func _run_probe() -> void:
 Engine.max_fps = 60
 root.size = Vector2i(1366, 768)
 var scene = TraceUI.new()
 root.add_child(scene)
 scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await create_timer(1.5).timeout
 # First, the selected-planet sidebar; then an OPEN construction
 # dock with one active site (the periodic 0.5s refresh path).
 for scenario in ["selected", "construction"]:
  if scenario == "construction":
   scene.paused = false
   scene.visual_clock.set_paused(false)
   var order: Dictionary = scene.construction.order("earth", "mining_rig")
   if not bool(order.get("ok", false)):
    push_error("SOL_HITCH_PROBE_SETUP_FAIL: " + str(order))
    quit(1)
    return
   scene._open_build()
   scene._refresh_construction_ui()
  for mode in ["x1", "x16", "pause"]:
   scene.measuring = false
   scene.samples.clear()
   scene.paused = mode == "pause"
   scene.visual_clock.set_paused(scene.paused)
   scene._set_speed(16 if mode == "x16" else 1)
   await create_timer(0.3).timeout
   scene.measuring = true
   await create_timer(CAPTURE_SECONDS).timeout
   scene.measuring = false
   _report(scenario + "/" + mode, scene.samples)
 scene.queue_free()
 Engine.max_fps = 0
 print("SOL_HITCH_PROBE_PASS")
 quit(0)
