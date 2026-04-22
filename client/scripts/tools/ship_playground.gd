extends Node3D

## Standalone scene for iterating on procedural ships. Matches the planet
## / asteroid playground shape — orbit camera on the 3D view, programmatic
## UI on the right. Run `scenes/tools/ship_playground.tscn`.
##
## Controls:
##   - Left-drag: orbit.  Wheel: zoom.
##   - Class / Faction dropdowns change silhouette + palette live.
##   - Seed + 🎲: reroll within-class variation.
##   - Spin toggle: rotate the ship slowly for silhouette inspection.

const ProceduralShipScript := preload(
  "res://scripts/tools/procedural_ship.gd"
)

const ORBIT_SENSITIVITY := 0.005
const ZOOM_MIN := 2.0
const ZOOM_MAX := 20.0
const ZOOM_STEP := 0.9

var ship: ProceduralShip
var ship_pivot: Node3D   # separate so "spin" doesn't mutate ship.rotation
var camera_rig: Node3D
var camera: Camera3D
var _yaw: float = 0.4
var _pitch: float = -0.35
var _zoom: float = 6.0
var _dragging := false
var _spin := true

var _class_opt: OptionButton
var _size_opt: OptionButton
var _faction_opt: OptionButton
var _seed_spin: SpinBox
var _size_readout: Label


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
  e.background_color = Color(0.015, 0.015, 0.04)
  e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
  e.ambient_light_color = Color(1, 1, 1)
  e.ambient_light_energy = 0.18
  e.glow_enabled = true
  e.glow_intensity = 1.0
  e.glow_hdr_threshold = 1.0
  env.environment = e
  add_child(env)

  var key := DirectionalLight3D.new()
  key.rotation_degrees = Vector3(-42, 35, 0)
  key.light_energy = 1.6
  add_child(key)
  var fill := DirectionalLight3D.new()
  fill.rotation_degrees = Vector3(-10, -115, 0)
  fill.light_energy = 0.35
  fill.light_color = Color(0.75, 0.82, 1.0)
  add_child(fill)

  ship_pivot = Node3D.new()
  ship_pivot.name = "ShipPivot"
  add_child(ship_pivot)

  ship = ProceduralShipScript.new()
  ship.name = "Ship"
  ship_pivot.add_child(ship)

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


func _process(delta: float) -> void:
  if _spin and ship_pivot:
    ship_pivot.rotate_y(delta * 0.35)


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
  title.text = "Ship Playground"
  title.add_theme_font_size_override("font_size", 20)
  vbox.add_child(title)
  var hint := Label.new()
  hint.text = "Left-drag: orbit · Wheel: zoom"
  hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
  vbox.add_child(hint)

  vbox.add_child(HSeparator.new())

  # Class
  _class_opt = OptionButton.new()
  for k in ProceduralShip.ShipClass.keys():
    _class_opt.add_item(
      String(k).capitalize(), ProceduralShip.ShipClass[k]
    )
  _class_opt.select(
    _class_opt.get_item_index(ship.ship_class)
  )
  _class_opt.item_selected.connect(_on_class_selected)
  _add_row(vbox, "Class", _class_opt)

  # Size
  _size_opt = OptionButton.new()
  for k in ProceduralShip.ShipSize.keys():
    _size_opt.add_item(
      String(k).capitalize(), ProceduralShip.ShipSize[k]
    )
  _size_opt.select(_size_opt.get_item_index(ship.ship_size))
  _size_opt.item_selected.connect(_on_size_selected)
  _add_row(vbox, "Size", _size_opt)

  # Size scale readout — instant visual feedback for the multiplier.
  _size_readout = Label.new()
  _size_readout.add_theme_color_override(
    "font_color", Color(0.9, 0.9, 0.5)
  )
  _refresh_size_readout()
  vbox.add_child(_size_readout)

  # Faction
  _faction_opt = OptionButton.new()
  var i := 0
  for fid in ProceduralShip.FACTION_PALETTES.keys():
    _faction_opt.add_item(String(fid), i)
    _faction_opt.set_item_metadata(i, fid)
    if String(fid) == ship.faction_id:
      _faction_opt.select(i)
    i += 1
  _faction_opt.item_selected.connect(func(idx: int):
    ship.faction_id = String(_faction_opt.get_item_metadata(idx))
  )
  _add_row(vbox, "Faction", _faction_opt)

  # Seed row
  var seed_row := HBoxContainer.new()
  _seed_spin = SpinBox.new()
  _seed_spin.min_value = 0
  _seed_spin.max_value = 9_999_999
  _seed_spin.step = 1
  _seed_spin.value = ship.ship_seed
  _seed_spin.value_changed.connect(func(v): ship.ship_seed = int(v))
  _seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  seed_row.add_child(_seed_spin)
  var rand_btn := Button.new()
  rand_btn.text = "🎲"
  rand_btn.pressed.connect(_on_randomize)
  seed_row.add_child(rand_btn)
  _add_row(vbox, "Seed", seed_row)

  # Spin toggle
  var spin_box := CheckBox.new()
  spin_box.text = "Rotate ship"
  spin_box.button_pressed = _spin
  spin_box.toggled.connect(func(on: bool): _spin = on)
  vbox.add_child(spin_box)

  # Cycle buttons (quick class + seed reroll loops)
  var cycle_row := HBoxContainer.new()
  var prev_btn := Button.new()
  prev_btn.text = "◀ Class"
  prev_btn.pressed.connect(_on_prev_class)
  prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  cycle_row.add_child(prev_btn)
  var next_btn := Button.new()
  next_btn.text = "Class ▶"
  next_btn.pressed.connect(_on_next_class)
  next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  cycle_row.add_child(next_btn)
  vbox.add_child(cycle_row)

  vbox.add_child(HSeparator.new())
  var copy_btn := Button.new()
  copy_btn.text = "Copy config to stdout"
  copy_btn.pressed.connect(_on_copy_config)
  vbox.add_child(copy_btn)


