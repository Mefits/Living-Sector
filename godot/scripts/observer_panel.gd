extends PanelContainer
## N20 observational UI: no command buttons until real executor is wired.
const ObserverProjection = preload("res://scripts/sim/observer/observer_projection.gd")
var _label: RichTextLabel

func _ready() -> void:
    custom_minimum_size = Vector2(380, 320)
    var column := VBoxContainer.new()
    add_child(column)
    var heading := Label.new()
    heading.text = "НАБЛЮДЕНИЕ / УПРАВЛЕНИЕ · N20"
    column.add_child(heading)
    _label = RichTextLabel.new()
    _label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _label.selection_enabled = true
    column.add_child(_label)
    show_observation(0, "unselected", {})

func show_observation(tick: int, faction_id: String, state: Dictionary) -> void:
    var text_value: String = ObserverProjection.describe(ObserverProjection.build(tick, faction_id, state))
    if _label:
        _label.text = text_value
