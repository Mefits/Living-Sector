extends SceneTree
## Verify Sol Lab visual commits follow 8 TPS, not an aliased 10Hz poll.
## Actual 60Hz Godot rendering, no gameplay/save mutations.
const Lab = preload("res://scripts/main.gd")

func _initialize() -> void:
 call_deferred("_check")

func _check() -> void:
 var original_fps: int = Engine.max_fps
 Engine.max_fps = 60
 root.size = Vector2i(1366, 768)
 var ui = Lab.new()
 root.add_child(ui)
 ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await process_frame
 if ui.native_view == null:
  push_error("SOL_MOTION_ALIGNMENT_FAIL: no map")
  Engine.max_fps = original_fps
  quit(1)
  return
 var map = ui.native_view
 map._zoom = 1.0
 map._pan = Vector2.ZERO
 map._focused_body_id = ""
 map._return_camera = false
 ui._set_speed(16)
 ui.paused = false
 ui.visual_clock.set_paused(false)
 await create_timer(0.5).timeout

 var commits: int = 0
 var max_commit_gap_ms: float = 0.0
 var prev_angle: float = float(map._body_by_id("earth").get("current_angle", 0.0))
 var prev_commit_usec: int = -1
 var begin_usec: int = Time.get_ticks_usec()
 while Time.get_ticks_usec() - begin_usec < 4000000:
  await process_frame
  var angle: float = float(map._body_by_id("earth").get("current_angle", 0.0))
  if not is_equal_approx(angle, prev_angle):
   var now_usec: int = Time.get_ticks_usec()
   commits += 1
   if prev_commit_usec >= 0:
    max_commit_gap_ms = maxf(max_commit_gap_ms,
     float(now_usec - prev_commit_usec) / 1000.0)
   prev_commit_usec = now_usec
   prev_angle = angle

 ui.queue_free()
 Engine.max_fps = original_fps
 print("SOL_MOTION_ALIGNMENT_RESULT ", JSON.stringify({
  "commits": commits, "max_commit_gap_ms": max_commit_gap_ms
 }))
 # At 8 TPS, 4s should generate ~32 commits with modest frame jitter.
 # The old 10Hz poll produced regular ~200ms gaps, which must disappear.
 if commits >= 25 and commits <= 37 and max_commit_gap_ms < 180.0:
  print("SOL_MOTION_ALIGNMENT_PASS")
  quit(0)
 else:
  push_error("SOL_MOTION_ALIGNMENT_FAIL: aliased source cadence")
  quit(1)
