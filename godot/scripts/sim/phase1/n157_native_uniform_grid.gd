extends RefCounted
## N157 frozen sim_core/spatial/grid.rs::UniformGrid<T> (source-backed).
## Spatial ACCELERATOR only, no ship motion, random IDs or new scene nodes.
## Rust uses floor(x/cell_size), including on negative universe positions.
## The stable-ID strings and Vector2 coordinates are supplied by the ECS.
var _cell_size: float = 10.0
var _cells: Dictionary = {}
var _positions: Dictionary = {}

func configure(cell_size: float = 10.0) -> bool:
    if not is_finite(cell_size) or cell_size <= 0.0:
        return false
    _cell_size = cell_size
    _cells.clear()
    _positions.clear()
    return true

func cell_size() -> float:
    return _cell_size

func size() -> int:
    return _positions.size()

func is_empty() -> bool:
    return _positions.is_empty()

func cell_of(position: Vector2) -> Vector2i:
    return Vector2i(
        int(floor(float(position.x) / _cell_size)),
        int(floor(float(position.y) / _cell_size)))

func insert(id: String, position: Vector2) -> bool:
    if id.is_empty() or not _finite_pos(position):
        return false
    var new_cell: Vector2i = cell_of(position)
    if _positions.has(id):
        var old_cell: Vector2i = cell_of(_positions[id])
        if old_cell == new_cell:
            _positions[id] = position
            return true
        _remove_bucket(old_cell, id)
    if not _cells.has(new_cell):
        _cells[new_cell] = {}
    _cells[new_cell][id] = true
    _positions[id] = position
    return true

func move_to(id: String, position: Vector2) -> bool:
    return insert(id, position)

func remove(id: String) -> Variant:
    if not _positions.has(id):
        return null
    var old: Vector2 = _positions[id]
    _positions.erase(id)
    _remove_bucket(cell_of(old), id)
    return old

func position(id: String) -> Variant:
    return _positions.get(id, null)

## Source Rust query_radius exact distance-squared after bucket rectangle
## selection. Radius <=0 returns empty, even at an exact center point.
func query_radius(center: Vector2, radius: float) -> Array:
    if radius <= 0.0 or not is_finite(radius) or not _finite_pos(center):
        return []
    var radius_squared: float = radius * radius
    if not is_finite(radius_squared):
        return []
    var min_cell: Vector2i = cell_of(center - Vector2(radius, radius))
    var max_cell: Vector2i = cell_of(center + Vector2(radius, radius))
    var out: Array = []
    for cx in range(min_cell.x, max_cell.x + 1):
        for cy in range(min_cell.y, max_cell.y + 1):
            var cell: Vector2i = Vector2i(cx, cy)
            if not _cells.has(cell):
                continue
            for id in _cells[cell]:
                var p: Vector2 = _positions[id]
                if p.distance_squared_to(center) <= radius_squared:
                    out.append(id)
    # Rust HashMap returns unspecified order; sort for deterministic Godot.
    out.sort()
    return out

func nearest(center: Vector2, max_radius: float) -> Dictionary:
    var candidates: Array = query_radius(center, max_radius)
    var best_distance: float = INF
    var best_id: String = ""
    for id in candidates:
        var distance: float = _positions[id].distance_to(center)
        if distance < best_distance:
            best_distance = distance
            best_id = id
    return {} if best_id.is_empty() else {
        "id": best_id, "distance": best_distance}

func rebuild_from(entries: Dictionary) -> bool:
    var staged = get_script().new()
    if not staged.configure(_cell_size):
        return false
    var ids: Array = entries.keys()
    ids.sort()
    for id in ids:
        if not (id is String) or not (entries[id] is Vector2):
            return false
        if not staged.insert(id, entries[id]):
            return false
    _cells = staged._cells.duplicate(true)
    _positions = staged._positions.duplicate(true)
    return true

func snapshot_positions() -> Dictionary:
    return _positions.duplicate(true)

func _remove_bucket(cell: Vector2i, id: String) -> void:
    if not _cells.has(cell):
        return
    _cells[cell].erase(id)
    if _cells[cell].is_empty():
        _cells.erase(cell)

func _finite_pos(p: Vector2) -> bool:
    return is_finite(p.x) and is_finite(p.y)
