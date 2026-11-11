extends Control
## Read-only map of actual native system positions. Godot CanvasItem rendering,
## no HTML or handmade browser renderer. No invented routes or ship positions.

signal system_selected(world: Dictionary)

var worlds: Array = []
var _pins: Array = []
var _selected_id: String = ""

func set_worlds(new_worlds: Array) -> void:
    worlds = new_worlds
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1421"), true)
    _pins.clear()
    if worlds.is_empty():
        return
    var radius: float = 1.0
    for item in worlds:
        var coords: Array = item.get("system", {}).get("universe_offset", [0, 0])
        if coords.size() >= 2:
            radius = maxf(radius, absf(float(coords[0])), absf(float(coords[1])))
    var unit: float = minf(
        maxf(40.0, size.x - 120.0),
        maxf(40.0, size.y - 120.0)
    ) * 0.5 / radius
    var center: Vector2 = size * 0.5
    var font: Font = get_theme_default_font()
    for item in worlds:
        var system: Dictionary = item.get("system", {})
        var coords: Array = system.get("universe_offset", [0, 0])
        if coords.size() < 2:
            continue
        var pos: Vector2 = center + Vector2(
            float(coords[0]) * unit,
            -float(coords[1]) * unit
        )
        var selected: bool = str(system.get("id", "")) == _selected_id
        draw_arc(pos, 16.0, 0.0, TAU, 32,
            Color("#82c7d8") if selected else Color("#344c63"), 1.5)
        draw_circle(pos, 5.5 if selected else 4.0,
            Color("#b5edfc") if selected else Color("#6c9eac"))
        draw_string(font, pos + Vector2(13, -9),
            str(system.get("name", "—")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            Color("#e2f0f4"))
        _pins.append({"world": item, "pos": pos})

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
            return
        for pin in _pins:
            if event.position.distance_to(pin["pos"]) <= 26.0:
                var item: Dictionary = pin["world"]
                _selected_id = str(item.get("system", {}).get("id", ""))
                queue_redraw()
                system_selected.emit(item)
                accept_event()
                return
