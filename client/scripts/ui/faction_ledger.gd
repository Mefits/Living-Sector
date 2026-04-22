extends PanelContainer

## Per-faction ledger: treasury, active subsidies, ship + facility counts.
## Pulls from `GameState.factions` (populated by faction_states WS +
## /api/report refreshes) and cross-references ship/facility dicts for
## member counts.
##
## Click a row → emit `faction_selected` so the rest of the UI can filter
## to that faction's members (future hook; not yet consumed).

signal faction_selected(faction_id: String)

@onready var tree: Tree = $VBox/Tree
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var close_button: Button = $VBox/TopRow/CloseButton

var _sort_column: String = "treasury"
var _sort_ascending: bool = false


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	tree.item_selected.connect(_on_row_activated)
	tree.column_title_clicked.connect(_on_column_clicked)
	_setup_columns()
	GameState.factions_updated.connect(_on_updated)
	GameState.contracts_updated.connect(_on_updated)  # subsidies roll in here too


func _setup_columns() -> void:
	tree.columns = 6
	tree.set_column_title(0, "Faction")
	tree.set_column_title(1, "Treasury")
	tree.set_column_title(2, "Subsidies")
	tree.set_column_title(3, "Ships")
	tree.set_column_title(4, "Facilities")
	tree.set_column_title(5, "System")
	tree.column_titles_visible = true
	tree.set_column_expand_ratio(0, 3)
	tree.set_column_expand_ratio(1, 2)
	tree.set_column_expand_ratio(2, 1)
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
	var cols := ["name", "treasury", "subsidies", "ships", "facilities", "system"]
	var new_col: String = cols[column]
	if new_col == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = new_col
		# Numbers descend by default, names ascend.
		_sort_ascending = new_col == "name" or new_col == "system"
	_refresh()


func _on_row_activated() -> void:
	var sel := tree.get_selected()
	if sel == null:
		return
	var fid: String = sel.get_metadata(0)
	if fid != "":
		faction_selected.emit(fid)


func _refresh() -> void:
	# Count ships + facilities per faction so we can show membership.
	var ships_per: Dictionary = {}
	for ship in GameState.ships.values():
		var fid := str(ship.get("faction_id", ""))
		ships_per[fid] = int(ships_per.get(fid, 0)) + 1
	var facs_per: Dictionary = {}
	for fac in GameState.facilities.values():
		var fid := str(fac.get("faction_id", ""))
		facs_per[fid] = int(facs_per.get(fid, 0)) + 1
	# Subsidies posted right now from the contracts cache (authoritative —
	# the server also sets `active_subsidies` but it only refreshes every
	# 32 ticks, so this re-count is fresher).
	var subsidies_per: Dictionary = {}
	for c in GameState.contracts.values():
		if str(c.get("contract_type", "")) != "subsidy":
			continue
		if str(c.get("status", "")) not in ["posted", "accepted", "picked_up"]:
			continue
		var fid = c.get("faction_id", "")
		if fid == null or str(fid) == "":
			continue
		subsidies_per[str(fid)] = int(subsidies_per.get(str(fid), 0)) + 1

	# Build a normalised row list.
	var rows: Array = []
	for slug in GameState.factions.keys():
		var fac: Dictionary = GameState.factions[slug]
		rows.append({
			"id": slug,
			"name": str(fac.get("name", slug)),
			"treasury": int(fac.get("treasury", 0)),
			"subsidies": int(subsidies_per.get(slug, fac.get("active_subsidies", 0))),
			"ships": int(ships_per.get(slug, 0)),
			"facilities": int(facs_per.get(slug, 0)),
			"system": str(fac.get("home_system", "")),
		})
	rows.sort_custom(_compare_rows)
	count_label.text = "%d factions" % rows.size()

	tree.clear()
	var root := tree.create_item()
	for r in rows:
		var row := tree.create_item(root)
		row.set_metadata(0, r["id"])
		row.set_text(0, r["name"])
		row.set_text(1, _format_credits(r["treasury"]))
		row.set_text(2, "%d" % r["subsidies"])
		row.set_text(3, "%d" % r["ships"])
		row.set_text(4, "%d" % r["facilities"])
		row.set_text(5, r["system"])

		# Colour the treasury: danger if near-zero, warn if <5k, success
		# otherwise. Same DANGER threshold the facility panel uses.
		if r["treasury"] < 1000:
			row.set_custom_color(1, ThemePalette.DANGER)
		elif r["treasury"] < 5000:
			row.set_custom_color(1, ThemePalette.WARN)
		else:
			row.set_custom_color(1, ThemePalette.SUCCESS)
		if r["subsidies"] > 0:
			row.set_custom_color(2, ThemePalette.WARN)


func _compare_rows(a: Dictionary, b: Dictionary) -> bool:
	var va: Variant = a.get(_sort_column, "")
	var vb: Variant = b.get(_sort_column, "")
	if _sort_ascending:
		return va < vb
	return va > vb


func _format_credits(n: int) -> String:
	## Cheap thousands separator — keeps the column narrow.
	var s := "%d" % abs(n)
	var out := ""
	var i := s.length()
	while i > 3:
		i -= 3
		out = "," + s.substr(i, 3) + out
	out = s.substr(0, i) + out
	return ("-" + out) if n < 0 else out
