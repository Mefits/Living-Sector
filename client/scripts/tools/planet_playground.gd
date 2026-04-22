extends Node3D

## Standalone scene for iterating on procedural planets. All UI is built
## programmatically so tweaking controls is a one-file edit. Run
## `scenes/tools/planet_playground.tscn` from the editor.
##
## Controls:
##   - Left-drag on the 3D view: orbit camera.
##   - Mouse wheel: zoom.
##   - Inspector panel (right side): all planet params live.
##   - "Randomize seed" rerolls; "Copy config" dumps JSON to stdout.

const ProceduralPlanetScript := preload(
  "res://scripts/tools/procedural_planet.gd"
)

const ORBIT_SENSITIVITY := 0.005
const ZOOM_MIN := 1.5
const ZOOM_MAX := 20.0
const ZOOM_STEP := 0.9

var planet: ProceduralPlanet
var camera_rig: Node3D
var camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = -0.25
var _zoom: float = 4.0
var _dragging := false

# UI refs populated by `_build_ui`
var _preset_opt: OptionButton
var _seed_spin: SpinBox
var _ring_count_spin: SpinBox
var _rings_ui_container: VBoxContainer
var _controls: Dictionary = {}  # prop_name -> Control
# While true, UI→planet callbacks skip the "drop preset to CUSTOM" side
# effect. Needed because ColorPickerButton has no set_color_no_signal, so
# sync after a preset change would otherwise fire color_changed and clobber
# the preset label.
var _syncing: bool = false


func _ready() -> void:
  _build_world()
  _build_ui()
  _update_camera()
  _sync_ui_from_planet()


# ---------------------------------------------------------------------------
# World setup
# ---------------------------------------------------------------------------

