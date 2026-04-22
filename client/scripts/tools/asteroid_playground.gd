extends Node3D

## Standalone scene for iterating on procedural asteroids. Same shape as
## the planet playground — programmatic UI on the right, orbit camera on
## the 3D view. Run `scenes/tools/asteroid_playground.tscn`.
##
## Controls:
##   - Left-drag: orbit camera.
##   - Wheel: zoom.
##   - Right panel: all asteroid params. "Randomize" picks a new seed;
##     "Copy config" dumps JSON to stdout + clipboard.

const ProceduralAsteroidScript := preload(
  "res://scripts/tools/procedural_asteroid.gd"
)

const ORBIT_SENSITIVITY := 0.005
const ZOOM_MIN := 1.5
const ZOOM_MAX := 20.0
const ZOOM_STEP := 0.9

var asteroid: ProceduralAsteroid
var camera_rig: Node3D
var camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = -0.25
var _zoom: float = 4.0
var _dragging := false

var _seed_spin: SpinBox
var _controls: Dictionary = {}  # prop_name -> Control


func _ready() -> void:
  _build_world()
  _build_ui()
  _update_camera()


# ---------------------------------------------------------------------------
# World
# ---------------------------------------------------------------------------

func _build_world() -> void:
  var env := WorldEnvironment.new()
  var e := Environment.new()
  e.background_mode = Environment.BG_COLOR
  e.background_color = Color(0.02, 0.02, 0.05)
  e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
  e.ambient_light_color = Color(1, 1, 1)
  e.ambient_light_energy = 0.15
  e.glow_enabled = true
  e.glow_intensity = 1.0
  e.glow_hdr_threshold = 1.0
  env.environment = e
  add_child(env)

  var key := DirectionalLight3D.new()
  key.rotation_degrees = Vector3(-45, 35, 0)
  key.light_energy = 1.4
  add_child(key)

  var fill := DirectionalLight3D.new()
  fill.rotation_degrees = Vector3(-10, -120, 0)
  fill.light_energy = 0.30
  fill.light_color = Color(0.7, 0.8, 1.0)
  add_child(fill)

  asteroid = ProceduralAsteroidScript.new()
  asteroid.name = "Asteroid"
  add_child(asteroid)

  camera_rig = Node3D.new()
  camera_rig.name = "CameraRig"
  add_child(camera_rig)
  camera = Camera3D.new()
  camera.position = Vector3(0, 0, _zoom)
  camera.current = true
  camera_rig.add_child(camera)


func _update_camera() -> void:
  camera_rig.rotation = Vector3(_pitch, _yaw, 0.0)
  camera.position = Vector3(0, 0, _zoom)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    if _is_over_ui(mb.position):
      return
    if mb.button_index == MOUSE_BUTTON_LEFT:
      _dragging = mb.pressed
    elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
      _zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
      _update_camera()
    elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
      _zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
      _update_camera()
  elif event is InputEventMouseMotion and _dragging:
    var mm := event as InputEventMouseMotion
    _yaw -= mm.relative.x * ORBIT_SENSITIVITY
    _pitch = clampf(
      _pitch - mm.relative.y * ORBIT_SENSITIVITY,
      -PI * 0.49, PI * 0.49
    )
    _update_camera()


func _is_over_ui(pos: Vector2) -> bool:
  var vp := get_viewport().get_visible_rect().size
  return pos.x >= vp.x - 380.0


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
  var layer := CanvasLayer.new()
  add_child(layer)

  var panel := PanelContainer.new()
  panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
  panel.custom_minimum_size = Vector2(380, 0)
  panel.offset_left = -380
  layer.add_child(panel)

  var scroll := ScrollContainer.new()
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  panel.add_child(scroll)

  var vbox := VBoxContainer.new()
  vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  vbox.add_theme_constant_override("separation", 6)
  scroll.add_child(vbox)

  var title := Label.new()
  title.text = "Asteroid Playground"
  title.add_theme_font_size_override("font_size", 20)
  vbox.add_child(title)
  var hint := Label.new()
  hint.text = "Left-drag: orbit · Wheel: zoom"
  hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
  vbox.add_child(hint)

  vbox.add_child(HSeparator.new())

  # Seed row
  var seed_row := HBoxContainer.new()
  _seed_spin = SpinBox.new()
  _seed_spin.min_value = 0
  _seed_spin.max_value = 9_999_999
  _seed_spin.step = 1
  _seed_spin.value = asteroid.asteroid_seed
  _seed_spin.value_changed.connect(
    func(v): asteroid.asteroid_seed = int(v)
  )
  _seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  seed_row.add_child(_seed_spin)
  var rand_btn := Button.new()
  rand_btn.text = "🎲"
  rand_btn.pressed.connect(_on_randomize)
  seed_row.add_child(rand_btn)
  _add_row(vbox, "Seed", seed_row)

  _add_section(vbox, "Shape")
  _add_int(vbox, "radial_segments", 6, 32, 1)
  _add_int(vbox, "rings", 4, 16, 1)
  _add_float(vbox, "base_radius", 0.1, 3.0, 0.01)
  _add_float(vbox, "deformation", 0.0, 0.8, 0.01)
  _add_float(vbox, "deform_frequency", 0.3, 8.0, 0.01)
  _add_int(vbox, "deform_octaves", 1, 5, 1)
  _add_vec3(vbox, "squash", 0.3, 2.0, 0.01)

  _add_section(vbox, "Palette")
  _add_color(vbox, "color_low")
  _add_color(vbox, "color_mid")
  _add_color(vbox, "color_high")

  _add_section(vbox, "Surface")
  _add_float(vbox, "noise_frequency", 0.1, 12.0, 0.01)
  _add_int(vbox, "noise_octaves", 1, 6, 1)
  _add_float(vbox, "noise_warp", 0.0, 2.0, 0.01)
  _add_float(vbox, "roughness", 0.0, 1.0, 0.01)
  _add_float(vbox, "metallic", 0.0, 1.0, 0.01)

  _add_section(vbox, "Tumble")
  _add_vec3(vbox, "tumble", -2.0, 2.0, 0.01)

  vbox.add_child(HSeparator.new())
  var copy_btn := Button.new()
  copy_btn.text = "Copy config to stdout"
  copy_btn.pressed.connect(_on_copy_config)
  vbox.add_child(copy_btn)


