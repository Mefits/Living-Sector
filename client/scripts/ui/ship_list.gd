extends PanelContainer

## Toggleable ship list panel with sortable columns.
## Click a row to select and follow that ship.

signal ship_selected(ship_id: String)
signal location_selected(location: String)

var _sort_column := "name"
var _sort_ascending := true
var _visible_ships: Array = []
var _filter_text := ""

@onready var search_box: LineEdit = $VBox/TopRow/SearchBox
@onready var ship_tree: Tree = $VBox/ShipTree
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var close_button: Button = $VBox/TopRow/CloseButton


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	search_box.text_changed.connect(_on_search_changed)
	ship_tree.item_selected.connect(_on_row_activated)
	ship_tree.column_title_clicked.connect(_on_column_clicked)

	_setup_columns()
	GameState.tick_updated.connect(_on_tick)


func _setup_columns() -> void:
	ship_tree.columns = 6
	ship_tree.set_column_title(0, "Name")
	ship_tree.set_column_title(1, "Class")
	ship_tree.set_column_title(2, "Location")
	ship_tree.set_column_title(3, "Goal")
	ship_tree.set_column_title(4, "Fuel")
	ship_tree.set_column_title(5, "!")  # Warning column
	ship_tree.column_titles_visible = true

	ship_tree.set_column_expand_ratio(0, 3)
	ship_tree.set_column_expand_ratio(1, 2)
	ship_tree.set_column_expand_ratio(2, 3)
	ship_tree.set_column_expand_ratio(3, 2)
	ship_tree.set_column_expand_ratio(4, 1)
	ship_tree.set_column_expand_ratio(5, 1)
	ship_tree.select_mode = Tree.SELECT_SINGLE


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _on_tick(_tick: int) -> void:
	if visible:
		_refresh()


func _on_search_changed(text: String) -> void:
	_filter_text = text.to_lower()
	_refresh()


func _on_column_clicked(column: int, _mouse_button: int) -> void:
	var col_names := ["name", "class", "location", "goal", "fuel"]
	var new_col: String = col_names[column]
	if new_col == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = new_col
		_sort_ascending = true
	_refresh()


func _on_row_activated() -> void:
	var selected := ship_tree.get_selected()
	if not selected:
		return
	var col := ship_tree.get_selected_column()
	var ship_id: String = selected.get_metadata(0)
	if ship_id == "":
		return

	if col == 2:
		# Location column — navigate to destination
		var loc_text: String = selected.get_text(2)
		if loc_text.begins_with("-> "):
			loc_text = loc_text.substr(3)
		location_selected.emit(loc_text)
	else:
		# Name/Class or any other column — select ship
		ship_selected.emit(ship_id)


func _refresh() -> void:
	# Collect and filter ships
	_visible_ships.clear()
	for ship in GameState.ships.values():
		if _filter_text != "":
			var name_lower: String = str(
				ship.get("name", "")
			).to_lower()
			var class_lower: String = str(
				ship.get("class", "")
			).to_lower()
			if (
				_filter_text not in name_lower
				and _filter_text not in class_lower
			):
				continue
		_visible_ships.append(ship)

	# Sort
	_visible_ships.sort_custom(_compare_ships)

	# Update count
	count_label.text = "%d/%d" % [
		_visible_ships.size(), GameState.ships.size()
	]

	# Rebuild tree
	ship_tree.clear()
	var root := ship_tree.create_item()

	for ship in _visible_ships:
		var row := ship_tree.create_item(root)
		row.set_metadata(0, ship.get("id", ""))

		row.set_text(0, str(ship.get("name", "?")))

		var ship_class: String = str(ship.get("class", "?"))
		row.set_text(1, ship_class.capitalize())

		# Location / transit
		var loc = ship.get("location")
		var transit = ship.get("transit")
		if loc != null and str(loc) != "null" and str(loc) != "":
			row.set_text(2, str(loc))
		elif transit is Dictionary and transit.get("to"):
			row.set_text(2, "-> %s" % str(transit["to"]))
		else:
			row.set_text(2, "in space")

		row.set_text(3, GameState.goal_label(ship.get("current_goal")))

		var fuel: float = float(ship.get("fuel", 0))
		var fuel_cap: float = float(ship.get("fuel_capacity", 1))
		var fuel_pct: int = int(fuel / fuel_cap * 100) if fuel_cap > 0 else 0
		row.set_text(4, "%d%%" % fuel_pct)
		# Low fuel reads red
		if fuel_pct < 25:
			row.set_custom_color(4, ThemePalette.DANGER)

		# Warning column: compact strike indicator. "$" = broke, "H" = hoarding,
		# "i" = idle streak. Count shown if > 1.
		var broke: int = int(ship.get("broke_strikes", 0))
		var hoard: int = int(ship.get("hoard_strikes", 0))
		var idle: int = int(ship.get("idle_ticks", 0))
		var warn_parts: PackedStringArray = PackedStringArray()
		if broke > 0:
			warn_parts.append("$%d" % broke)
		if hoard > 0:
			warn_parts.append("H%d" % hoard)
		# Only surface idle when it's been going for a while
		if idle >= 10:
			warn_parts.append("i")
		var warn_text: String = " ".join(warn_parts)
		row.set_text(5, warn_text)
		if broke >= 2 or hoard >= 2:
			row.set_custom_color(5, ThemePalette.DANGER)
		elif warn_text != "":
			row.set_custom_color(5, ThemePalette.WARN)


func _compare_ships(a: Dictionary, b: Dictionary) -> bool:
	var va: Variant
	var vb: Variant
	match _sort_column:
		"name":
			va = str(a.get("name", ""))
			vb = str(b.get("name", ""))
		"class":
			va = str(a.get("class", ""))
			vb = str(b.get("class", ""))
		"location":
			va = str(a.get("location", a.get("transit", {}).get("to", "")))
			vb = str(b.get("location", b.get("transit", {}).get("to", "")))
		"goal":
			va = str(a.get("current_goal", ""))
			vb = str(b.get("current_goal", ""))
		"fuel":
			var fa: float = float(a.get("fuel", 0))
			var fc: float = float(a.get("fuel_capacity", 1))
			var fb: float = float(b.get("fuel", 0))
			var fbc: float = float(b.get("fuel_capacity", 1))
			va = fa / fc if fc > 0 else 0.0
			vb = fb / fbc if fbc > 0 else 0.0
		_:
			va = ""
			vb = ""

	if _sort_ascending:
		return va < vb
	return va > vb
