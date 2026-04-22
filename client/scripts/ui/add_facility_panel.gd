extends PanelContainer

## God-mode Add Facility panel. Dropdowns rebuilt on each open.
## Emits create_requested(data) for main.gd to handle.

signal create_requested(data: Dictionary)

# Facility types — from the backend reference doc.
const FACILITY_TYPES := [
	"station", "outpost", "mining_rig", "refinery",
	"factory", "farm", "hub", "shipyard",
]

@onready var name_edit: LineEdit = $VBox/Fields/NameRow/NameEdit
@onready var type_opt: OptionButton = $VBox/Fields/TypeRow/TypeOpt
@onready var faction_opt: OptionButton = $VBox/Fields/FactionRow/FactionOpt
@onready var body_opt: OptionButton = $VBox/Fields/BodyRow/BodyOpt
@onready var credits_spin: SpinBox = $VBox/Fields/CreditsRow/CreditsSpin
@onready var create_button: Button = $VBox/Footer/CreateButton
@onready var cancel_button: Button = $VBox/Footer/CancelButton
@onready var close_button: Button = $VBox/TopRow/CloseButton


func _ready() -> void:
	visible = false
	create_button.pressed.connect(_on_create_pressed)
	cancel_button.pressed.connect(func(): visible = false)
	close_button.pressed.connect(func(): visible = false)


func open() -> void:
	_populate_types()
	_populate_factions()
	_populate_bodies()
	visible = true


func _populate_types() -> void:
	type_opt.clear()
	for t in FACILITY_TYPES:
		type_opt.add_item(str(t).replace("_", " ").capitalize())
		type_opt.set_item_metadata(type_opt.item_count - 1, t)


func _populate_factions() -> void:
	faction_opt.clear()
	var slugs: Array = GameState.factions.keys()
	slugs.sort()
	for slug in slugs:
		faction_opt.add_item(GameState.faction_name(slug))
		faction_opt.set_item_metadata(
			faction_opt.item_count - 1, slug
		)


func _populate_bodies() -> void:
	# Flatten systems[*].bodies; label with "Body (System)" so two
	# bodies with the same short name in different systems stay
	# distinguishable.
	body_opt.clear()
	var entries: Array = []
	for sys_id in GameState.systems:
		var sys: Dictionary = GameState.systems[sys_id]
		var sys_name: String = str(sys.get("name", sys_id))
		for body in sys.get("bodies", []):
			if not (body is Dictionary):
				continue
			var body_id: String = str(body.get("id", ""))
			var body_name: String = str(body.get("name", body_id))
			if body_id == "":
				continue
			entries.append({
				"body_id": body_id,
				"label": "%s (%s)" % [body_name, sys_name],
			})
	entries.sort_custom(
		func(a, b): return str(a.label) < str(b.label)
	)
	for e in entries:
		body_opt.add_item(e.label)
		body_opt.set_item_metadata(
			body_opt.item_count - 1, e.body_id
		)


func _selected_metadata(opt: OptionButton) -> Variant:
	var idx := opt.selected
	if idx < 0:
		return null
	return opt.get_item_metadata(idx)


func _on_create_pressed() -> void:
	# Field names match POST /api/admin/facilities (credits, not
	# starting_credits). location_name is derived by the server from
	# the name if not supplied, so we skip it here.
	var data := {
		"name": name_edit.text.strip_edges(),
		"type": _selected_metadata(type_opt),
		"faction_id": _selected_metadata(faction_opt),
		"body_id": _selected_metadata(body_opt),
		"credits": int(credits_spin.value),
	}
	create_requested.emit(data)
	visible = false
