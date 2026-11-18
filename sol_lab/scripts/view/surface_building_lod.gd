extends RefCounted
## Sol Lab-only, read-only level of detail for ground buildings.
## Sizes are in viewport logical pixels. No fake N39 objects.
const REVEAL_START_PX: float = 14.0
const REVEAL_FULL_PX: float = 42.0
const LABEL_START_PX: float = 60.0
const LABEL_FULL_PX: float = 138.0
const ROAD_START_PX: float = 55.0
const ROAD_FULL_PX: float = 110.0
const ICON_RELATIVE_RADIUS: float = 0.07
const ICON_MINIMUM_DETAIL_PX: float = 1.2

static func _smoothstep(value: float) -> float:
    var t: float = clampf(value, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

static func _between(radius: float, from_px: float,
        to_px: float, ui_scale: float) -> float:
    var normalized_scale: float = maxf(ui_scale, 0.01)
    var lo: float = from_px / normalized_scale
    var hi: float = to_px / normalized_scale
    return _smoothstep((radius - lo) / (hi - lo))

static func icon_half_size(radius: float, ui_scale: float = 1.0) -> float:
    # Unlike the old 4.5..9px clamp, grows through every zoom level.
    return maxf(0.0, radius) * ICON_RELATIVE_RADIUS + (
        ICON_MINIMUM_DETAIL_PX / maxf(ui_scale, 0.01))

static func visibility(radius: float, ui_scale: float = 1.0) -> float:
    return _between(radius, REVEAL_START_PX, REVEAL_FULL_PX, ui_scale)

static func label_visibility(radius: float,
        ui_scale: float = 1.0) -> float:
    return _between(radius, LABEL_START_PX, LABEL_FULL_PX, ui_scale)

static func road_visibility(radius: float, ui_scale: float = 1.0) -> float:
    return _between(radius, ROAD_START_PX, ROAD_FULL_PX, ui_scale)
