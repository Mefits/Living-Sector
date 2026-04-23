extends Camera3D

## Top-down perspective camera with slight tilt for isometric feel.
## Zoom moves along the view axis to maintain consistent angle.
##
## Also supports a "POV" chase-cam mode that rides behind a ship,
## inheriting the ship's heading so the camera rotates with its path.
## If we add more discrete modes (cinematic flyby, dogfight, orbital
## tour) it's probably worth switching to the Phantom Camera addon
## with priority-based cameras instead of growing this script further.

@export var zoom_level: float = 80.0
# Let the camera pull right up to ships. 10.0 was safe but couldn't frame
# a single courier at its rendered size (~0.05 world units). 2.0 lets
# you clearly see individual ship silhouettes; below that you can clip
# inside planet geometry.
@export var zoom_min: float = 2.0
@export var zoom_max: float = 300.0
@export var zoom_speed: float = 8.0
@export var pan_speed_base: float = 50.0
@export var cam_angle: float = -70.0  # Tilt from horizontal
# Godot defaults to 75° which causes visible sphere distortion near the
# viewport edges. 40° is a "telephoto" look that flattens perspective so
# planets stay round across the whole screen.
@export var fov_degrees: float = 40.0

# POV chase-cam tuning
@export var pov_distance: float = 4.2
@export var pov_distance_min: float = 1.5
@export var pov_distance_max: float = 20.0
@export var pov_height: float = 1.75
@export var pov_tilt_degrees: float = -10.0

var follow_target: Node3D = null
var pov_target: Node3D = null

var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_camera_start := Vector3.ZERO

# Precomputed from cam_angle
var _sin_angle: float
var _cos_angle: float
var _look_z_offset: float = 0.0  # Z offset to maintain angle


func _ready() -> void:
  var angle_rad := deg_to_rad(absf(cam_angle))
  _sin_angle = sin(angle_rad)
  _cos_angle = cos(angle_rad)
  rotation_degrees = Vector3(cam_angle, 0.0, 0.0)
  fov = fov_degrees
  _apply_zoom(0.0)


func _process(delta: float) -> void:
  # POV mode takes over positioning and rotation completely
  if pov_target:
    if not is_instance_valid(pov_target):
      exit_pov()
    else:
      _update_pov_transform()
      return

  if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
    _apply_zoom(-zoom_speed * delta * 10.0)
  if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
    _apply_zoom(zoom_speed * delta * 10.0)

  if follow_target:
    position.x = follow_target.position.x
    position.z = follow_target.position.z + _look_z_offset
  else:
    var pan_speed := pan_speed_base * (zoom_level / 80.0)
    var move := Vector3.ZERO

    if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
      move.x -= 1.0
    if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
      move.x += 1.0
    if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
      move.z -= 1.0
    if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
      move.z += 1.0

    if move != Vector3.ZERO:
      position += move.normalized() * pan_speed * delta


func _unhandled_input(event: InputEvent) -> void:
  # _unhandled_input runs AFTER GUI event handling: a ScrollContainer /
  # ItemList inside a panel will consume the wheel event first, and this
  # camera only gets it when the cursor is over the 3D viewport. Using
  # _input here would steal wheel scrolling from every open panel.
  # ESC exits POV.
  if pov_target and event is InputEventKey:
    if event.pressed and event.keycode == KEY_ESCAPE:
      exit_pov()
      get_viewport().set_input_as_handled()
      return

  if event is InputEventMouseButton:
    # In POV, mouse wheel adjusts chase distance rather than zoom.
    if pov_target:
      if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        pov_distance = clampf(
          pov_distance - 0.75, pov_distance_min, pov_distance_max
        )
        get_viewport().set_input_as_handled()
      elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        pov_distance = clampf(
          pov_distance + 0.75, pov_distance_min, pov_distance_max
        )
        get_viewport().set_input_as_handled()
      return

    if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
      _apply_zoom(-zoom_speed * (zoom_level / 80.0))
      get_viewport().set_input_as_handled()
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
      _apply_zoom(zoom_speed * (zoom_level / 80.0))
      get_viewport().set_input_as_handled()

    elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
      if follow_target == null:
        if event.pressed:
          _is_dragging = true
          _drag_start = event.position
          _drag_camera_start = position
        else:
          _is_dragging = false

  elif event is InputEventMouseMotion and _is_dragging and pov_target == null:
    var motion := event as InputEventMouseMotion
    var viewport_size := get_viewport().get_visible_rect().size
    var drag_factor := zoom_level / viewport_size.y * 2.0
    var delta_mouse: Vector2 = motion.position - _drag_start
    position.x = _drag_camera_start.x - delta_mouse.x * drag_factor
    position.z = _drag_camera_start.z - drag_factor * delta_mouse.y


func _apply_zoom(amount: float) -> void:
  zoom_level = clampf(zoom_level + amount, zoom_min, zoom_max)
  position.y = zoom_level * _sin_angle
  _look_z_offset = zoom_level * _cos_angle
  GameState.update_zoom(zoom_level)


func focus_on(world_pos: Vector3) -> void:
  position.x = world_pos.x
  position.z = world_pos.z + _look_z_offset


func enter_pov(target: Node3D) -> void:
  if target == null:
    return
  pov_target = target
  follow_target = null
  _is_dragging = false


func exit_pov() -> void:
  if pov_target == null:
    return
  pov_target = null
  # Restore the normal top-down transform.
  var angle_rad := deg_to_rad(absf(cam_angle))
  _sin_angle = sin(angle_rad)
  _cos_angle = cos(angle_rad)
  rotation = Vector3.ZERO
  rotation_degrees = Vector3(cam_angle, 0.0, 0.0)
  _apply_zoom(0.0)


func _update_pov_transform() -> void:
  # Place the camera behind the ship along its heading, slightly above,
  # and match the ship's yaw so we look where it's going. Ship.gd's
  # rotation.y = atan2(dx, dz), which means the ship's forward is +Z
  # after yaw — but Godot's default camera forward is -Z, so the camera
  # needs heading + PI to face the same direction as the ship.
  var heading: float = pov_target.rotation.y
  var forward := Vector3(sin(heading), 0.0, cos(heading))
  position = (
    pov_target.position
    - forward * pov_distance
    + Vector3(0.0, pov_height, 0.0)
  )
  rotation = Vector3(deg_to_rad(pov_tilt_degrees), heading + PI, 0.0)
