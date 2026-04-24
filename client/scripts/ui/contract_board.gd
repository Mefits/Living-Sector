extends PanelContainer

## Live view of the simulator's contract board — Delivery, Courier,
## Passenger, Subsidy, Supply, CrewMission all in one sortable table.
##
## Data source: `GameState.contracts` (refreshed every ~4s from the
## `contract_states` WS broadcast, or full refresh from `/api/contracts`).
##
## Columns: kind, status, commodity, qty, source → dest, payment, age,
## faction, min_rep. Click a row → emit `contract_selected` with the
## contract id; the details panel renders the full record.

signal contract_selected(contract_id: String)

## Max rows shown per page. The full contract board can grow to
## 400+ entries; rendering all of them into a Tree every refresh
## is what made this panel laggy. Pagination keeps per-refresh
## work bounded.
const PAGE_SIZE: int = 50

var _filter_kind: String = ""      # "" = all
var _filter_status: String = ""    # "" = all
var _show_expired: bool = false    # hide expired rows by default (they pile up fast)
var _sort_column: String = "age"
var _sort_ascending: bool = true
var _visible_contracts: Array = []
var _page: int = 0                 # 0-indexed page into _visible_contracts

@onready var kind_filter: OptionButton = $VBox/TopRow/KindFilter
@onready var status_filter: OptionButton = $VBox/TopRow/StatusFilter
@onready var show_expired_check: CheckBox = $VBox/TopRow/ShowExpired
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var close_button: Button = $VBox/TopRow/CloseButton
@onready var tree: Tree = $VBox/Tree
@onready var prev_button: Button = $VBox/BottomRow/PrevButton
@onready var next_button: Button = $VBox/BottomRow/NextButton
@onready var page_label: Label = $VBox/BottomRow/PageLabel

# Known kinds / statuses from the Rust ContractType + ContractStatus enums.
const KIND_OPTIONS := [
	["All", ""],
	["Delivery", "delivery"],
	["Courier", "courier"],
	["Passenger", "passenger"],
	["Subsidy", "subsidy"],
	["Supply", "supply"],
	["Crew Mission", "crew_mission"],
]

const STATUS_OPTIONS := [
	["All", ""],
	["Posted", "posted"],
	["Accepted", "accepted"],
	["Picked Up", "picked_up"],
	["Delivered", "delivered"],
	["Paid", "paid"],
	["Expired", "expired"],
]


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	for opt in KIND_OPTIONS:
		kind_filter.add_item(opt[0])
		kind_filter.set_item_metadata(kind_filter.item_count - 1, opt[1])
	for opt in STATUS_OPTIONS:
		status_filter.add_item(opt[0])
		status_filter.set_item_metadata(status_filter.item_count - 1, opt[1])
	kind_filter.item_selected.connect(_on_kind_changed)
	status_filter.item_selected.connect(_on_status_changed)
	show_expired_check.button_pressed = _show_expired
	show_expired_check.toggled.connect(_on_show_expired_toggled)
	prev_button.pressed.connect(_on_prev_page)
	next_button.pressed.connect(_on_next_page)
	tree.item_selected.connect(_on_row_activated)
	tree.column_title_clicked.connect(_on_column_clicked)
	_setup_columns()
	# Refresh on contract-board updates (every ~4s from the
	# `contract_states` WS broadcast) rather than every tick.
	# Per-tick refreshes were the lag source — rebuilding a
	# 200+ row Tree at 8 Hz is expensive even on desktop.
	# The age column will be up to ~4s stale; that's fine for
	# this panel's purpose.
	GameState.contracts_updated.connect(_on_contracts_updated)


func _setup_columns() -> void:
	tree.columns = 9
	tree.set_column_title(0, "Kind")
	tree.set_column_title(1, "Status")
	tree.set_column_title(2, "Item")
	tree.set_column_title(3, "Qty")
	tree.set_column_title(4, "Source → Dest")
	tree.set_column_title(5, "Pay")
	tree.set_column_title(6, "Age")
	tree.set_column_title(7, "Faction")
	tree.set_column_title(8, "Rep")
	tree.column_titles_visible = true
	tree.set_column_expand_ratio(0, 2)
	tree.set_column_expand_ratio(1, 1)
	tree.set_column_expand_ratio(2, 2)
	tree.set_column_expand_ratio(3, 1)
	tree.set_column_expand_ratio(4, 4)
	tree.set_column_expand_ratio(5, 1)
	tree.set_column_expand_ratio(6, 1)
	tree.set_column_expand_ratio(7, 2)
	tree.set_column_expand_ratio(8, 1)
	tree.select_mode = Tree.SELECT_SINGLE


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _on_contracts_updated() -> void:
	if visible:
		_refresh()


func _on_kind_changed(i: int) -> void:
	_filter_kind = kind_filter.get_item_metadata(i)
	_page = 0
	_refresh()


func _on_status_changed(i: int) -> void:
	_filter_status = status_filter.get_item_metadata(i)
	_page = 0
	_refresh()


func _on_show_expired_toggled(pressed: bool) -> void:
	_show_expired = pressed
	_page = 0
	_refresh()


func _on_prev_page() -> void:
	if _page > 0:
		_page -= 1
		_refresh()


