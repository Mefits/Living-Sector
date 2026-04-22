extends Node3D

## Renders a facility using a space station 3D model.
## Lerps between server positions over the tick interval.

var facility_id: String
var facility_data: Dictionary
var _glow_light: OmniLight3D
var _time: float = 0.0

@onready var label: Label3D = $Label3D

const TYPE_MODELS := {
	"station": "res://assets/stations/station01.glb",
	"outpost": "res://assets/stations/station05.glb",
	"mining_rig": "res://assets/stations/station03_base.glb",
	"refinery": "res://assets/stations/station02_base.glb",
	"factory": "res://assets/stations/station06_base.glb",
	"farm": "res://assets/stations/station05.glb",
	# Gates use the heaviest model so they read as a landmark. The
	# distinguishing feature is the cyan emissive ring built procedurally
	# below — it's what makes them visually "portal-y" in-game.
	"gate": "res://assets/stations/station06_base.glb",
}

const DEFAULT_MODEL := "res://assets/stations/station01.glb"
const MODEL_SCALE := Vector3(0.05, 0.05, 0.05)
# Bigger scale for gates so they're visible at system-level zoom.
const GATE_MODEL_SCALE := Vector3(0.12, 0.12, 0.12)

var _system_offset: Vector2
var _prev_pos: Vector3
var _next_pos: Vector3
var _lerp_t: float = 1.0


func setup(data: Dictionary, world_pos: Vector3, index: int = 0) -> void:
	facility_id = data.get("id", "")
	facility_data = data
	position = world_pos
	_prev_pos = world_pos
	_next_pos = world_pos

	var body_id: String = data.get("body_id", "")
	for sys in GameState.systems.values():
		for body in sys.get("bodies", []):
			if body.get("id", "") == body_id:
				_system_offset = GameState.get_system_offset(sys["id"])
				break

	label.text = data.get("name", facility_id)

	# Load station model
	var facility_type: String = data.get("type", "")
	var is_gate := facility_type == "gate"
	var model_path: String = TYPE_MODELS.get(facility_type, DEFAULT_MODEL)
	var scene: PackedScene = load(model_path)
	if scene:
		var model := scene.instantiate()
		model.scale = GATE_MODEL_SCALE if is_gate else MODEL_SCALE
		add_child(model)

	# Gates get a distinctive cyan emissive ring around them — the
	# visual hook players pattern-match on when routing cross-system
	# travel. Non-gate facilities just have the dock glow.
	if is_gate:
		_create_gate_ring()

	# Stagger labels above model, below planet labels
	var y_offset := 0.35 + (index % 4) * 0.15
	label.position = Vector3(0, y_offset, 0)

	# Activity glow — pulses when ships are docked (gates glow stronger
	# because jumps count as heavy activity).
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(0.3, 0.6, 1.0) if not is_gate else Color(0.4, 0.9, 1.0)
	_glow_light.light_energy = 0.0
	_glow_light.omni_range = 5.0 if is_gate else 3.0
	_glow_light.omni_attenuation = 1.5
	add_child(_glow_light)

	GameState.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)


func update_position(abs_x: float, abs_y: float) -> void:
	var rel_x := abs_x - _system_offset.x
	var rel_y := abs_y - _system_offset.y
	_prev_pos = _next_pos
	_next_pos = GameState.server_to_world(rel_x, rel_y)
	_lerp_t = 0.0


func _process(delta: float) -> void:
	if _lerp_t < 1.0:
		var interval := GameState.get_tick_interval_seconds()
		_lerp_t = minf(_lerp_t + delta / interval, 1.0)
		var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
		position = _prev_pos.lerp(_next_pos, t)

	# Pulse glow when facility has docked ships; gates pulse subtly
	# even when idle so they read as "always on, always powered".
	_time += delta
	var data: Dictionary = GameState.facilities.get(facility_id, {})
	var docked = data.get("docked_ships", [])
	var docked_count: int = docked.size() if docked is Array else 0
	var is_gate: bool = data.get("type", "") == "gate"
	if docked_count > 0:
		var intensity := 0.3 + 0.2 * sin(_time * 2.0)
		intensity *= minf(float(docked_count) / 3.0, 1.0)
		_glow_light.light_energy = intensity
	elif is_gate:
		# Idle gate heartbeat — soft cyan pulse.
		_glow_light.light_energy = 0.15 + 0.05 * sin(_time * 1.2)
	else:
		_glow_light.light_energy = 0.0


## Build a cyan torus ring around the facility to mark it as a gate.
## Sits flat on the XZ plane, rotates slowly so the "portal" reads even
## at a distance.
func _create_gate_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.60
	torus.rings = 32
	torus.ring_segments = 12

	var ring := MeshInstance3D.new()
	ring.mesh = torus
	# TorusMesh is YZ by default; rotate so the ring is horizontal.
	ring.rotation_degrees.x = 90.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 1.0) * 1.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat

	add_child(ring)


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
	# Facility labels visible at CLOSE and LOCAL
	label.visible = (tier <= GameState.ZoomTier.LOCAL)
