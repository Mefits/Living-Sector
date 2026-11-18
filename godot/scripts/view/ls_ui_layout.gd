extends RefCounted
## Stateless layout model for the Figma native HUD.
## All positions use the *actual* logical Control size, after UI scaling.
## No access to World, N39, N158, window state or rendering.
const HEADER_H := 58.0
const FOOT_H := 24.0
const RAIL_W := 64.0
const OUTLINER_W := 264.0
const COMPACT_OUTLINER_W := 242.0
const GUTTER := 12.0

static func calculate(viewport: Vector2, header_height: float,
        window_open: bool, wants_outliner: bool,
        force_outliner_overlay: bool = false) -> Dictionary:
    var vw: float = maxf(viewport.x, 1.0)
    var vh: float = maxf(viewport.y, 1.0)
    var top: float = maxf(HEADER_H, header_height)
    var out_width: float = (OUTLINER_W if vw >= 1450.0
        else COMPACT_OUTLINER_W)
    # Preserve a usable central map. A temporary management window receives
    # priority over the outliner on laptops/high Windows DPI.
    var available: float = vw - RAIL_W - GUTTER * 3.0
    # Reserve a map area even when no management window is open.
    # Without this, the right sidebar consumes a scaled laptop viewport.
    var minimum_center: float = 485.0 if window_open else 420.0
    # A manual reveal may temporarily overlay the map on very narrow
    # displays; closing/reopening the sidebar must not trap the user.
    var overlay: bool = (
        force_outliner_overlay and wants_outliner and not window_open and
        available - out_width < minimum_center)
    var show_outliner: bool = (
        wants_outliner and (overlay or available - out_width >= minimum_center))
    var reserved_right: float = (
        out_width + GUTTER + 8.0 if show_outliner and not overlay else GUTTER)
    var left: float = minf(vw - GUTTER, RAIL_W + GUTTER)
    var right: float = maxf(left, vw - reserved_right)
    var available_height: float = maxf(0.0, vh - top - FOOT_H)
    var window_top: float = top + (
        64.0 if available_height >= 480.0 else 10.0)
    var window_bottom: float = maxf(window_top + 1.0, vh - FOOT_H - 12.0)
    var window_width: float = minf(930.0, maxf(0.0, right - left))
    var selection_width: float = minf(360.0, maxf(0.0, right - left))
    return {
        "viewport_width": vw, "viewport_height": vh, "top": top,
        "left": left, "right": right,
        "show_outliner": show_outliner, "out_width": out_width,
        "outliner_overlay": overlay,
        "window_top": window_top,
        "window_bottom": window_bottom,
        "window_right": minf(right, left + window_width),
        "selection_left": right - selection_width,
        "selection_right": right,
        "breadcrumb_right": minf(right, left + 376.0),
        "alert_left": maxf(left, right - 335.0),
        "alert_bottom": minf(vh - FOOT_H - 9.0, top + 380.0),
    }
