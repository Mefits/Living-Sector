extends Node3D

## Container for a star system — holds its orbital bodies and facilities.

var system_id: String
var system_data: Dictionary
var _system_offset: Vector2

@onready var label: Label3D = $Label3D
@onready var bodies_node: Node3D = $Bodies
@onready var facilities_node: Node3D = $Facilities

var _orbital_body_scene: PackedScene = preload("res://scenes/world/orbital_body.tscn")
var _facility_scene: PackedScene = preload("res://scenes/world/facility.tscn")
var _orbit_ring_script: GDScript = preload("res://scripts/world/orbit_ring.gd")

# Body display sizes — larger bodies get bigger spheres
const BODY_RADII := {
	"jupiter": 1.5,
	"saturn": 1.3,
	"earth": 0.8,
	"mars": 0.6,
	"venus": 0.7,
	"haven": 0.7,
	"proxima": 0.9,
}
const DEFAULT_BODY_RADIUS := 0.5


const STAR_COLORS := {
	"system-sol": Color(1.0, 0.95, 0.6),
	"system-alpha-centauri": Color(1.0, 0.7, 0.4),
	"system-tau-ceti": Color(1.0, 0.9, 0.7),
}
const STAR_RADIUS := 0.6


func setup(id: String, data: Dictionary) -> void:
	system_id = id
	system_data = data
	_system_offset = GameState.get_system_offset(id)

	var sys_name: String = data.get("name", id)
	label.text = sys_name

	GameState.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)

	# Star at system center
	_create_star(id)

	# Create orbital bodies (body x/y are in universe coords)
	var body_list: Array = data.get("bodies", [])
	for body in body_list:
		_create_body(body)

	# Create facilities that belong to this system
	for facility_data in GameState.facilities.values():
		var fac_body_id: String = facility_data.get("body_id", "")
		var belongs := false
		for body in body_list:
			if body.get("id", "") == fac_body_id:
				belongs = true
				break
		if belongs:
			_create_facility(facility_data)


func _to_local_pos(abs_x: float, abs_y: float) -> Vector3:
	## Convert absolute universe coords to local position (relative to system center).
	var rel_x := abs_x - _system_offset.x
	var rel_y := abs_y - _system_offset.y
	return GameState.server_to_world(rel_x, rel_y)


func _create_body(body_data: Dictionary) -> void:
	var body_id: String = body_data.get("id", "")
	var body_name: String = body_data.get("name", body_id)
	var radius: float = BODY_RADII.get(body_id, DEFAULT_BODY_RADIUS)

	# Body positions: try x/y directly, then nested position dict
	var x: float = 0.0
	var y: float = 0.0
	var has_pos := false

	if body_data.has("x") and body_data["x"] != null:
		x = float(body_data["x"])
		y = float(body_data.get("y", 0.0))
		has_pos = true
	else:
		var pos = body_data.get("position")
		if pos is Dictionary:
			x = float(pos.get("x", 0.0))
			y = float(pos.get("y", 0.0))
			has_pos = (x != 0.0 or y != 0.0)

	if not has_pos:
		# Try to derive from a facility at this body
		for fac in GameState.facilities.values():
			if fac.get("body_id", "") == body_id:
				var fpos = fac.get("position", {})
				if fpos is Dictionary:
					var fx: float = float(fpos.get("x", 0.0))
					var fy: float = float(fpos.get("y", 0.0))
					if fx != 0.0 or fy != 0.0:
						x = fx
						y = fy
						has_pos = true
						break

	if not has_pos:
		return  # Can't place this body

	var world_pos := _to_local_pos(x, y)
	var body_node = _orbital_body_scene.instantiate()
	bodies_node.add_child(body_node)
	body_node.setup(body_id, body_name, world_pos, radius, body_data)

	# Add orbit ring if we have orbit_radius
	var orbit_r = body_data.get("orbit_radius")
	if orbit_r != null and float(orbit_r) > 0.0:
		var ring := MeshInstance3D.new()
		ring.set_script(_orbit_ring_script)
		add_child(ring)
		ring.setup(float(orbit_r))


func _create_facility(data: Dictionary) -> void:
	create_facility(data)


func create_facility(data: Dictionary) -> Node:
	## Public version used by the universe to spawn a facility
	## post-world-build (e.g. god-mode create). Returns the new node
	## so callers can track it, or null if we couldn't place it.
	var pos = data.get("position", {})
	if not (pos is Dictionary):
		return null

	var x: float = float(pos.get("x", 0.0))
	var y: float = float(pos.get("y", 0.0))

	if x == 0.0 and y == 0.0:
		return null

	var world_pos := _to_local_pos(x, y)
	var facility_node = _facility_scene.instantiate()
	var index: int = facilities_node.get_child_count()
	facilities_node.add_child(facility_node)
	facility_node.setup(data, world_pos, index)
	return facility_node


func _create_star(sys_id: String) -> void:
	var star := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = STAR_RADIUS
	sphere.height = STAR_RADIUS * 2.0
	star.mesh = sphere

	var col: Color = STAR_COLORS.get(sys_id, Color(1.0, 0.95, 0.7))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.material_override = mat

	add_child(star)

	# Point light for the star glow
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.0
	light.omni_range = 15.0
	light.omni_attenuation = 1.5
	add_child(light)


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
	# System name visible at SYSTEM zoom and beyond
	label.visible = (tier >= GameState.ZoomTier.SYSTEM)