func _build_world() -> void:
  var env := WorldEnvironment.new()
  var e := Environment.new()
  e.background_mode = Environment.BG_COLOR
  e.background_color = Color(0.02, 0.02, 0.05)
  e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
  e.ambient_light_color = Color(1, 1, 1)
  e.ambient_light_energy = 0.15
  # Match the main scene so emissive knobs (lava, industrial glow, clouds)
  # preview with the same bloom intensity here as they get in-game.
  e.glow_enabled = true
  e.glow_intensity = 1.2
  e.glow_strength = 1.1
  e.glow_bloom = 0.15
  e.glow_hdr_threshold = 1.0
  e.glow_hdr_scale = 2.5
  env.environment = e
  add_child(env)

  var key := DirectionalLight3D.new()
  key.name = "KeyLight"
  key.rotation_degrees = Vector3(-45, 35, 0)
  key.light_energy = 1.2
  add_child(key)

  var fill := DirectionalLight3D.new()
  fill.name = "FillLight"
  fill.rotation_degrees = Vector3(-10, -120, 0)
  fill.light_energy = 0.25
  fill.light_color = Color(0.7, 0.8, 1.0)
  add_child(fill)

  planet = ProceduralPlanetScript.new()
  planet.name = "Planet"
  # Connect before add_child so we don't miss the _ready-time emit.
  planet.rings_changed.connect(_rebuild_rings_ui)
  add_child(planet)

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
# Input (orbit + zoom)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
  if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    # Only hijack mouse if click lands on the 3D view, not UI.
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
  # Right-side panel reserves the last N pixels of the viewport.
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

  # Header
  var title := Label.new()
  title.text = "Planet Playground"
  title.add_theme_font_size_override("font_size", 20)
  vbox.add_child(title)

  var hint := Label.new()
  hint.text = "Left-drag: orbit · Wheel: zoom"
  hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
  vbox.add_child(hint)

  vbox.add_child(HSeparator.new())

  # Preset
  _preset_opt = OptionButton.new()
  for k in ProceduralPlanet.Preset.keys():
    _preset_opt.add_item(String(k).capitalize(),
                         ProceduralPlanet.Preset[k])
  _preset_opt.select(_preset_opt.get_item_index(planet.preset))
  _preset_opt.item_selected.connect(_on_preset_selected)
  _add_row(vbox, "Preset", _preset_opt)

  # Seed row
  var seed_row := HBoxContainer.new()
  _seed_spin = SpinBox.new()
  _seed_spin.min_value = 0
  _seed_spin.max_value = 9_999_999
  _seed_spin.step = 1
  _seed_spin.value = planet.planet_seed
  _seed_spin.value_changed.connect(
    func(v): planet.planet_seed = int(v)
  )
  _seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  seed_row.add_child(_seed_spin)
  var rand_btn := Button.new()
  rand_btn.text = "🎲"
  rand_btn.pressed.connect(_on_randomize_seed)
  seed_row.add_child(rand_btn)
  _add_row(vbox, "Seed", seed_row)

  vbox.add_child(HSeparator.new())
  _add_section(vbox, "Geometry")
  _add_float(vbox, "radius", 0.1, 5.0, 0.01)
  _add_int(vbox, "radial_segments", 6, 64, 1)
  _add_int(vbox, "rings", 4, 32, 1)
  _add_float(vbox, "spin_speed", -2.0, 2.0, 0.01)

  _add_section(vbox, "Palette")
  _add_color(vbox, "color_low")
  _add_color(vbox, "color_mid")
  _add_color(vbox, "color_high")
  _add_color(vbox, "sea_color")
  _add_color(vbox, "pole_color")
  _add_color(vbox, "emission_color")

  _add_section(vbox, "Shape")
  _add_bool(vbox, "sea_enabled")
  _add_float(vbox, "sea_level", 0.0, 1.0, 0.01)
  _add_float(vbox, "pole_threshold", 0.0, 1.0, 0.01)
  _add_float(vbox, "pole_softness", 0.001, 0.5, 0.001)
  _add_float(vbox, "noise_frequency", 0.1, 12.0, 0.01)
  _add_int(vbox, "noise_octaves", 1, 6, 1)
  _add_float(vbox, "noise_lacunarity", 1.5, 3.5, 0.01)
  _add_float(vbox, "noise_gain", 0.2, 0.8, 0.01)
  _add_float(vbox, "noise_warp", 0.0, 2.0, 0.01)
  _add_float(vbox, "band_strength", 0.0, 1.0, 0.01)

  _add_section(vbox, "Emission & Surface")
  _add_float(vbox, "emission_strength", 0.0, 4.0, 0.01)
  _add_float(vbox, "emission_cutoff", 0.0, 1.0, 0.01)
  _add_bool(vbox, "flat_shading")
  _add_float(vbox, "roughness", 0.0, 1.0, 0.01)
  _add_float(vbox, "metallic", 0.0, 1.0, 0.01)

  _add_section(vbox, "Clouds")
  _add_bool(vbox, "cloud_enabled")
  _add_color(vbox, "cloud_color")
  _add_float(vbox, "cloud_opacity", 0.0, 1.0, 0.01)
  _add_float(vbox, "cloud_coverage", 0.0, 1.0, 0.01)
  _add_float(vbox, "cloud_softness", 0.001, 0.5, 0.001)
  _add_float(vbox, "cloud_frequency", 0.1, 12.0, 0.01)
  _add_int(vbox, "cloud_octaves", 1, 6, 1)
  _add_float(vbox, "cloud_height", 1.001, 1.3, 0.001)
  _add_float(vbox, "cloud_spin_speed", -2.0, 2.0, 0.01)

  _add_section(vbox, "Rings")
  _ring_count_spin = SpinBox.new()
  _ring_count_spin.min_value = 0
  _ring_count_spin.max_value = ProceduralPlanet.MAX_RINGS
  _ring_count_spin.step = 1
  _ring_count_spin.value = planet.ring_count
  _ring_count_spin.value_changed.connect(func(v: float):
    planet.ring_count = int(v)
    _rebuild_rings_ui()
  )
  _add_row(vbox, "Ring count", _ring_count_spin)

  _rings_ui_container = VBoxContainer.new()
  _rings_ui_container.add_theme_constant_override("separation", 4)
  vbox.add_child(_rings_ui_container)
  _rebuild_rings_ui()

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
  # Slider + readout, synced both ways. Pushing the slider calls the setter
  # on the planet node, which pushes to the shader.
  var row := HBoxContainer.new()
  var slider := HSlider.new()
  slider.min_value = lo
  slider.max_value = hi
  slider.step = step
  slider.value = planet.get(prop)
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

  var value_label := Label.new()
  value_label.text = "%.3f" % slider.value
  value_label.custom_minimum_size = Vector2(60, 0)
  value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))

  slider.value_changed.connect(func(v: float):
    planet.set(prop, v)
    value_label.text = "%.3f" % v
    if not _syncing:
      _preset_to_custom()
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
  spin.value = planet.get(prop)
  spin.value_changed.connect(func(v: float):
    planet.set(prop, int(v))
    if not _syncing:
      _preset_to_custom()
  )
  _add_row(parent, prop, spin)
  _controls[prop] = spin


func _add_bool(parent: Container, prop: String) -> void:
  var cb := CheckBox.new()
  cb.button_pressed = bool(planet.get(prop))
  cb.toggled.connect(func(on: bool):
    planet.set(prop, on)
    if not _syncing:
      _preset_to_custom()
  )
  _add_row(parent, prop, cb)
  _controls[prop] = cb


func _add_color(parent: Container, prop: String) -> void:
  var picker := ColorPickerButton.new()
  picker.color = planet.get(prop)
  picker.custom_minimum_size = Vector2(0, 28)
  picker.color_changed.connect(func(c: Color):
    planet.set(prop, c)
    if not _syncing:
      _preset_to_custom()
  )
  _add_row(parent, prop, picker)
  _controls[prop] = picker


func _sync_ui_from_planet() -> void:
  ## After a preset change, shove every planet property value back into the
  ## UI so sliders reflect reality.
  _syncing = true
  for prop in _controls.keys():
    var ctrl := _controls[prop] as Control
    var val: Variant = planet.get(prop)
    if ctrl is HSlider:
      (ctrl as HSlider).set_value_no_signal(float(val))
      # Refresh the readout label sibling
      var row := ctrl.get_parent() as HBoxContainer
      if row and row.get_child_count() >= 2:
        var rl := row.get_child(1) as Label
        if rl: rl.text = "%.3f" % float(val)
    elif ctrl is SpinBox:
      (ctrl as SpinBox).set_value_no_signal(float(val))
    elif ctrl is CheckBox:
      (ctrl as CheckBox).set_pressed_no_signal(bool(val))
    elif ctrl is ColorPickerButton:
      (ctrl as ColorPickerButton).color = val
  _syncing = false


func _preset_to_custom() -> void:
  # When user tweaks a raw uniform, drop the preset indicator to CUSTOM so
  # the UI doesn't lie about which preset is active. Use no_signal to avoid
  # re-entering _on_preset_selected.
  if planet.preset != ProceduralPlanet.Preset.CUSTOM:
    planet.preset = ProceduralPlanet.Preset.CUSTOM
  _preset_opt.select(
    _preset_opt.get_item_index(ProceduralPlanet.Preset.CUSTOM)
  )


# ---------------------------------------------------------------------------
# Rings UI
# ---------------------------------------------------------------------------

func _rebuild_rings_ui() -> void:
  ## Tear down every per-ring subsection and recreate for the current count.
  ## Cheap (N ≤ 4), and keeps the UI truthful when ring_count changes either
  ## from the spinbox or externally (presets, to_config round-trips).
  if not _rings_ui_container:
    return
  if _ring_count_spin and int(_ring_count_spin.value) != planet.ring_count:
    _ring_count_spin.set_value_no_signal(planet.ring_count)
  for c in _rings_ui_container.get_children():
    c.queue_free()
  for i in range(planet.ring_count):
    _build_ring_ui(_rings_ui_container, i)


func _build_ring_ui(parent: Container, index: int) -> void:
  var header := Label.new()
  header.text = "Ring %d" % (index + 1)
  header.add_theme_font_size_override("font_size", 13)
  header.add_theme_color_override("font_color", Color(0.8, 0.9, 0.6))
  parent.add_child(header)
  _add_ring_float(parent, index, "inner", 0.5, 4.0, 0.01)
  _add_ring_float(parent, index, "outer", 0.5, 4.0, 0.01)
  _add_ring_float(parent, index, "tilt_x", -90.0, 90.0, 0.5)
  _add_ring_float(parent, index, "tilt_z", -90.0, 90.0, 0.5)
  _add_ring_color(parent, index, "color")
  _add_ring_float(parent, index, "emission", 0.0, 2.0, 0.01)
  _add_ring_float(parent, index, "spin_speed", -2.0, 2.0, 0.01)
  _add_ring_int(parent, index, "segments", 12, 128, 1)


func _add_ring_float(
  parent: Container, index: int, key: String,
  lo: float, hi: float, step: float
) -> void:
  var row := HBoxContainer.new()
  var slider := HSlider.new()
  slider.min_value = lo
  slider.max_value = hi
  slider.step = step
  slider.value = float(planet.get_ring_param(index, key))
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  var value_label := Label.new()
  value_label.text = "%.3f" % slider.value
  value_label.custom_minimum_size = Vector2(60, 0)
  value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
  slider.value_changed.connect(func(v: float):
    planet.set_ring_param(index, key, v)
    value_label.text = "%.3f" % v
  )
  row.add_child(slider)
  row.add_child(value_label)
  _add_row(parent, key, row)


func _add_ring_int(
  parent: Container, index: int, key: String,
  lo: int, hi: int, step: int
) -> void:
  var spin := SpinBox.new()
  spin.min_value = lo
  spin.max_value = hi
  spin.step = step
  spin.value = int(planet.get_ring_param(index, key))
  spin.value_changed.connect(func(v: float):
    planet.set_ring_param(index, key, int(v))
  )
  _add_row(parent, key, spin)


func _add_ring_color(
  parent: Container, index: int, key: String
) -> void:
  var picker := ColorPickerButton.new()
  picker.edit_alpha = true
  picker.color = planet.get_ring_param(index, key)
  picker.custom_minimum_size = Vector2(0, 28)
  picker.color_changed.connect(func(c: Color):
    planet.set_ring_param(index, key, c)
  )
  _add_row(parent, key, picker)


# ---------------------------------------------------------------------------
# UI callbacks
# ---------------------------------------------------------------------------

func _on_preset_selected(idx: int) -> void:
  var id := _preset_opt.get_item_id(idx)
  planet.preset = id
  _sync_ui_from_planet()


func _on_randomize_seed() -> void:
  var new_seed := randi() % 10_000_000
  planet.planet_seed = new_seed
  _seed_spin.set_value_no_signal(new_seed)


func _on_copy_config() -> void:
  var cfg := planet.to_config()
  var text := JSON.stringify(cfg, "  ")
  print("[planet_playground] config:")
  print(text)
  DisplayServer.clipboard_set(text)
