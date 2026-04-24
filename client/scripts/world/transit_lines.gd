extends Node3D

## Draws dotted transit lines. All lines are very faint;
## the selected ship's line is drawn brighter on top.

# Kill switch (2026-04-24 perf bisect found transit lines were the
# single biggest remaining FPS cost at ~1500 ships). Left in place so
# we can flip it off without editing code if we ever need another
# isolation run. The main cost has now been addressed by
# (a) skipping ships the camera cull has hidden, (b) rebuilding every
# REBUILD_EVERY_N broadcasts instead of every one.
const ENABLE_TRANSIT_LINES: bool = true

const LINE_COLOR_BASE := Color(0.5, 0.6, 0.9)
const SELECTED_COLOR := Color(0.7, 0.8, 1.0)
const DASH_LENGTH := 0.8
const GAP_LENGTH := 0.5

const TIER_ALPHA := {
	GameState.ZoomTier.CLOSE: 0.08,
	GameState.ZoomTier.LOCAL: 0.05,
	GameState.ZoomTier.SYSTEM: 0.03,
	GameState.ZoomTier.REGION: 0.02,
	GameState.ZoomTier.GALAXY: 0.01,
}
const SELECTED_ALPHA := 0.35

var _all_mesh: ImmediateMesh
var _all_inst: MeshInstance3D
var _all_mat: StandardMaterial3D

var _sel_mesh: ImmediateMesh
var _sel_inst: MeshInstance3D
var _sel_mat: StandardMaterial3D

var _location_cache: Dictionary = {}

# Cache our parent universe so _rebuild_lines can skip ships the
# camera-distance cull has already hidden. Lets transit lines piggyback
# on the existing cull work rather than draw across the whole fleet.
var _universe: Node = null

# Rebuild cadence. The positions broadcast fires every ~125 ms but at
# 1500 ships the full rebuild dominated the main thread — and the lines
# are a coarse visual hint, not precise nav, so sub-second freshness is
# fine. 4 = rebuild every 4 broadcasts (~500 ms), quartering the cost
# while still feeling live.
const REBUILD_EVERY_N: int = 4
var _broadcast_counter: int = 0


func _ready() -> void:
	# Faint lines for all ships
	_all_mesh = ImmediateMesh.new()
	_all_inst = MeshInstance3D.new()
	_all_inst.mesh = _all_mesh
	_all_mat = _make_line_material(Color(LINE_COLOR_BASE, 0.05))
	_all_inst.material_override = _all_mat
	add_child(_all_inst)

	# Bright line for selected ship
	_sel_mesh = ImmediateMesh.new()
	_sel_inst = MeshInstance3D.new()
	_sel_inst.mesh = _sel_mesh
	_sel_mat = _make_line_material(Color(SELECTED_COLOR, SELECTED_ALPHA))
	_sel_inst.material_override = _sel_mat
	add_child(_sel_inst)

	# We're instantiated as a child of the Universe node (see main.gd).
	# Cache the reference once so _rebuild_lines can call
	# `universe.is_ship_visible(id)` without a per-line get_parent().
	_universe = get_parent()

	GameState.positions_updated.connect(_on_positions_updated)


func _make_line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = -1
	return mat


func _on_positions_updated(_positions: Array) -> void:
	if not ENABLE_TRANSIT_LINES:
		# Killswitch for the perf bisect. Keeps the toggle useful as a
		# one-flip "render nothing" if we ever want to isolate again.
		_all_mesh.clear_surfaces()
		_sel_mesh.clear_surfaces()
		return
	# Cadence gate: only rebuild every N broadcasts. Position drift
	# during the gap is small and the lines are a coarse hint, not
	# navigation-accurate geometry.
	_broadcast_counter += 1
	if _broadcast_counter < REBUILD_EVERY_N:
		return
	_broadcast_counter = 0
	_rebuild_location_cache()
	var alpha: float = TIER_ALPHA.get(GameState.zoom_tier, 0.03)
	_all_mat.albedo_color = Color(LINE_COLOR_BASE, alpha)
	_rebuild_lines()


func _rebuild_location_cache() -> void:
	_location_cache.clear()
	for fac in GameState.facilities.values():
		var loc: String = str(fac.get("location", ""))
		if loc == "" or loc == "null":
			continue
		var pos = fac.get("position", {})
		if not (pos is Dictionary):
			continue
		var x: float = float(pos.get("x", 0.0))
		var y: float = float(pos.get("y", 0.0))
		if x != 0.0 or y != 0.0:
			_location_cache[loc] = Vector2(x, y)


func _rebuild_lines() -> void:
	_all_mesh.clear_surfaces()
	_sel_mesh.clear_surfaces()

	var has_all := false
	var has_sel := false
	var selected_id: String = GameState.selected_entity_id

	for ship_data in GameState.ships.values():
		var transit = ship_data.get("transit")
		if transit == null or not (transit is Dictionary):
			continue

		var to_loc = transit.get("to")
		if to_loc == null or str(to_loc) == "null":
			continue

		var arrive: int = int(transit.get("arrival_tick", 0))
		if arrive > 0 and arrive <= GameState.tick:
			continue

		# Visibility gate: skip lines for ships the camera-distance
		# cull has already hidden. Always draw the selected ship's
		# line regardless — the user is tracking it and a missing
		# line for their selection would read as a bug.
		var ship_id: String = ship_data.get("id", "")
		var is_selected: bool = ship_id == selected_id
		if not is_selected and _universe != null and _universe.has_method("is_ship_visible"):
			if not _universe.is_ship_visible(ship_id):
				continue

		var pos = ship_data.get("position", {})
		if not (pos is Dictionary):
			continue
		var sx: float = float(pos.get("x", 0.0))
		var sy: float = float(pos.get("y", 0.0))

		var dest_key: String = str(to_loc)
		if not _location_cache.has(dest_key):
			continue
		var dest: Vector2 = _location_cache[dest_key]

		var from := GameState.server_to_world(sx, sy)
		var to := GameState.server_to_world(dest.x, dest.y)
		from.y = 0.05
		to.y = 0.05

		if is_selected:
			if not has_sel:
				_sel_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				has_sel = true
			_draw_dashed_line(_sel_mesh, from, to)
		else:
			if not has_all:
				_all_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				has_all = true
			_draw_dashed_line(_all_mesh, from, to)

	if has_all:
		_all_mesh.surface_end()
	if has_sel:
		_sel_mesh.surface_end()


func _draw_dashed_line(
	im: ImmediateMesh, from: Vector3, to: Vector3
) -> void:
	var direction := to - from
	var total_length := direction.length()
	if total_length < 0.1:
		return

	var dir_norm := direction / total_length
	var traveled := 0.0
	var drawing := true

	while traveled < total_length:
		var segment: float
		if drawing:
			segment = minf(DASH_LENGTH, total_length - traveled)
		else:
			segment = minf(GAP_LENGTH, total_length - traveled)

		if drawing:
			var start := from + dir_norm * traveled
			var end := from + dir_norm * (traveled + segment)
			im.surface_add_vertex(start)
			im.surface_add_vertex(end)

		traveled += segment
		drawing = not drawing