func _on_next_page() -> void:
	var total_pages: int = _total_pages()
	if _page + 1 < total_pages:
		_page += 1
		_refresh()


func _total_pages() -> int:
	if _visible_contracts.is_empty():
		return 1
	return int(ceil(float(_visible_contracts.size()) / float(PAGE_SIZE)))


func _on_column_clicked(column: int, _mouse_button: int) -> void:
	var cols := ["kind", "status", "commodity", "quantity", "source",
		"payment", "age", "faction", "min_rep"]
	var new_col: String = cols[column]
	if new_col == _sort_column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = new_col
		_sort_ascending = true
	_refresh()


func _on_row_activated() -> void:
	var sel := tree.get_selected()
	if sel == null:
		return
	var cid: String = sel.get_metadata(0)
	if cid != "":
		contract_selected.emit(cid)


func _refresh() -> void:
	_visible_contracts.clear()
	for c in GameState.contracts.values():
		var status: String = str(c.get("status", ""))
		if _filter_kind != "" and str(c.get("contract_type", "")) != _filter_kind:
			continue
		if _filter_status != "" and status != _filter_status:
			continue
		# Hide expired unless the user explicitly asks for them
		# (either by toggling "Show expired" or by selecting
		# "Expired" in the status filter). They accumulate fast
		# and are usually not actionable.
		if not _show_expired and status == "expired" and _filter_status != "expired":
			continue
		_visible_contracts.append(c)

	_visible_contracts.sort_custom(_compare_contracts)
	# Clamp the current page in case filtering shrank the list below it.
	var total_pages: int = _total_pages()
	if _page >= total_pages:
		_page = total_pages - 1
	if _page < 0:
		_page = 0

	# Slice the visible-page window.
	var start_idx: int = _page * PAGE_SIZE
	var end_idx: int = min(start_idx + PAGE_SIZE, _visible_contracts.size())
	var page_slice: Array = _visible_contracts.slice(start_idx, end_idx)

	count_label.text = "%d shown · %d total" % [
		_visible_contracts.size(),
		GameState.contracts.size(),
	]
	page_label.text = "Page %d/%d" % [_page + 1, total_pages]
	prev_button.disabled = _page == 0
	next_button.disabled = _page + 1 >= total_pages

	tree.clear()
	var root := tree.create_item()
	for c in page_slice:
		var row := tree.create_item(root)
		row.set_metadata(0, str(c.get("id", "")))
		row.set_text(0, str(c.get("contract_type", "?")).capitalize())
		row.set_text(1, str(c.get("status", "?")).capitalize())
		row.set_text(2, str(c.get("commodity", "-")))
		row.set_text(3, "%d" % int(c.get("quantity", 0)))
		row.set_text(4, "%s → %s" % [
			str(c.get("source_location", "?")),
			str(c.get("destination_location", "?")),
		])
		row.set_text(5, "%d" % int(c.get("payment", 0)))
		var posted_at: int = int(c.get("posted_at_tick", 0))
		row.set_text(6, "%d" % max(0, GameState.tick - posted_at))
		var fac = c.get("faction_id")
		row.set_text(7, GameState.faction_name(fac) if fac != null else "-")
		var min_rep: int = int(c.get("min_reputation", 0))
		row.set_text(8, "%d" % min_rep if min_rep > 0 else "-")

		_color_row(row, c)


func _color_row(row: TreeItem, c: Dictionary) -> void:
	## Colour coding: status + rep gate dominate.
	var status: String = str(c.get("status", "")).to_lower()
	match status:
		"posted":
			row.set_custom_color(1, ThemePalette.PRIMARY)
		"accepted", "picked_up":
			row.set_custom_color(1, ThemePalette.WARN)
		"paid":
			row.set_custom_color(1, ThemePalette.SUCCESS)
		"expired":
			row.set_custom_color(1, ThemePalette.DANGER)
	var min_rep: int = int(c.get("min_reputation", 0))
	if min_rep >= 50:
		row.set_custom_color(8, ThemePalette.WARN)
	elif min_rep > 0:
		row.set_custom_color(8, ThemePalette.PRIMARY)


func _compare_contracts(a: Dictionary, b: Dictionary) -> bool:
	var va: Variant
	var vb: Variant
	match _sort_column:
		"kind":
			va = str(a.get("contract_type", ""))
			vb = str(b.get("contract_type", ""))
		"status":
			va = str(a.get("status", ""))
			vb = str(b.get("status", ""))
		"commodity":
			va = str(a.get("commodity", ""))
			vb = str(b.get("commodity", ""))
		"quantity":
			va = int(a.get("quantity", 0))
			vb = int(b.get("quantity", 0))
		"source":
			va = str(a.get("source_location", ""))
			vb = str(b.get("source_location", ""))
		"payment":
			va = int(a.get("payment", 0))
			vb = int(b.get("payment", 0))
		"age":
			# Sort oldest-posted first so you see the stale stuff.
			va = int(a.get("posted_at_tick", 0))
			vb = int(b.get("posted_at_tick", 0))
		"faction":
			va = str(a.get("faction_id", ""))
			vb = str(b.get("faction_id", ""))
		"min_rep":
			va = int(a.get("min_reputation", 0))
			vb = int(b.get("min_reputation", 0))
		_:
			va = ""
			vb = ""
	if _sort_ascending:
		return va < vb
	return va > vb
