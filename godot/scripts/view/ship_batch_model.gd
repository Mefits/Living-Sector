extends RefCounted
## N22 CODE_UNVERIFIED. Render-only projection: never advances ships or changes cargo.
## Input records must contain native world-space position (Vector2 or [x,y]).
## No invented movement from origin/destination or visual interpolation across game ticks.

const MAX_SHIPS: int = 100000
var _records: Array[Dictionary] = []
var _by_id: Dictionary = {}

func set_records(records: Array) -> bool:
    if records.size() > MAX_SHIPS:
        return false
    var next_records: Array[Dictionary] = []
    var next_ids: Dictionary = {}
    for raw in records:
        if not raw is Dictionary:
            return false
        var record: Dictionary = raw
        var id: String = str(record.get("id", ""))
        if id.is_empty() or next_ids.has(id):
            return false
        var position: Variant = record.get("position", null)
        var point: Vector2
        if position is Vector2:
            point = position
        elif position is Array and position.size() == 2:
            if not (position[0] is float or position[0] is int):
                return false
            if not (position[1] is float or position[1] is int):
                return false
            point = Vector2(float(position[0]), float(position[1]))
        else:
            return false
        if not is_finite(point.x) or not is_finite(point.y):
            return false
        var kind: String = str(record.get("class", "unknown"))
        var faction: String = str(record.get("faction_id", ""))
        var entry: Dictionary = {"id": id, "position": point, "class": kind, "faction_id": faction}
        next_records.append(entry)
        next_ids[id] = entry
    next_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    _records = next_records
    _by_id = next_ids
    return true

func total_count() -> int:
    return _records.size()

func get_record(ship_id: String) -> Dictionary:
    return _by_id.get(ship_id, {}).duplicate()

func visible_records(world_rect: Rect2, padding: float = 0.0) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var margin: float = maxf(padding, 0.0)
    var bounds: Rect2 = world_rect.grow(margin).abs()
    for record in _records:
        if bounds.has_point(record["position"]):
            result.append(record)
    return result

func pick(world_point: Vector2, max_distance: float) -> String:
    var best_id: String = ""
    var best_squared: float = maxf(max_distance, 0.0) * maxf(max_distance, 0.0)
    for record in _records:
        var distance: float = world_point.distance_squared_to(record["position"])
        if distance <= best_squared:
            if best_id.is_empty() or distance < best_squared or str(record["id"]) < best_id:
                best_squared = distance
                best_id = record["id"]
    return best_id
