extends SceneTree
## Windows-only 30s visual-motion capture. No gameplay code is modified.
## Captures the actual position used by StarSystemView._draw(), and the
## post-draw frame timestamp on ONE timeline. Nothing is written during
## capture; the CSV is flushed only once after the complete 30s window.
const Lab = preload("res://scripts/main.gd")
const Interp = preload("res://scripts/ui_source_motion_interpolator.gd")
const BODY_ID := "earth"
const DURATION_USEC: int = 30000000
const OUTPUT_PATH := "res://sol-motion-30s.csv"

func _initialize() -> void:
 call_deferred("_capture")

func _capture() -> void:
 var original_fps: int = Engine.max_fps
 Engine.max_fps = 60
 root.size = Vector2i(1366, 768)
 var ui = Lab.new()
 root.add_child(ui)
 ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await process_frame
 var map = ui.native_view
 if map == null or map._body_by_id(BODY_ID).is_empty():
  push_error("SOL_MOTION_FAIL: no visible Earth map body")
  Engine.max_fps = original_fps
  quit(1)
  return

 # The real Sol Lab camera, fixed at the default overview zoom.
 # Earth stays entirely visible. No camera follow, panning or zoom animation.
 map._zoom = 1.0
 map._pan = Vector2.ZERO
 map._focused_body_id = ""
 map._zoom_candidate_body_id = ""
 map._focus_zoom_target = -1.0
 map._wheel_target_zoom = -1.0
 map._return_camera = false
 map._follow_orbit_valid = false
 map.queue_redraw()
 ui._set_speed(16)
 ui.paused = false
 ui.visual_clock.set_paused(false)

 # Stabilize initial draw, clock and shader caches before recording.
 await create_timer(1.5).timeout
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_title("Sol Lab · Earth motion trace (30 seconds)")
 var rows: Array[PackedFloat64Array] = []
 var begin_usec: int = Time.get_ticks_usec()
 var last_usec: int = -1
 var last_position: Vector2 = Vector2.ZERO
 var previous_draws: int = -1
 while Time.get_ticks_usec() - begin_usec < DURATION_USEC:
  await RenderingServer.frame_post_draw
  var now_usec: int = Time.get_ticks_usec()
  var position: Variant = map._draw_body_positions.get(BODY_ID, null)
  if not (position is Vector2):
   continue
  var draw_usec: int = int(map._draw_now_usec)
  var draw_calls: int = int(map._draw_calls)
  var source: Dictionary = map._body_by_id(BODY_ID)
  var interpolation: float = Interp.alpha(
   int(map._body_motion_started_usec),
   int(map._body_motion_duration_usec), draw_usec)
  if last_usec >= 0:
   var elapsed_ms: float = float(now_usec - begin_usec) / 1000.0
   var frame_ms: float = float(now_usec - last_usec) / 1000.0
   var step_px: float = (position as Vector2).distance_to(last_position)
   var cpu_ms: float = 0.0
   if not ui.frame_profiler._process_us.is_empty():
    cpu_ms = float(ui.frame_profiler._process_us.back()) / 1000.0
   rows.append(PackedFloat64Array([
    float(rows.size() + 1), elapsed_ms, frame_ms,
    position.x, position.y, step_px,
    float(draw_calls), float(int(draw_calls != previous_draws)),
    float(now_usec - draw_usec) / 1000.0,
    ui.native_time, float(source.get("current_angle", 0.0)),
    map._visual_body_angle(source, draw_usec), interpolation,
    float(now_usec - int(map._last_body_commit_usec)) / 1000.0,
    cpu_ms, map._zoom, map._pan.x, map._pan.y
   ]))
  last_usec = now_usec
  last_position = position
  previous_draws = draw_calls

 # Only now write to disk. No logging/CSV file writes during capture.
 var output: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
 if output == null:
  push_error("SOL_MOTION_FAIL: cannot open CSV, error %d" %
   FileAccess.get_open_error())
  Engine.max_fps = original_fps
  quit(1)
  return
 output.store_line("frame,t_ms,frame_dt_ms,x_px,y_px,step_px," +
  "draw_seq,new_draw,draw_age_ms,native_time,source_angle_deg," +
  "draw_angle_deg,interp_alpha,source_age_ms,cpu_process_ms," +
  "zoom,pan_x,pan_y")
 var max_dt: float = 0.0
 var max_step: float = 0.0
 var slow_frames: int = 0
 var flat_frames: int = 0
 var normal_time_jumps: int = 0
 var new_draws: int = 0
 for row in rows:
  var fields := PackedStringArray()
  for value in row:
   fields.append("%.5f" % float(value))
  output.store_line(",".join(fields))
  var dt: float = row[2]
  var step: float = row[5]
  max_dt = maxf(max_dt, dt)
  max_step = maxf(max_step, step)
  if dt >= 25.0:
   slow_frames += 1
  if dt >= 12.0 and dt <= 20.0 and step < 0.02:
   flat_frames += 1
  if dt >= 12.0 and dt <= 20.0 and step > 1.5:
   normal_time_jumps += 1
  new_draws += int(row[7])
 output.close()
 print("SOL_MOTION_RESULT ", JSON.stringify({
  "body": BODY_ID, "speed": 16,
  "seconds": 30, "frames": rows.size(),
  "new_draws": new_draws, "max_frame_dt_ms": max_dt,
  "frames_over_25ms": slow_frames, "max_step_px": max_step,
  "flat_frames_normal_dt": flat_frames,
  "jumps_over_1_5px_normal_dt": normal_time_jumps,
  "csv": ProjectSettings.globalize_path(OUTPUT_PATH),
  "vsync": DisplayServer.window_get_vsync_mode()
 }))
 Engine.max_fps = original_fps
 ui.queue_free()
 print("SOL_MOTION_TRACE_PASS")
 quit(0)
