extends Node3D

## Renders a ship with a 3D model based on ship class.
## Uses GPS-style displacement window for stable heading and speed.

var ship_id: String
var ship_class: String

var _prev_pos: Vector3
var _next_pos: Vector3
var _lerp_t: float = 1.0
var _model: Node3D
var _particles: GPUParticles3D
var _label: Label3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh

# GPS-style heading from position history
const HEADING_WINDOW := 20  # ticks for heading calculation
const TRAIL_LENGTH := 60    # ticks of trail (~7.5 sec at 8 tps)
var _pos_history: Array[Vector3] = []
var _trail_history: Array[Vector3] = []
var _target_heading: float = 0.0
var _speed: float = 0.0
var _is_moving := false

const CLASS_MODELS := {
	"freighter": "res://assets/ships/Challenger.gltf",
	"hauler": "res://assets/ships/Dispatcher.gltf",
	"courier": "res://assets/ships/Spitfire.gltf",
	"tanker": "res://assets/ships/Imperial.gltf",
	"miner": "res://assets/ships/Executioner.gltf",
}

const DEFAULT_MODEL := "res://assets/ships/Challenger.gltf"
const MODEL_SCALE := Vector3(0.03, 0.03, 0.03)

# Engine burn particle settings
const PARTICLE_BASE_LIFETIME := 0.6
const PARTICLE_MAX_LIFETIME := 4.0
const SPEED_FOR_MAX_BURN := 15.0


func setup(data: Dictionary) -> void:
	ship_id = data.get("id", "")
	ship_class = data.get("class", "")

	var pos_data = data.get("position", {})
	var x: float = pos_data.get("x", 0.0) if pos_data is Dictionary else 0.0
	var y: float = pos_data.get("y", 0.0) if pos_data is Dictionary else 0.0
	_next_pos = GameState.server_to_world(x, y)
	_prev_pos = _next_pos
	position = _next_pos

	# Load ship model
	var model_path: String = CLASS_MODELS.get(ship_class, DEFAULT_MODEL)
	var scene: PackedScene = load(model_path)
	if scene:
		_model = scene.instantiate()
		_model.scale = MODEL_SCALE
		add_child(_model)

	# Ship name label
	_label = $Label3D
	_label.text = data.get("name", ship_id)
	_label.visible = false  # Shown only at close zoom

	# Faction marker: small orange star above the-doughtys ships.
	# Billboarded + no-depth so it floats above the ship no matter the
	# camera angle. Scales with distance like everything else — fixed_size
	# at a 64pt font turned the whole viewport orange.
	if str(data.get("faction_id", "")) == "the-doughtys":
		var star := Label3D.new()
		star.text = "\u2605"  # ★
		star.modulate = Color(1.0, 0.6, 0.15)
		star.font_size = 16
		star.pixel_size = 0.003
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.no_depth_test = true
		star.position = Vector3(0.0, 0.5, 0.0)
		add_child(star)

	GameState.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)

	_setup_trail()
	_setup_particles()


func _setup_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = -2
	_trail.material_override = mat
	# Trail is a sibling, not a child — so it doesn't rotate with the ship
	# We add it to the parent in _ready or after being added to tree
	_trail.top_level = true
	add_child(_trail)


func _update_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_history.size() < 3 or not _is_moving:
		return

	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var count := _trail_history.size()
	for i in range(count):
		# t goes 0 (oldest) to 1 (newest)
		var t := float(i) / float(count - 1)
		var alpha := t * t * 0.35
		# Color shifts from red (old) to orange/yellow (new)
		var col := Color(
			1.0,
			0.3 + t * 0.4,
			0.1,
			alpha
		)
		_trail_mesh.surface_set_color(col)
		var pos: Vector3 = _trail_history[i]
		_trail_mesh.surface_add_vertex(Vector3(pos.x, 0.03, pos.z))
	_trail_mesh.surface_end()


func _setup_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 16
	_particles.lifetime = PARTICLE_BASE_LIFETIME
	_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = Color(0.8, 0.5, 0.2, 0.9)

	var color_ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.9, 0.6, 0.2, 1.0))
	gradient.set_color(1, Color(0.3, 0.1, 0.05, 0.0))
	color_ramp.gradient = gradient
	mat.color_ramp = color_ramp

	_particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	_particles.draw_pass_1 = quad

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	quad.material = draw_mat

	add_child(_particles)


func update_position(x: float, y: float) -> void:
	_prev_pos = _next_pos
	_next_pos = GameState.server_to_world(x, y)
	_lerp_t = 0.0

	# Add to position history ring buffers
	_pos_history.append(_next_pos)
	if _pos_history.size() > HEADING_WINDOW:
		_pos_history.remove_at(0)

	_trail_history.append(_next_pos)
	if _trail_history.size() > TRAIL_LENGTH:
		_trail_history.remove_at(0)

	# Compute heading and speed from displacement window
	_update_heading_from_history()
	_update_trail()


func _update_heading_from_history() -> void:
	if _pos_history.size() < 2:
		_is_moving = false
		return

	var oldest: Vector3 = _pos_history[0]
	var newest: Vector3 = _pos_history[-1]
	var displacement := newest - oldest
	var dist := displacement.length()

	if dist > 0.1:
		# Clear movement — update heading and speed
		_target_heading = atan2(displacement.x, displacement.z)
		_is_moving = true
		var window_secs: float = (
			_pos_history.size() * GameState.get_effective_interval_seconds()
		)
		_speed = dist / window_secs if window_secs > 0.0 else 0.0
	elif dist < 0.01:
		# Truly stationary
		_is_moving = false
		_speed = 0.0
	# else: in dead zone — keep last heading and moving state


func _process(delta: float) -> void:
	# Position interpolation
	if _lerp_t < 1.0:
		var interval := GameState.get_effective_interval_seconds()
		_lerp_t = minf(_lerp_t + delta / interval, 1.0)
		var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
		position = _prev_pos.lerp(_next_pos, t)

	# Smooth rotation toward window-derived heading
	if _is_moving:
		var diff := wrapf(_target_heading - rotation.y, -PI, PI)
		rotation.y += diff * minf(delta * 3.0, 1.0)

	# Engine burn particles — scale with speed, off when docked
	var ship_data: Dictionary = GameState.ships.get(ship_id, {})
	var loc: Variant = ship_data.get("location")
	var is_docked: bool = (
		loc != null and str(loc) != "null" and str(loc) != ""
	)
	if _is_moving and _speed > 0.05 and not is_docked:
		_particles.emitting = true
		var burn_t := clampf(_speed / SPEED_FOR_MAX_BURN, 0.0, 1.0)
		_particles.lifetime = lerpf(
			PARTICLE_BASE_LIFETIME, PARTICLE_MAX_LIFETIME, burn_t
		)
		_particles.amount = int(lerpf(8, 24, burn_t))
	else:
		_particles.emitting = false


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
	# Ship names only visible at CLOSE zoom
	if _label:
		_label.visible = (tier == GameState.ZoomTier.CLOSE)
