extends PanelContainer

## Rolling feed of simulator events (ship_docked, contract_delivered,
## passengers_arrived, market_supply_adjusted, crew_mission_completed, …).
##
## Reads `GameState.event_log` — populated by `network_manager._handle_events`
## as the server pushes the `events` WS message — and redraws whenever a new
## batch arrives.
##
## Filter chips at the top narrow to a single event kind. Click a row to
## emit `focus_requested` with the involved agent/contract id so the main
## scene can point the camera at it (or select it in the ship list, etc.).

signal focus_requested(agent_id: String)

const MAX_ROWS := 120

@onready var close_button: Button = $VBox/TopRow/CloseButton
@onready var kind_filter: OptionButton = $VBox/TopRow/KindFilter
@onready var count_label: Label = $VBox/TopRow/CountLabel
@onready var feed: RichTextLabel = $VBox/Feed

var _current_filter: String = ""  # empty = all kinds
# Track the known event kinds so the OptionButton stays in sync with the
# live stream (new event kinds added by Rust will show up here).
var _known_kinds: Dictionary = {}


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	kind_filter.item_selected.connect(_on_filter_changed)
	feed.meta_clicked.connect(_on_meta_clicked)
	feed.bbcode_enabled = true
	feed.scroll_following = true
	GameState.event_received.connect(_on_event)
	_refresh_filter_options()


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild_from_log()


func _on_event(_event: Dictionary, _tick: int) -> void:
	if not visible:
		return
	_rebuild_from_log()


func _on_filter_changed(index: int) -> void:
	_current_filter = kind_filter.get_item_metadata(index)
	_rebuild_from_log()


func _on_meta_clicked(meta: Variant) -> void:
	## RichTextLabel.meta_clicked fires with whatever we stuffed into
	## `[url=…]…[/url]`. We encode the target agent id.
	if meta is String and meta != "":
		focus_requested.emit(meta)


func _rebuild_from_log() -> void:
	_refresh_filter_options()
	var log: Array = GameState.event_log
	var out: PackedStringArray = PackedStringArray()
	var shown: int = 0
	# Newest first — iterate backwards through the ring buffer.
	for i in range(log.size() - 1, -1, -1):
		if shown >= MAX_ROWS:
			break
		var entry: Dictionary = log[i]
		var ev: Dictionary = entry.get("event", {})
		var kind: String = str(ev.get("kind", "?"))
		if _current_filter != "" and kind != _current_filter:
			continue
		out.append(_format_row(int(entry.get("tick", 0)), ev))
		shown += 1
	feed.text = "\n".join(out)
	count_label.text = "%d / %d" % [shown, log.size()]


func _format_row(tick: int, ev: Dictionary) -> String:
	var kind: String = str(ev.get("kind", "?"))
	var color := _color_for_kind(kind)
	var body := _body_for_kind(kind, ev)
	var link := _link_target(ev)
	var tick_str := "[color=%s][%d][/color]" % [ThemePalette.TEXT_DIM.to_html(), tick]
	var kind_str := "[color=%s]%s[/color]" % [color.to_html(), kind]
	var row := "%s %s %s" % [tick_str, kind_str, body]
	if link != "":
		return "[url=%s]%s[/url]" % [link, row]
	return row


func _link_target(ev: Dictionary) -> String:
	## Pick whatever id is most useful to click-through to. Prefer explicit
	## ship id, then contract_id, then destination location.
	var id := str(ev.get("id", ""))
	if id != "":
		return id
	var cid := str(ev.get("contract_id", ""))
	if cid != "":
		return cid
	var dest := str(ev.get("destination", ""))
	if dest != "":
		return dest
	return ""


