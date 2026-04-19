extends Control

## Minimap showing all star systems with camera viewport indicator.
## Click a system dot to jump the camera there.

const MINIMAP_SIZE := Vector2(180, 180)
const PADDING := 10.0
const SYSTEM_DOT_RADIUS := 6.0

# Per-system accent colors stay bespoke — each sun has its own hue.
const SYSTEM_COLORS := {
	"system-sol": Color(1.0, 0.9, 0.3),
	"system-alpha-centauri": Color(0.4, 0.8, 1.0),
	"system-tau-ceti": Color(1.0, 0.5, 0.3),
}

# Universe bounds for mapping to minimap (derived from data)
var _universe_min := Vector2(-15, -15)
var _universe_max := Vector2(50, 15)
var _camera: Camera3D


func _ready() -> void:
	custom_minimum_size = MINIMAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.world_loaded.connect(_update_bounds)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _update_bounds() -> void:
	# Derive bounds from system offsets + some margin
	var min_x := 0.0
	var min_y := 0.0
	var max_x := 0.0
	var max_y := 0.0
	for offset in GameState.system_offsets.values():
		var v: Vector2 = offset
		min_x = minf(min_x, v.x)
		min_y = minf(min_y, v.y)
		max_x = maxf(max_x, v.x)
		max_y = maxf(max_y, v.y)
	_universe_min = Vector2(min_x - 15.0, min_y - 15.0)
	_universe_max = Vector2(max_x + 15.0, max_y + 15.0)


func _universe_to_minimap(universe_pos: Vector2) -> Vector2:
	var range_vec := _universe_max - _universe_min
	var normalized := (universe_pos - _universe_min) / range_vec
	return Vector2(
		PADDING + normalized.x * (MINIMAP_SIZE.x - PADDING * 2),
		PADDING + normalized.y * (MINIMAP_SIZE.y - PADDING * 2)
	)


func _minimap_to_universe(minimap_pos: Vector2) -> Vector2:
	var range_vec := _universe_max - _universe_min
	var normalized := Vector2(
		(minimap_pos.x - PADDING) / (MINIMAP_SIZE.x - PADDING * 2),
		(minimap_pos.y - PADDING) / (MINIMAP_SIZE.y - PADDING * 2)
	)
	return _universe_min + normalized * range_vec


func _draw() -> void:
	# Background
	var bg: Color = ThemePalette.PANEL_BG
	var border: Color = ThemePalette.PRIMARY
	var ship_dot: Color = Color(
		ThemePalette.PRIMARY.r, ThemePalette.PRIMARY.g,
		ThemePalette.PRIMARY.b, 0.35
	)
	draw_rect(Rect2(Vector2.ZERO, MINIMAP_SIZE), bg)
	draw_rect(
		Rect2(Vector2.ZERO, MINIMAP_SIZE),
		Color(border.r, border.g, border.b, 0.7),
		false, 1.0
	)

	# Ship dots
	for ship in GameState.ships.values():
		var pos = ship.get("position", {})
		if pos is Dictionary:
			var sx: float = float(pos.get("x", 0.0))
			var sy: float = float(pos.get("y", 0.0))
			var mp := _universe_to_minimap(Vector2(sx, sy))
			draw_circle(mp, 1.0, ship_dot)

	# System dots
	for sys_id in GameState.system_offsets:
		var offset: Vector2 = GameState.system_offsets[sys_id]
		var mp := _universe_to_minimap(offset)
		var col: Color = SYSTEM_COLORS.get(sys_id, Color.WHITE)
		draw_circle(mp, SYSTEM_DOT_RADIUS, col)

		# System name
		var sys_data: Dictionary = GameState.systems.get(sys_id, {})
		var label: String = sys_data.get("name", sys_id)
		var font := ThemeDB.fallback_font
		var font_size := 9
		var text_size := font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		)
		draw_string(
			font,
			mp + Vector2(-text_size.x / 2, SYSTEM_DOT_RADIUS + 12),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col
		)

	# Camera viewport rectangle
	if _camera:
		var cam_x: float = _camera.position.x / GameState.SCALE_FACTOR
		var cam_z: float = _camera.position.z / GameState.SCALE_FACTOR
		var zoom: float = _camera.position.y / GameState.SCALE_FACTOR
		var aspect := get_viewport().get_visible_rect().size
		var half_w := zoom * aspect.x / aspect.y
		var half_h := zoom

		var top_left := _universe_to_minimap(
			Vector2(cam_x - half_w, cam_z - half_h)
		)
		var bottom_right := _universe_to_minimap(
			Vector2(cam_x + half_w, cam_z + half_h)
		)
		var rect := Rect2(top_left, bottom_right - top_left)
		var cam_fill: Color = Color(
			ThemePalette.PRIMARY.r, ThemePalette.PRIMARY.g,
			ThemePalette.PRIMARY.b, 0.18
		)
		draw_rect(rect, cam_fill)
		draw_rect(rect, ThemePalette.PRIMARY_BRIGHT, false, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var universe_pos := _minimap_to_universe(event.position)
			if _camera:
				var world := GameState.server_to_world(
					universe_pos.x, universe_pos.y
				)
				_camera.focus_on(world)
			accept_event()
