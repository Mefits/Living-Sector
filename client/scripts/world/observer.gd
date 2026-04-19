extends Node3D

## The player's observer — a controllable entity in the world.
## In follow mode, WASD moves the observer and the camera tracks it.
## Movement is sent optimistically to the server.

signal position_changed(universe_x: float, universe_y: float)

var observer_id: String = "observer-1"
var move_speed: float = 8.0  # Universe units per second

var _active := false  # Whether the observer is being controlled

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D


func _ready() -> void:
	# Start at Sol
	position = Vector3.ZERO
	label.text = "Observer"


func setup(id: String, start_x: float, start_y: float) -> void:
	observer_id = id
	position = GameState.server_to_world(start_x, start_y)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.3, 0.9) * 0.8
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat


func set_active(active: bool) -> void:
	_active = active
	label.text = "Observer (you)" if active else "Observer"


func get_universe_position() -> Vector2:
	return Vector2(
		position.x / GameState.SCALE_FACTOR,
		position.z / GameState.SCALE_FACTOR
	)


func _process(delta: float) -> void:
	if not _active:
		return

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		move.z += 1.0

	if move != Vector3.ZERO:
		# Move in world space (scaled)
		var scaled_speed := move_speed * GameState.SCALE_FACTOR
		position += move.normalized() * scaled_speed * delta

		# Emit universe coords for network send
		var upos := get_universe_position()
		position_changed.emit(upos.x, upos.y)