func _add_section(parent: Container, text: String) -> void:
  parent.add_child(HSeparator.new())
  var l := Label.new()
  l.text = text
  l.add_theme_font_size_override("font_size", 14)
  l.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
  parent.add_child(l)


func _add_row(parent: Container, label_text: String, ctrl: Control) -> void:
  var row := HBoxContainer.new()
  var lbl := Label.new()
  lbl.text = label_text
  lbl.custom_minimum_size = Vector2(140, 0)
  row.add_child(lbl)
  ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(ctrl)
  parent.add_child(row)


func _add_float(
  parent: Container, prop: String,
  lo: float, hi: float, step: float
) -> void:
  var row := HBoxContainer.new()
  var slider := HSlider.new()
  slider.min_value = lo
  slider.max_value = hi
  slider.step = step
  slider.value = asteroid.get(prop)
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  var value_label := Label.new()
  value_label.text = "%.3f" % slider.value
  value_label.custom_minimum_size = Vector2(60, 0)
  value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
  slider.value_changed.connect(func(v: float):
    asteroid.set(prop, v)
    value_label.text = "%.3f" % v
  )
  row.add_child(slider)
  row.add_child(value_label)
  _add_row(parent, prop, row)
  _controls[prop] = slider


func _add_int(
  parent: Container, prop: String, lo: int, hi: int, step: int
) -> void:
  var spin := SpinBox.new()
  spin.min_value = lo
  spin.max_value = hi
  spin.step = step
  spin.value = asteroid.get(prop)
  spin.value_changed.connect(func(v: float):
    asteroid.set(prop, int(v))
  )
  _add_row(parent, prop, spin)
  _controls[prop] = spin


func _add_color(parent: Container, prop: String) -> void:
  var picker := ColorPickerButton.new()
  picker.color = asteroid.get(prop)
  picker.custom_minimum_size = Vector2(0, 28)
  picker.color_changed.connect(func(c: Color):
    asteroid.set(prop, c)
  )
  _add_row(parent, prop, picker)
  _controls[prop] = picker


func _add_vec3(
  parent: Container, prop: String,
  lo: float, hi: float, step: float
) -> void:
  ## Three linked sliders (x/y/z) that write back as a Vector3. Use
  ## `.bind(prop, axis, label)` rather than closure capture — the loop
  ## variable `i` would late-bind in GDScript, and all three callbacks
  ## would write the same axis.
  var row := VBoxContainer.new()
  row.add_theme_constant_override("separation", 2)
  var cur: Vector3 = asteroid.get(prop)
  var sliders := [null, null, null]
  for i in range(3):
    var axis_row := HBoxContainer.new()
    var axis_label := Label.new()
    axis_label.text = ["x:", "y:", "z:"][i]
    axis_label.custom_minimum_size = Vector2(20, 0)
    axis_row.add_child(axis_label)
    var slider := HSlider.new()
    slider.min_value = lo
    slider.max_value = hi
    slider.step = step
    slider.value = [cur.x, cur.y, cur.z][i]
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var val_lbl := Label.new()
    val_lbl.text = "%.2f" % slider.value
    val_lbl.custom_minimum_size = Vector2(50, 0)
    val_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
    slider.value_changed.connect(
      _on_vec3_axis_changed.bind(prop, i, val_lbl)
    )
    sliders[i] = slider
    axis_row.add_child(slider)
    axis_row.add_child(val_lbl)
    row.add_child(axis_row)
  _add_row(parent, prop, row)
  _controls[prop] = sliders


func _on_vec3_axis_changed(
  v: float, prop: String, axis: int, val_lbl: Label
) -> void:
  var c: Vector3 = asteroid.get(prop)
  match axis:
    0: c.x = v
    1: c.y = v
    2: c.z = v
  asteroid.set(prop, c)
  val_lbl.text = "%.2f" % v


func _on_randomize() -> void:
  var s := randi() % 10_000_000
  asteroid.asteroid_seed = s
  _seed_spin.set_value_no_signal(s)


func _on_copy_config() -> void:
  var cfg := asteroid.to_config()
  var text := JSON.stringify(cfg, "  ")
  print("[asteroid_playground] config:")
  print(text)
  DisplayServer.clipboard_set(text)