func _add_row(
  parent: Container, label_text: String, ctrl: Control
) -> void:
  var row := HBoxContainer.new()
  var lbl := Label.new()
  lbl.text = label_text
  lbl.custom_minimum_size = Vector2(120, 0)
  row.add_child(lbl)
  ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(ctrl)
  parent.add_child(row)


# ---------------------------------------------------------------------------
# UI handlers
# ---------------------------------------------------------------------------

func _on_randomize() -> void:
  var s := randi() % 10_000_000
  ship.ship_seed = s
  _seed_spin.set_value_no_signal(s)


func _on_class_selected(idx: int) -> void:
  _set_class(_class_opt.get_item_id(idx))


func _on_size_selected(idx: int) -> void:
  ship.ship_size = _size_opt.get_item_id(idx)
  _refresh_size_readout()


func _on_prev_class() -> void:
  var classes: Array = ProceduralShip.ShipClass.values()
  var cur_idx := classes.find(ship.ship_class)
  var next_idx := (cur_idx - 1 + classes.size()) % classes.size()
  _set_class(classes[next_idx])


func _on_next_class() -> void:
  var classes: Array = ProceduralShip.ShipClass.values()
  var cur_idx := classes.find(ship.ship_class)
  var next_idx := (cur_idx + 1) % classes.size()
  _set_class(classes[next_idx])


func _set_class(cls: ProceduralShip.ShipClass) -> void:
  ## Switch class AND reset size to that class's default. Otherwise
  ## picking Courier after Hauler leaves you with a Huge Courier, which
  ## is only sometimes what you wanted.
  ship.ship_class = cls
  _class_opt.select(_class_opt.get_item_index(cls))
  var default_size: ProceduralShip.ShipSize = ProceduralShip.CLASS_DEFAULT_SIZE.get(
    cls, ProceduralShip.ShipSize.MEDIUM
  )
  ship.ship_size = default_size
  _size_opt.select(_size_opt.get_item_index(default_size))
  _refresh_size_readout()


func _refresh_size_readout() -> void:
  if not _size_readout:
    return
  var mult: float = float(ProceduralShip.SIZE_SCALES.get(ship.ship_size, 1.0))
  _size_readout.text = "  Scale: %.2fx" % mult


func _on_copy_config() -> void:
  var cfg := ship.to_config()
  var text := JSON.stringify(cfg, "  ")
  print("[ship_playground] config:")
  print(text)
  DisplayServer.clipboard_set(text)
