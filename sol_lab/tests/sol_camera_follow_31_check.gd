extends SceneTree
## Sol Lab 3.1 camera follow threshold, independent of globe detail LOD.
const StarView = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    var view = StarView.new()
    var okay: bool = true
    okay = okay and is_equal_approx(view.FOLLOW_START_ZOOM, 3.1)
    okay = okay and not view._follow_threshold_reached(1.0)
    okay = okay and not view._follow_threshold_reached(3.099)
    okay = okay and view._follow_threshold_reached(3.1)
    okay = okay and view._follow_threshold_reached(3.101)
    okay = okay and view._follow_threshold_reached(8.0)
    okay = okay and view._follow_threshold_reached(96.0)
    view.free()
    if okay:
        print("SOL_CAMERA_FOLLOW_31_PASS")
        quit(0)
    else:
        push_error("SOL_CAMERA_FOLLOW_31_FAIL")
        quit(1)
