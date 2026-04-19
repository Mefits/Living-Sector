extends Node3D

## Manages all star systems and dispatches position updates to ships and facilities.

var _star_system_scene: PackedScene = preload("res://scenes/world/star_system.tscn")
var _ship_scene: PackedScene = preload("res://scenes/world/ship.tscn")

var _ship_nodes: Dictionary = {}
var _facility_nodes: Dictionary = {}


func get_ship_node(id: String) -> Node3D:
	return _ship_nodes.get(id)


func get_facility_node(id: String) -> Node3D:
	return _facility_nodes.get(id)


func build_world() -> void:
	# Create star systems at their offsets
	for system_data in GameState.systems.values():
		var system_node = _star_system_scene.instantiate()
		add_child(system_node)

		var sys_id: String = system_data["id"]
		var offset: Vector2 = GameState.get_system_offset(sys_id)
		system_node.position = GameState.server_to_world(offset.x, offset.y)
		system_node.setup(sys_id, system_data)

		# Collect facility node references for position updates
		for facility_node in system_node.get_node("Facilities").get_children():
			_facility_nodes[facility_node.facility_id] = facility_node

	# Create ships as flat children of universe (absolute positions)
	for ship_data in GameState.ships.values():
		var ship_node = _ship_scene.instantiate()
		add_child(ship_node)
		ship_node.setup(ship_data)
		_ship_nodes[ship_data["id"]] = ship_node

	# Connect to position updates
	GameState.positions_updated.connect(_on_positions_updated)
	GameState.ship_removed.connect(_on_ship_removed)
	GameState.ship_added.connect(_on_ship_added)
	GameState.facility_removed.connect(_on_facility_removed)
	GameState.facility_added.connect(_on_facility_added)

	print("[Universe] Built %d systems, %d ships, %d facilities" % [
		GameState.systems.size(), _ship_nodes.size(), _facility_nodes.size()
	])


var _camera: Camera3D
var _cull_timer: float = 0.0
const CULL_INTERVAL := 0.5  # Cull check every 0.5 sec


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _process(delta: float) -> void:
	if not _camera:
		return
	_cull_timer += delta
	if _cull_timer >= CULL_INTERVAL:
		_cull_timer = 0.0
		_cull_ships()


func _cull_ships() -> void:
	# Hide ships far from camera, show ones nearby
	var cam_x := _camera.position.x
	var cam_z := _camera.position.z
	# Cull radius scales with zoom — see more when zoomed out
	var cull_radius: float = GameState.zoom_raw * 2.5
	var cull_sq := cull_radius * cull_radius

	for ship_node in _ship_nodes.values():
		var sn: Node3D = ship_node
		var dx: float = sn.position.x - cam_x
		var dz: float = sn.position.z - cam_z
		var dist_sq: float = dx * dx + dz * dz
		sn.visible = (dist_sq < cull_sq)
		sn.set_process(sn.visible)


func _on_ship_removed(id: String) -> void:
	if _ship_nodes.has(id):
		var node: Node3D = _ship_nodes[id]
		_ship_nodes.erase(id)
		if is_instance_valid(node):
			node.queue_free()


func _on_facility_removed(id: String) -> void:
	if _facility_nodes.has(id):
		var node: Node3D = _facility_nodes[id]
		_facility_nodes.erase(id)
		if is_instance_valid(node):
			node.queue_free()


func _on_ship_added(id: String) -> void:
	if _ship_nodes.has(id):
		return
	var ship_data: Dictionary = GameState.ships.get(id, {})
	if ship_data.is_empty():
		return
	var ship_node = _ship_scene.instantiate()
	add_child(ship_node)
	ship_node.setup(ship_data)
	_ship_nodes[id] = ship_node


func _on_facility_added(id: String) -> void:
	if _facility_nodes.has(id):
		return
	var fac_data: Dictionary = GameState.facilities.get(id, {})
	if fac_data.is_empty():
		return
	var system_node: Node = _find_system_node_for_body(
		str(fac_data.get("body_id", ""))
	)
	if system_node == null:
		push_warning(
			"[Universe] no star_system found for new facility %s" % id
		)
		return
	var fac_node: Node = system_node.create_facility(fac_data)
	if fac_node != null:
		_facility_nodes[id] = fac_node


func _find_system_node_for_body(body_id: String) -> Node:
	if body_id == "":
		return null
	# Figure out which system owns this body, then find the star_system
	# Node3D we spawned for it in build_world.
	var owning_sys_id: String = ""
	for sys_id in GameState.systems:
		var sys: Dictionary = GameState.systems[sys_id]
		for body in sys.get("bodies", []):
			if str(body.get("id", "")) == body_id:
				owning_sys_id = sys_id
				break
		if owning_sys_id != "":
			break
	if owning_sys_id == "":
		return null
	for child in get_children():
		if child.get("system_id") == owning_sys_id:
			return child
	return null


func _on_positions_updated(positions_array: Array) -> void:
	for entry in positions_array:
		var id: String = entry.get("id", "")
		var x: float = float(entry.get("x", 0.0))
		var y: float = float(entry.get("y", 0.0))

		if id.begins_with("ship-"):
			if _ship_nodes.has(id):
				_ship_nodes[id].update_position(x, y)
		elif id.begins_with("facility-"):
			if _facility_nodes.has(id):
				_facility_nodes[id].update_position(x, y)
