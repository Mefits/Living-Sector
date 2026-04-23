extends PanelContainer

## Post-mortem ledger of decommissioned ships. Reads
## `GET /api/retirements` (newest-first, capped at 200 rows on the
## server) and renders the result as a sortable table.
##
## Unlike other inspector panels this one is NOT live — retirement
## rows are append-only on the server (see
## `simulator-rust/.../persistence.rs::DbWrite::RetireShip`), so we
## fetch on open + whenever a fresh `ship_decommissioned` event
## arrives. No per-tick refresh; the HTTP payload is just extra work
## for a list that rarely changes.

signal location_selected(location: String)

@onready var tree: Tree = $VBox/Tree
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var refresh_button: Button = $VBox/TopRow/RefreshButton
@onready var close_button: Button = $VBox/TopRow/CloseButton

var _rows: Array = []
var _sort_column: String = "retired_at_tick"
var _sort_ascending: bool = false  # newest-first default


func _ready() -> void:
  visible = false
  close_button.pressed.connect(func(): visible = false)
  refresh_button.pressed.connect(_fetch)
  tree.item_activated.connect(_on_row_activated)
  tree.column_title_clicked.connect(_on_column_clicked)
  _setup_columns()
  # Live-update when a decommission event lands. The server publishes
  # the retire row on the same tick so by the time the event arrives
  # in Godot, /api/retirements is current. No debounce needed —
  # decommissions are rare (seconds apart at most).
  GameState.event_received.connect(_on_event)


func _setup_columns() -> void:
  tree.columns = 8
  tree.set_column_title(0, "Name")
  tree.set_column_title(1, "Class")
  tree.set_column_title(2, "Faction")
  tree.set_column_title(3, "Last Location")
  tree.set_column_title(4, "Credits")
  tree.set_column_title(5, "Morale")
  tree.set_column_title(6, "Fuel %")
  tree.set_column_title(7, "Reason")
  tree.column_titles_visible = true
  tree.set_column_expand_ratio(0, 3)
  tree.set_column_expand_ratio(1, 2)
  tree.set_column_expand_ratio(2, 2)
  tree.set_column_expand_ratio(3, 3)
  tree.set_column_expand_ratio(4, 2)
  tree.set_column_expand_ratio(5, 1)
  tree.set_column_expand_ratio(6, 1)
  tree.set_column_expand_ratio(7, 2)
  tree.select_mode = Tree.SELECT_SINGLE


func toggle() -> void:
  visible = not visible
  if visible:
    _fetch()


func _on_event(ev: Dictionary, _tick: int) -> void:
  if not visible:
    return
  if str(ev.get("type", "")) == "ship_decommissioned":
    _fetch()


func _fetch() -> void:
  count_label.text = "loading…"
  NetworkManager.fetch_retirements(
    func(code: int, rows: Array) -> void:
      if code != 200:
        count_label.text = "fetch failed (%d)" % code
        return
      _rows = rows
      _refresh()
  )


func _on_column_clicked(column: int, _mouse_button: int) -> void:
  var cols := [
    "name", "class", "faction_id", "final_location",
    "final_credits", "final_crew_morale", "final_fuel_pct", "reason",
  ]
  var new_col: String = cols[column]
  if new_col == _sort_column:
    _sort_ascending = not _sort_ascending
  else:
    _sort_column = new_col
    # Most recent / largest first is the useful default for the
    # numeric columns; strings sort ascending.
    _sort_ascending = new_col in [
      "name", "class", "faction_id", "final_location", "reason"
    ]
  _refresh()


func _on_row_activated() -> void:
  var sel := tree.get_selected()
  if sel == null:
    return
  var loc: String = str(sel.get_metadata(1))
  if loc != "":
    # Surface for main.gd to jump the camera to wherever this ship
    # was last seen (typically a station). Parallels the market +
    # pops panels.
    location_selected.emit(loc)


func _refresh() -> void:
  count_label.text = "%d retired" % _rows.size()
  var sorted := _rows.duplicate()
  sorted.sort_custom(_compare)
  tree.clear()
  var root := tree.create_item()
  for r in sorted:
    var row := tree.create_item(root)
    row.set_metadata(0, str(r.get("agent_id", "")))
    row.set_metadata(1, str(r.get("final_location", "")))

    row.set_text(0, str(r.get("name", "?")))
    row.set_text(1, str(r.get("class", "?")).capitalize())
    row.set_text(2, GameState.faction_name(r.get("faction_id", "")))
    row.set_text(3, str(r.get("final_location", "")))
    row.set_text(4, _fmt_credits(int(r.get("final_credits", 0))))

    var morale: int = int(r.get("final_crew_morale", 0))
    row.set_text(5, "%d" % morale)
    _color_morale(row, 5, morale)

    var fuel: int = int(r.get("final_fuel_pct", 0))
    row.set_text(6, "%d%%" % fuel)
    if fuel < 20:
      row.set_custom_color(6, ThemePalette.DANGER)

    row.set_text(7, _reason_label(str(r.get("reason", ""))))


func _compare(a: Dictionary, b: Dictionary) -> bool:
  var va: Variant = a.get(_sort_column, "")
  var vb: Variant = b.get(_sort_column, "")
  if va is int or va is float or vb is int or vb is float:
    va = float(va)
    vb = float(vb)
  else:
    va = str(va)
    vb = str(vb)
  if _sort_ascending:
    return va < vb
  return va > vb


func _fmt_credits(n: int) -> String:
  if n >= 1_000_000:
    return "%.1fM" % (float(n) / 1_000_000.0)
  if n >= 10_000:
    return "%.1fk" % (float(n) / 1_000.0)
  return "%d" % n


func _color_morale(row: TreeItem, col: int, v: int) -> void:
  if v >= 70:
    row.set_custom_color(col, ThemePalette.SUCCESS)
  elif v >= 40:
    row.set_custom_color(col, ThemePalette.WARN)
  else:
    row.set_custom_color(col, ThemePalette.DANGER)


func _reason_label(reason: String) -> String:
  ## Map the server's short slugs into display text. Unknown values
  ## fall through capitalized so a new reason on the server still
  ## renders readably.
  match reason:
    "admin":
      return "Decommissioned"
    "broke":
      return "Bankrupt"
    "hoard":
      return "Hoarding"
    _:
      return reason.capitalize() if reason != "" else "—"
