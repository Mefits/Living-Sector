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
}

const DEFAULT_MODEL := "res://assets/stations/station01.glb"
const MODEL_SCALE := Vector3(0.05, 0.05, 0.05)

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
	var model_path: String = TYPE_MODELS.get(facility_type, DEFAULT_MODEL)
	var scene: PackedScene = load(model_path)
	if scene:
		var model := scene.instantiate()
		model.scale = MODEL_SCALE
		add_child(model)

	# Stagger labels above model, below planet labels
	var y_offset := 0.35 + (index % 4) * 0.15
	label.position = Vector3(0, y_offset, 0)

	# Activity glow — pulses when ships are docked
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(0.3, 0.6, 1.0)
	_glow_light.light_energy = 0.0
	_glow_light.omni_range = 3.0
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

	# Pulse glow when facility has docked ships
	_time += delta
	var data: Dictionary = GameState.facilities.get(facility_id, {})
	var docked = data.get("docked_ships", [])
	var docked_count: int = docked.size() if docked is Array else 0
	if docked_count > 0:
		var intensity := 0.3 + 0.2 * sin(_time * 2.0)
		intensity *= minf(float(docked_count) / 3.0, 1.0)
		_glow_light.light_energy = intensity
	else:
		_glow_light.light_energy = 0.0


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
	# Facility labels visible at CLOSE and LOCAL
	label.visible = (tier <= GameState.ZoomTier.LOCAL)
