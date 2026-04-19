extends PopupMenu

## Right-click context menu for entities.
## Shows different options based on entity type.

signal action_selected(action: String, entity_id: String, entity_type: String)

var _entity_id: String = ""
var _entity_type: String = ""

const SHIP_ACTIONS := ["Inspect", "Follow", "POV", "Destroy"]
const FACILITY_ACTIONS := [
	"Inspect", "Follow", "View Market", "Edit Supply", "Destroy",
]
const BODY_ACTIONS := ["Inspect", "Focus"]


func _ready() -> void:
	id_pressed.connect(_on_item_pressed)


func show_for_entity(
	id: String, type: String, screen_pos: Vector2
) -> void:
	_entity_id = id
	_entity_type = type
	clear()

	var actions: Array
	match type:
		"ship":
			actions = SHIP_ACTIONS
		"facility":
			actions = FACILITY_ACTIONS
		"body":
			actions = BODY_ACTIONS
		_:
			return

	for i in range(actions.size()):
		add_item(actions[i], i)

	position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	popup()


func _on_item_pressed(id: int) -> void:
	var label: String = get_item_text(id)
	action_selected.emit(label, _entity_id, _entity_type)
