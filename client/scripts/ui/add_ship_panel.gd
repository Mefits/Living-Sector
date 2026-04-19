extends PanelContainer

## God-mode Add Ship panel. Collects the minimum fields, emits a
## `create_requested(data)` signal for main.gd to handle (currently
## a stub log + toast). Dropdowns are rebuilt on each open so new
## factions / facilities appear without needing to reopen the panel.

signal create_requested(data: Dictionary)

# Ship classes — mirrors CLASS_MODELS keys in scripts/world/ship.gd.
const SHIP_CLASSES := [
	"freighter", "hauler", "courier", "tanker", "miner",
]

@onready var name_edit: LineEdit = $VBox/Fields/NameRow/NameEdit
@onready var faction_opt: OptionButton = $VBox/Fields/FactionRow/FactionOpt
@onready var class_opt: OptionButton = $VBox/Fields/ClassRow/ClassOpt
@onready var location_opt: OptionButton = $VBox/Fields/LocationRow/LocationOpt
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
	_populate_factions()
	_populate_classes()
	_populate_locations()
	visible = true


func _populate_factions() -> void:
	faction_opt.clear()
	var slugs: Array = GameState.factions.keys()
	slugs.sort()
	for slug in slugs:
		faction_opt.add_item(GameState.faction_name(slug))
		faction_opt.set_item_metadata(
			faction_opt.item_count - 1, slug
		)


func _populate_classes() -> void:
	class_opt.clear()
	for c in SHIP_CLASSES:
		class_opt.add_item(str(c).capitalize())
		class_opt.set_item_metadata(class_opt.item_count - 1, c)


func _populate_locations() -> void:
	location_opt.clear()
	var facs: Array = GameState.facilities.values()
	facs.sort_custom(
		func(a, b): return str(a.get("name", "")) < str(b.get("name", ""))
	)
	for fac in facs:
		var loc: String = str(fac.get("location", ""))
		if loc == "":
			continue
		location_opt.add_item(str(fac.get("name", loc)))
		location_opt.set_item_metadata(
			location_opt.item_count - 1, loc
		)


func _selected_metadata(opt: OptionButton) -> Variant:
	var idx := opt.selected
	if idx < 0:
		return null
	return opt.get_item_metadata(idx)


func _on_create_pressed() -> void:
	# Field names match POST /api/admin/ships (location, credits —
	# not starting_location / starting_credits).
	var data := {
		"name": name_edit.text.strip_edges(),
		"faction_id": _selected_metadata(faction_opt),
		"class": _selected_metadata(class_opt),
		"location": _selected_metadata(location_opt),
		"credits": int(credits_spin.value),
	}
	create_requested.emit(data)
	visible = false
