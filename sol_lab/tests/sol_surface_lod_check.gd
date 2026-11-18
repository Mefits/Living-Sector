extends SceneTree
## Regression: sizes must keep growing through the reported x18, 24, 55, 96 plateaus.
const LOD = preload("res://scripts/view/surface_building_lod.gd")

func _initialize() -> void:
    var samples: Array[float] = [12.0, 18.0, 24.0, 40.0,
        55.0, 96.0, 150.0, 240.0, 460.0]
    var previous_size: float = -1.0
    var previous_alpha: float = -1.0
    var okay: bool = true
    for radius in samples:
        var icon_size: float = LOD.icon_half_size(radius)
        var alpha: float = LOD.visibility(radius)
        okay = okay and icon_size > previous_size
        okay = okay and alpha >= previous_alpha
        previous_size = icon_size
        previous_alpha = alpha
    okay = okay and LOD.visibility(14.0) == 0.0
    okay = okay and LOD.visibility(42.0) == 1.0
    okay = okay and LOD.visibility(24.0) > 0.0
    okay = okay and LOD.visibility(24.0) < 1.0
    okay = okay and LOD.icon_half_size(55.0) < LOD.icon_half_size(96.0)
    okay = okay and LOD.icon_half_size(96.0) < LOD.icon_half_size(240.0)
    okay = okay and LOD.label_visibility(60.0) == 0.0
    okay = okay and LOD.label_visibility(100.0) > 0.0
    okay = okay and LOD.label_visibility(138.0) == 1.0
    okay = okay and LOD.road_visibility(55.0) == 0.0
    okay = okay and LOD.road_visibility(110.0) == 1.0
    okay = okay and is_equal_approx(
        LOD.visibility(28.0, 1.0), LOD.visibility(14.0, 2.0))
    if okay:
        print("SOL_SURFACE_LOD_PASS")
        quit(0)
    else:
        push_error("SOL_SURFACE_LOD_FAIL")
        quit(1)