func _body_for_kind(kind: String, ev: Dictionary) -> String:
	## Hand-tuned one-liner per event kind. Any kind without a match
	## falls through to the raw fields so new event types stay readable.
	match kind:
		"ship_docked":
			return "ship @ %s" % str(ev.get("location", "?"))
		"ship_decommissioned":
			return "%s — %s" % [str(ev.get("id", "?")), str(ev.get("reason", ""))]
		"ship_spawned":
			return "%s (%s) at %s" % [
				str(ev.get("id", "?")),
				str(ev.get("class", "?")),
				str(ev.get("location", "?")),
			]
		"contract_delivered":
			return "%s %s→%s pay=%d" % [
				str(ev.get("contract_type", "")),
				str(ev.get("commodity", "")),
				str(ev.get("destination", "?")),
				int(ev.get("payment", 0)),
			]
		"passengers_arrived":
			return "%d passengers → %s pay=%d" % [
				int(ev.get("head_count", 0)),
				str(ev.get("destination", "?")),
				int(ev.get("payment", 0)),
			]
		"crew_mission_completed":
			return "%s (+%d %s) pay=%d" % [
				str(ev.get("category", "?")),
				int(ev.get("skill_gain", 0)),
				str(ev.get("skill", "")),
				int(ev.get("payment", 0)),
			]
		"facility_spawned":
			return "%s (%s) at %s" % [
				str(ev.get("id", "?")),
				str(ev.get("facility_type", "?")),
				str(ev.get("location", "?")),
			]
		"facility_removed":
			return str(ev.get("id", "?"))
		"market_supply_adjusted":
			return "%s → %d deltas" % [
				str(ev.get("location", "?")),
				int((ev.get("deltas", []) as Array).size()),
			]
		"ship_leveled_up":
			return "%s → lvl %d (+%d retrofit pts)" % [
				str(ev.get("id", "?")),
				int(ev.get("new_level", 0)),
				int(ev.get("levels_gained", 0)),
			]
		"ship_refitted":
			var from = ev.get("from", null)
			var to = ev.get("to", null)
			var from_s := "—" if from == null else str(from)
			var to_s := "—" if to == null else str(to)
			var via := str(ev.get("via", "admin"))
			var cost_str := ""
			if ev.has("cost"):
				cost_str = " (%d cr)" % int(ev.get("cost", 0))
			return "%s %s: %s → %s [%s%s]" % [
				str(ev.get("id", "?")),
				str(ev.get("slot", "?")),
				from_s,
				to_s,
				via,
				cost_str,
			]
		"facility_refitted":
			var f_from = ev.get("from", null)
			var f_to = ev.get("to", null)
			return "%s %s: %s → %s" % [
				str(ev.get("id", "?")),
				str(ev.get("slot", "?")),
				"—" if f_from == null else str(f_from),
				"—" if f_to == null else str(f_to),
			]
		"ship_gate_jumped":
			return "%s %s → %s (fee %d)" % [
				str(ev.get("id", "?")),
				str(ev.get("src_gate", "?")),
				str(ev.get("dest_gate", "?")),
				int(ev.get("fee", 0)),
			]
		"contract_accepted":
			return "%s %s %s → %s pay=%d" % [
				str(ev.get("ship_id", "?")),
				str(ev.get("contract_type", "")),
				str(ev.get("commodity", "")),
				str(ev.get("destination", "?")),
				int(ev.get("payment", 0)),
			]
		"contract_renewed":
			# Payment bumps + rep gate drops as deliveries age open.
			# renewal_count maxes at 3 — after that they really expire.
			return "%s @ %s pay=%d min_rep=%d (renewal %d)" % [
				str(ev.get("commodity", "")),
				str(ev.get("destination", "?")),
				int(ev.get("payment", 0)),
				int(ev.get("min_reputation", 0)),
				int(ev.get("renewal_count", 0)),
			]
		"contract_expired":
			return "%s %s → %s expired pay=%d" % [
				str(ev.get("contract_type", "")),
				str(ev.get("commodity", "")),
				str(ev.get("destination", "?")),
				int(ev.get("final_payment", 0)),
			]
		"facility_crew_starving":
			return "%s (%s) — crew %d morale %.0f" % [
				str(ev.get("facility_id", "?")),
				str(ev.get("facility_type", "?")),
				int(ev.get("crew_count", 0)),
				float(ev.get("morale", 0.0)),
			]
		"facility_abandoned":
			return "%s (%s) at %s — cond=%.2f creds=%d" % [
				str(ev.get("facility_id", "?")),
				str(ev.get("facility_type", "?")),
				str(ev.get("location", "?")),
				float(ev.get("condition", 0.0)),
				int(ev.get("credits", 0)),
			]
		_:
			# Unknown kind — stringify the fields we have.
			var parts: PackedStringArray = PackedStringArray()
			for key in ev.keys():
				if key == "kind":
					continue
				parts.append("%s=%s" % [key, str(ev[key])])
			return " ".join(parts)


func _color_for_kind(kind: String) -> Color:
	if kind.begins_with("ship_"):
		return ThemePalette.PRIMARY
	if kind.begins_with("contract_") or kind == "passengers_arrived":
		return ThemePalette.SUCCESS
	if kind.begins_with("facility_"):
		return ThemePalette.WARN
	if kind.begins_with("crew_mission"):
		return ThemePalette.WARN
	if kind.begins_with("market_"):
		return ThemePalette.TEXT
	return ThemePalette.TEXT_DIM


func _refresh_filter_options() -> void:
	## Scan the log for kinds the user hasn't seen before; add them to
	## the filter dropdown. Cheap — log is capped at EVENT_BUFFER_SIZE.
	var new_kinds: Array = []
	for entry in GameState.event_log:
		var ev: Dictionary = entry.get("event", {})
		var kind: String = str(ev.get("kind", ""))
		if kind == "" or _known_kinds.has(kind):
			continue
		_known_kinds[kind] = true
		new_kinds.append(kind)
	if new_kinds.is_empty() and kind_filter.item_count > 0:
		return
	var prev_filter := _current_filter
	kind_filter.clear()
	kind_filter.add_item("All")
	kind_filter.set_item_metadata(0, "")
	var sorted_kinds: Array = _known_kinds.keys()
	sorted_kinds.sort()
	for k in sorted_kinds:
		kind_filter.add_item(k)
		kind_filter.set_item_metadata(kind_filter.item_count - 1, k)
	# Restore previous selection if still present.
	for i in range(kind_filter.item_count):
		if kind_filter.get_item_metadata(i) == prev_filter:
			kind_filter.select(i)
			return
	kind_filter.select(0)
	_current_filter = ""
