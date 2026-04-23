extends Node3D

## Standalone scene for iterating on procedural nebulas. Same shape as
## the planet / asteroid / ship playgrounds. Run
## `scenes/tools/nebula_playground.tscn`.
##
## Presets let you snap between "Emission" (bright purple/pink HII),
## "Reflection" (cool blue scattered light), "Planetary" (green/red
## shell), and "Dark" (dusty orange/brown).

const ProceduralNebulaScript := preload(
  "res://scripts/tools/procedural_nebula.gd"
)

const ORBIT_SENSITIVITY := 0.005
const ZOOM_MIN := 1.0
const ZOOM_MAX := 60.0
const ZOOM_STEP := 0.9

var nebula: ProceduralNebula
var camera_rig: Node3D
var camera: Camera3D
var _yaw: float = 0.5
var _pitch: float = -0.20
var _zoom: float = 10.0
var _dragging := false

var _seed_spin: SpinBox
var _preset_opt: OptionButton
var _controls: Dictionary = {}
var _syncing: bool = false

# Palette presets — seed your creativity. Users tweak sliders after.
const PRESETS := {
  "Emission": {
    "primary_color": Color(0.92, 0.30, 0.55),
    "secondary_color": Color(0.45, 0.20, 0.85),
    "density": 1.0,
    "brightness": 2.0,
    "noise_frequency": 1.5,
    "noise_warp": 0.85,
    "wisp_strength": 1.0,
    "radial_falloff": 2.4,
    "density_threshold": 0.12,
    "color_mix_shift": 0.55,
    "color_mix_band": 0.22,
  },
  "Reflection": {
    "primary_color": Color(0.30, 0.55, 1.00),
    "secondary_color": Color(0.75, 0.88, 1.00),
    "density": 0.8,
    "brightness": 1.5,
    "noise_frequency": 1.8,
    "noise_warp": 1.1,
    "wisp_strength": 0.7,
    "radial_falloff": 2.8,
    "density_threshold": 0.15,
    "color_mix_shift": 0.45,
    "color_mix_band": 0.25,
  },
  "Planetary": {
    "primary_color": Color(0.40, 0.95, 0.55),
    "secondary_color": Color(0.95, 0.35, 0.25),
    "density": 1.2,
    "brightness": 2.3,
    "noise_frequency": 2.4,
    "noise_warp": 0.5,
    "wisp_strength": 1.4,
    "radial_falloff": 3.5,   # tighter shell
    "density_threshold": 0.05,
    "color_mix_shift": 0.5,
    "color_mix_band": 0.18,
  },
  "Dark": {
    "primary_color": Color(0.55, 0.30, 0.15),
    "secondary_color": Color(0.18, 0.10, 0.08),
    "density": 1.5,
    "brightness": 0.9,
    "noise_frequency": 1.2,
    "noise_warp": 1.4,
    "wisp_strength": 0.6,
    "radial_falloff": 2.0,
    "density_threshold": 0.25,
    "color_mix_shift": 0.42,
    "color_mix_band": 0.30,
  },
}


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
  e.background_color = Color(0.01, 0.01, 0.03)
  e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
  e.ambient_light_color = Color(1, 1, 1)
  e.ambient_light_energy = 0.1
  # Glow so emission-heavy nebulas actually bloom.
  e.glow_enabled = true
  e.glow_intensity = 1.0
  e.glow_strength = 1.1
  e.glow_bloom = 0.2
  e.glow_hdr_threshold = 0.8
  e.glow_hdr_scale = 2.5
  env.environment = e
  add_child(env)

  nebula = ProceduralNebulaScript.new()
  nebula.name = "Nebula"
  add_child(nebula)

  camera_rig = Node3D.new()
  camera_rig.name = "CameraRig"
  add_child(camera_rig)
  camera = Camera3D.new()
  camera.position = Vector3(0, 0, _zoom)
  camera.current = true
  camera.fov = 50.0
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
  vbox.add_theme_constant_override(&"separation", 6)
  scroll.add_child(vbox)

  var title := Label.new()
  title.text = "Nebula Playground"
  title.add_theme_font_size_override(&"font_size", 20)
  vbox.add_child(title)
  var hint := Label.new()
  hint.text = "Left-drag: orbit · Wheel: zoom"
  hint.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
  vbox.add_child(hint)
  vbox.add_child(HSeparator.new())

  _preset_opt = OptionButton.new()
  var idx := 0
  for name in PRESETS.keys():
    _preset_opt.add_item(String(name), idx)
    idx += 1
  _preset_opt.item_selected.connect(_on_preset_selected)
  _add_row(vbox, "Preset", _preset_opt)

  var seed_row := HBoxContainer.new()
  _seed_spin = SpinBox.new()
  _seed_spin.min_value = 0
  _seed_spin.max_value = 9_999_999
  _seed_spin.step = 1
  _seed_spin.value = nebula.nebula_seed
  _seed_spin.value_changed.connect(
    func(v): nebula.nebula_seed = int(v)
  )
  _seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  seed_row.add_child(_seed_spin)
  var rand_btn := Button.new()
  rand_btn.text = "🎲"
  rand_btn.pressed.connect(_on_randomize)
  seed_row.add_child(rand_btn)
  _add_row(vbox, "Seed", seed_row)

  _add_section(vbox, "Shape")
  _add_float(vbox, "radius", 0.5, 20.0, 0.1)
  _add_int(vbox, "mesh_segments", 8, 48, 1)
  _add_vec3(vbox, "shape_scale", 0.2, 2.5, 0.01)

  _add_section(vbox, "Palette")
  _add_color(vbox, "primary_color")
  _add_color(vbox, "secondary_color")
  _add_float(vbox, "color_mix_shift", 0.0, 1.0, 0.01)
  _add_float(vbox, "color_mix_band", 0.05, 0.5, 0.01)

  _add_section(vbox, "Noise")
  _add_float(vbox, "density", 0.0, 3.0, 0.01)
  _add_float(vbox, "brightness", 0.0, 6.0, 0.01)
  _add_float(vbox, "noise_frequency", 0.1, 8.0, 0.01)
  _add_int(vbox, "noise_octaves", 1, 6, 1)
  _add_float(vbox, "noise_warp", 0.0, 2.0, 0.01)
  _add_float(vbox, "wisp_strength", 0.0, 2.0, 0.01)
  _add_float(vbox, "radial_falloff", 0.3, 8.0, 0.01)
  _add_float(vbox, "density_threshold", 0.0, 0.8, 0.01)

  _add_section(vbox, "Tumble")
  _add_vec3(vbox, "tumble", -0.5, 0.5, 0.005)

  vbox.add_child(HSeparator.new())
  var copy_btn := Button.new()
  copy_btn.text = "Copy config to stdout"
  copy_btn.pressed.connect(_on_copy_config)
  vbox.add_child(copy_btn)


