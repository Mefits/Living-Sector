extends PanelContainer

## Sortable list of every population in the simulation. Shows count,
## sentiment, food satisfaction, and total wealth. Click a row → select
## the pop on the details panel (via `population_selected`).

signal population_selected(pop_id: String)
## Fires when a row is clicked — the pop's parent facility location
## slug, so main.gd can camera-jump to the planet/station the pop
## lives on. Same contract as ship_list.location_selected.
signal location_selected(location: String)

@onready var tree: Tree = $VBox/Tree
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var close_button: Button = $VBox/TopRow/CloseButton

var _sort_column: String = "population_count"
var _sort_ascending: bool = false


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	tree.item_selected.connect(_on_row_activated)
	tree.column_title_clicked.connect(_on_column_clicked)
	_setup_columns()
	GameState.populations_updated.connect(_on_updated)


func _setup_columns() -> void:
	tree.columns = 6
	tree.set_column_title(0, "Population")
	tree.set_column_title(1, "Demographic")
	tree.set_column_title(2, "Count")
	tree.set_column_title(3, "Sentiment")
	tree.set_column_title(4, "Food Sat")
	tree.set_column_title(5, "Wealth")
	tree.column_titles_visible = true
	tree.set_column_expand_ratio(0, 3)
	tree.set_column_expand_ratio(1, 2)
	tree.set_column_expand_ratio(2, 2)
	tree.set_column_expand_ratio(3, 1)
	tree.set_column_expand_ratio(4, 1)
	tree.set_column_expand_ratio(5, 2)
	tree.select_mode = Tree.SELECT_SINGLE


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _on_updated() -> void:
	if visible:
		_refresh()


func _on_column_clicked(column: int, _mouse_button: int) -> void:
	var cols := ["label", "demographic", "population_count",
		"overall_sentiment", "food_satisfaction", "total_wealth"]
	var new_col: String = cols[column]
	if new_col == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = new_col
		_sort_ascending = new_col in ["label", "demographic"]
	_refresh()


func _on_row_activated() -> void:
	var sel := tree.get_selected()
	if sel == null:
		return
	var pid: String = sel.get_metadata(0)
	if pid != "":
		population_selected.emit(pid)
	# Column-0 metadata also carries the facility_location (set in
	# _refresh) so we can camera-jump on the same click. No extra
	# selection gesture — selecting a pop row IS the navigate.
	var loc: String = str(sel.get_metadata(1))
	if loc != "":
		location_selected.emit(loc)


func _refresh() -> void:
	var rows: Array = []
	for p in GameState.populations.values():
		rows.append(p)
	rows.sort_custom(_compare_rows)
	count_label.text = "%d populations" % rows.size()

	tree.clear()
	var root := tree.create_item()
	for p in rows:
		var row := tree.create_item(root)
		row.set_metadata(0, str(p.get("id", "")))
		# Stash the parent facility's location slug on the row so
		# _on_row_activated can emit `location_selected` without a
		# second lookup. Server fills this as `facility_location`.
		row.set_metadata(1, str(p.get("facility_location", "")))
		row.set_text(0, str(p.get("label", p.get("id", "?"))))
		row.set_text(1, str(p.get("demographic", "-")))
		row.set_text(2, _format_count(int(p.get("population_count", 0))))
		var sent: int = int(p.get("overall_sentiment", 0))
		row.set_text(3, "%d" % sent)
		_color_sentiment(row, 3, sent)
		var fs: int = int(p.get("food_satisfaction", 0))
		row.set_text(4, "%d" % fs)
		_color_sentiment(row, 4, fs)
		row.set_text(5, _format_count(int(p.get("total_wealth", 0))))


func _color_sentiment(row: TreeItem, col: int, v: int) -> void:
	if v >= 70:
		row.set_custom_color(col, ThemePalette.SUCCESS)
	elif v >= 40:
		row.set_custom_color(col, ThemePalette.WARN)
	else:
		row.set_custom_color(col, ThemePalette.DANGER)


func _compare_rows(a: Dictionary, b: Dictionary) -> bool:
	var va: Variant = a.get(_sort_column, "")
	var vb: Variant = b.get(_sort_column, "")
	# Normalise numeric vs. string compare.
	if va is int or va is float:
		vb = float(vb)
		va = float(va)
	else:
		va = str(va)
		vb = str(vb)
	if _sort_ascending:
		return va < vb
	return va > vb


func _format_count(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (float(n) / 1_000_000.0)
	if n >= 1_000:
		return "%.1fk" % (float(n) / 1_000.0)
	return "%d" % n
