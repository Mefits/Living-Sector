extends RefCounted

const EMPTY := preload("res://sol_lab/earth_port/assets/empty.png")
const CONTAINER := preload("res://sol_lab/earth_port/assets/container.png")
const COLONIZER := preload("res://sol_lab/earth_port/assets/colonizer.png")

static func paint(canvas: CanvasItem, position: Vector2, heading: float,
		size: float, tint: Color, colonizer: bool, loaded: bool) -> void:
	var hull := COLONIZER if colonizer else EMPTY
	canvas.draw_set_transform(position, heading + PI / 2.0, Vector2.ONE * size)
	canvas.draw_texture(hull, -hull.get_size() / 2.0, tint)
	if loaded and not colonizer:
		canvas.draw_texture(CONTAINER, -CONTAINER.get_size() / 2.0, tint)
	canvas.draw_set_transform(Vector2.ZERO)
