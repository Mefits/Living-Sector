extends Node2D
## One physical pad and one local service lane per ship slot.
## Native time drives every pose, including when the view is recreated.

const Art = preload("res://sol_lab/earth_port/ship_art.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const APPROACH := 1.25
const SERVICE := 3.25
const TAKEOFF := 0.9
const PAD_B := Vector2(167, 0)

var _runtime: RefCounted
var _roads: Array[Curve2D] = []
var _state: Dictionary = {}

func bind_runtime(runtime: RefCounted, body_id: String) -> void:
	_runtime = runtime if body_id == "earth" else null
	visible = _runtime != null
	_refresh()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_roads = [
		_road([Vector2(17, 0), Vector2(59, 0), Vector2(66, 10), Vector2(66, 64),
			Vector2(60, 74), Vector2(-8, 74), Vector2(-8, 89)]),
		_road([Vector2(184, 0), Vector2(210, 0), Vector2(220, 12), Vector2(220, 53),
			Vector2(214, 59), Vector2(129, 59), Vector2(129, 89)]),
	]

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_refresh()

func _refresh() -> void:
	var next: Dictionary = _runtime.earth_port_state() if _runtime != null else {}
	if next != _state:
		_state = next
		queue_redraw()

func _road(points: Array[Vector2]) -> Curve2D:
	var road := Curve2D.new()
	for point in points:
		road.add_point(point)
	return road

func _draw() -> void:
	if _roads.is_empty():
		return
	for index in 2:
		var pad := Vector2.ZERO if index == 0 else PAD_B
		var road := _roads[index]
		var lane := road.get_baked_points()
		draw_polyline(lane, Color("#444c48"), 9.0, true)
		draw_polyline(lane, Color("#666c5d"), 0.8, true)
		for distance in range(10, int(road.get_baked_length()) - 5, 10):
			draw_line(road.sample_baked(distance), road.sample_baked(distance + 3),
				Color("#aaa387"), 0.75, true)
		for x in [-34, 34]:
			draw_circle(pad + Vector2(x, 30), 1.3, Color("#e5c783"))
		if not _state.is_empty():
			_draw_bay(index, pad, road, _state.bays[index], _state.time)

func _draw_bay(index: int, pad: Vector2, road: Curve2D, bay: Dictionary, now: float) -> void:
	var order: Dictionary = bay.order
	var landed: Dictionary = bay.last_arrival
	var inbound: bool = order.get("destination") == "earth"
	var outbound: bool = order.get("source") == "earth"
	var landed_age := now - float(landed.get("time", -INF))
	var outgoing_age := now - float(bay.departure)
	var previous_service_end := float(landed.get("time", -INF)) + SERVICE
	if outbound:
		outgoing_age = now - maxf(float(bay.departure), previous_service_end)
	var cargo: Dictionary = {}
	var transfer := -1.0
	var flight_height := 0.0
	var ship_position := pad
	var show_ship: bool = bay.location == "earth"
	if inbound and float(bay.arrival) - now <= APPROACH:
		cargo = order
		show_ship = true
		flight_height = 1.0 - smoothstep(0.0, APPROACH, APPROACH - (float(bay.arrival) - now))
		ship_position += Vector2(0, 100) * flight_height
	elif landed_age >= 0.0 and landed_age < SERVICE:
		cargo = landed
		transfer = landed_age / SERVICE
		show_ship = true
	elif outbound and outgoing_age >= 0.0 and outgoing_age < SERVICE + TAKEOFF:
		cargo = order
		if outgoing_age <= SERVICE:
			transfer = 1.0 - outgoing_age / SERVICE
		flight_height = smoothstep(SERVICE, SERVICE + TAKEOFF, outgoing_age)
		ship_position -= Vector2(0, 100) * flight_height
		show_ship = true

	var loaded := int(cargo.get("amount", 0)) > 0
	var mount := ship_position
	var cargo_position := mount
	var cargo_angle := 0.0
	var show_cargo := loaded
	var loader_position := road.sample_baked(road.get_baked_length())
	if loaded and transfer >= 0.0:
		var lane_length := road.get_baked_length()
		var distance := lane_length * (1.0 - smoothstep(0.0, 0.28, transfer) +
			smoothstep(0.43, 0.91, transfer))
		loader_position = road.sample_baked(distance)
		var toward_ship := (road.sample_baked(maxf(0.0, distance - 2.0)) -
			road.sample_baked(minf(lane_length, distance + 2.0))).angle()
		var forks := loader_position + Vector2(7, 0).rotated(toward_ship)
		cargo_position = mount.lerp(forks, smoothstep(0.29, 0.43, transfer))
		cargo_position = cargo_position.lerp(road.sample_baked(lane_length),
			smoothstep(0.91, 1.0, transfer))
		cargo_angle = lerp_angle(0.0, toward_ship + PI / 2.0, smoothstep(0.37, 0.47, transfer))
		show_cargo = transfer < 0.99
		_draw_loader(loader_position, toward_ship, sin(smoothstep(0.26, 0.46, transfer) * PI))
	else:
		_draw_loader(loader_position, -PI / 2.0, 0.0)
	if show_ship:
		var flight_scale := 1.0 + flight_height * 0.24
		draw_set_transform(ship_position + Vector2(3, 4) + Vector2(12, 16) * flight_height)
		draw_rect(Rect2(-4.5, -10, 9, 20), Color(0.06, 0.11, 0.1, 0.35))
		Art.paint(self, ship_position, -PI / 2.0, flight_scale, Color.WHITE, false,
			loaded and transfer < 0.0)
		if loaded and transfer < 0.0:
			show_cargo = false
		draw_string(ThemeDB.fallback_font, ship_position + Vector2(-21, -13),
			str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#f1e1bd"))
	if show_cargo:
		draw_set_transform(cargo_position, cargo_angle)
		draw_texture(Art.CONTAINER, -Art.CONTAINER.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO)
	if loaded:
		var caption := "%d %s" % [cargo.amount, Model.batch_unit(cargo.resource)]
		var label_at := cargo_position + Vector2(8, -7)
		draw_string_outline(ThemeDB.fallback_font, label_at, caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color("#252d26"))
		draw_string(ThemeDB.fallback_font, label_at, caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f5dfab"))

func _draw_loader(at: Vector2, angle: float, extension: float) -> void:
	draw_set_transform(at + Vector2(1.4, 1.8), angle)
	draw_rect(Rect2(-5, -3, 10, 6), Color(0.12, 0.14, 0.13, 0.56))
	draw_set_transform(at, angle)
	draw_rect(Rect2(-5, -3.3, 10, 6.6), Color("#283631"))
	draw_rect(Rect2(-4.8, -1.9, 3.4, 3.8), Color("#d6a96b"))
	draw_rect(Rect2(-1.4, -2.5, 4.5, 5), Color("#b4b9a8"))
	draw_rect(Rect2(0.4, -1.5, 2.2, 3), Color("#46636a"))
	draw_rect(Rect2(3.1, -2.3, 1.6, 4.6), Color("#394341"))
	for y in [-1.7, 1.0]:
		draw_rect(Rect2(4.4, y, 4.0 + extension * 8.7, 0.9), Color("#bfbdab"))
	draw_set_transform(Vector2.ZERO)