func _add_section(parent: Container, text: String) -> void:
  parent.add_child(HSeparator.new())
  var l := Label.new()
  l.text = text
  l.add_theme_font_size_override(&"font_size", 14)
  l.add_theme_color_override(&"font_color", Color(0.75, 0.85, 1.0))
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
  slider.value = nebula.get(prop)
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  var value_label := Label.new()
  value_label.text = "%.3f" % slider.value
  value_label.custom_minimum_size = Vector2(60, 0)
  value_label.add_theme_color_override(
    &"font_color", Color(0.9, 0.9, 0.5)
  )
  slider.value_changed.connect(func(v: float):
    nebula.set(prop, v)
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
  spin.value = nebula.get(prop)
  spin.value_changed.connect(func(v: float): nebula.set(prop, int(v)))
  _add_row(parent, prop, spin)
  _controls[prop] = spin


func _add_color(parent: Container, prop: String) -> void:
  var picker := ColorPickerButton.new()
  picker.color = nebula.get(prop)
  picker.custom_minimum_size = Vector2(0, 28)
  picker.color_changed.connect(func(c: Color): nebula.set(prop, c))
  _add_row(parent, prop, picker)
  _controls[prop] = picker


func _add_vec3(
  parent: Container, prop: String,
  lo: float, hi: float, step: float
) -> void:
  var row := VBoxContainer.new()
  row.add_theme_constant_override(&"separation", 2)
  var cur: Vector3 = nebula.get(prop)
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
    val_lbl.text = "%.3f" % slider.value
    val_lbl.custom_minimum_size = Vector2(50, 0)
    val_lbl.add_theme_color_override(
      &"font_color", Color(0.9, 0.9, 0.5)
    )
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
  var c: Vector3 = nebula.get(prop)
  match axis:
    0: c.x = v
    1: c.y = v
    2: c.z = v
  nebula.set(prop, c)
  val_lbl.text = "%.3f" % v


func _on_preset_selected(idx: int) -> void:
  var preset_name: String = PRESETS.keys()[idx]
  var cfg: Dictionary = PRESETS[preset_name]
  _syncing = true
  for key in cfg.keys():
    nebula.set(key, cfg[key])
    _sync_control(key)
  _syncing = false


func _sync_control(prop: String) -> void:
  if not _controls.has(prop):
    return
  var ctrl: Variant = _controls[prop]
  var val: Variant = nebula.get(prop)
  if ctrl is HSlider:
    (ctrl as HSlider).set_value_no_signal(float(val))
    var row := (ctrl as Control).get_parent() as HBoxContainer
    if row and row.get_child_count() >= 2:
      var rl := row.get_child(1) as Label
      if rl: rl.text = "%.3f" % float(val)
  elif ctrl is SpinBox:
    (ctrl as SpinBox).set_value_no_signal(float(val))
  elif ctrl is ColorPickerButton:
    (ctrl as ColorPickerButton).color = val


func _on_randomize() -> void:
  var s := randi() % 10_000_000
  nebula.nebula_seed = s
  _seed_spin.set_value_no_signal(s)


func _on_copy_config() -> void:
  var cfg := nebula.to_config()
  var text := JSON.stringify(cfg, "  ")
  print("[nebula_playground] config:")
  print(text)
  DisplayServer.clipboard_set(text)
