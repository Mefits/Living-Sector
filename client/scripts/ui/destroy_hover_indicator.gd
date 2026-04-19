extends Control

## Red ring that follows the destroy-mode hover target. Set by
## main.gd every frame during destroy mode — visible when the cursor
## is over a valid ship/facility, hidden when hovering empty space.

const RING_RADIUS := 26.0
const RING_THICKNESS := 2.5
const RING_COLOR := Color(1.0, 0.25, 0.25, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(RING_RADIUS * 2.0, RING_RADIUS * 2.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	visible = false


func show_at(screen_pos: Vector2) -> void:
	# Center the control on the target. Offset by half-size since
	# position is the top-left corner.
	position = screen_pos - size * 0.5
	visible = true
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_arc(center, RING_RADIUS, 0.0, TAU, 48, RING_COLOR, RING_THICKNESS, true)
