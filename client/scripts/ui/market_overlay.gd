extends PanelContainer

## Market panel. One cell per (facility × commodity) showing current price
## + supply as text, plus a sparkline with red = price, blue = supply.
## History is captured client-side from game load — nothing fetched from
## the server. Sampling runs even when the panel is closed so the graph
## isn't empty on reopen.

## DEBUG: flip on to print refresh-phase diagnostics (market → facility
## match rates, row-creation counts). Left in so future mismatches are a
## one-line flip away.
const DEBUG := false

## Fires when the user clicks a facility name in the left column.
## Main wires this to the same camera-jump path the Ship-list and
## Events-ticker panels use (`_on_location_selected` → focus_on the
## matching facility's world position).
signal location_selected(location: String)

@onready var close_button: Button = $VBox/TopRow/CloseButton
@onready var header_row: HBoxContainer = $VBox/HeaderRow
@onready var rows_container: VBoxContainer = $VBox/ScrollContainer/Rows

const KEY_COMMODITIES := [
	"ore", "fuel", "food", "metals", "water",
	"components", "electronics", "tools",
]

# ~90 samples at one every 16 ticks (~2s) ≈ 3 min of history.
const MAX_SAMPLES := 90
const SAMPLE_EVERY_N_TICKS := 16

const FAC_COL_WIDTH := 220
const COMMODITY_COL_WIDTH := 160
const ROW_HEIGHT := 72

# facility_loc -> commodity -> Array of {p: float, s: int}
var _history: Dictionary = {}
# facility_loc -> commodity -> MarketCell
var _cells: Dictionary = {}
# facility_loc -> HBoxContainer
var _rows: Dictionary = {}

var _tick_counter: int = 0


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	_build_header()
	# Per-tick sparkline sampling stays on tick_updated — it's cheap
	# (a few hashmap writes). Full grid rebuild moves to `markets_updated`
	# which fires on the ~2 s market_states broadcast, since that's when
	# the data actually changes; the 8-Hz rebuild was pure waste.
	GameState.tick_updated.connect(_on_tick)
	GameState.markets_updated.connect(_on_markets_updated)
	if DEBUG:
		print("[Market] _ready — close_button=%s header_row=%s rows_container=%s" % [
			close_button != null, header_row != null, rows_container != null,
		])


func toggle() -> void:
	visible = not visible
	if DEBUG:
		print("[Market] toggle — visible=%s GameState.markets=%d facilities=%d" % [
			visible, GameState.markets.size(), GameState.facilities.size(),
		])
	if visible:
		_refresh()


func _on_tick(_tick: int) -> void:
	# Sparkline history only — the full grid rebuild moved to the
	# `markets_updated` handler below (fires on the ~2 s WS broadcast
	# that actually contains fresh prices).
	_tick_counter += 1
	if _tick_counter % SAMPLE_EVERY_N_TICKS == 0:
		_capture_samples()


func _on_markets_updated() -> void:
	if visible:
		_refresh()


func _capture_samples() -> void:
	for market in GameState.markets.values():
		var fac_loc: String = str(market.get("facility_location", market.get("facility_id", "")))
		if fac_loc == "":
			continue
		var prices = market.get("prices", {})
		var supply = market.get("supply", {})
		if not (prices is Dictionary) or not (supply is Dictionary):
			continue
		if not _history.has(fac_loc):
			_history[fac_loc] = {}
		var fac_hist: Dictionary = _history[fac_loc]
		for commodity in KEY_COMMODITIES:
			var p = prices.get(commodity)
			if p == null:
				continue
			var pf: float = float(p)
			if pf <= 0 or pf >= 500:
				continue
			var si: int = int(supply.get(commodity, 0))
			if not fac_hist.has(commodity):
				fac_hist[commodity] = []
			var samples: Array = fac_hist[commodity]
			# Dedupe unchanged samples so the buffer covers a longer
			# real-time window when the market is stagnant.
			if samples.size() > 0:
				var last: Dictionary = samples[-1]
				if last.p == pf and last.s == si:
					continue
			samples.append({"p": pf, "s": si})
			if samples.size() > MAX_SAMPLES:
				samples.remove_at(0)


func _build_header() -> void:
	var fac_label := Label.new()
	fac_label.text = "Facility"
	fac_label.custom_minimum_size = Vector2(FAC_COL_WIDTH, 0)
	header_row.add_child(fac_label)
	for commodity in KEY_COMMODITIES:
		var l := Label.new()
		l.text = str(commodity).capitalize().substr(0, 4)
		l.custom_minimum_size = Vector2(COMMODITY_COL_WIDTH, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_row.add_child(l)


func _refresh() -> void:
	var markets_by_fac: Dictionary = {}
	var sample_market_keys: Array = []
	for market in GameState.markets.values():
		var fac_loc: String = str(market.get("facility_location", market.get("facility_id", "")))
		markets_by_fac[fac_loc] = market
		if DEBUG and sample_market_keys.size() < 3:
			sample_market_keys.append({
				"id": market.get("id"),
				"facility_location": market.get("facility_location"),
				"has_prices": market.has("prices"),
				"has_supply": market.has("supply"),
				"price_keys": (market.get("prices", {}) as Dictionary).keys() if market.get("prices") is Dictionary else [],
			})
	if DEBUG:
		print("[Market] _refresh — markets_by_fac keys sample: %s" % [markets_by_fac.keys().slice(0, 5)])
		print("[Market] _refresh — market sample shapes: %s" % [sample_market_keys])

	var sorted_facs: Array = []
	var sample_fac_keys: Array = []
	var unmatched_facs: Array = []
	for fac in GameState.facilities.values():
		var fac_loc: String = str(fac.get("location", ""))
		if DEBUG and sample_fac_keys.size() < 3:
			sample_fac_keys.append({"id": fac.get("id"), "location": fac_loc, "name": fac.get("name")})
		if markets_by_fac.has(fac_loc):
			sorted_facs.append(fac)
		elif DEBUG and unmatched_facs.size() < 5:
			unmatched_facs.append({"id": fac.get("id"), "location": fac_loc})
	sorted_facs.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("name", "")) < str(b.get("name", ""))
	)
	if DEBUG:
		print("[Market] _refresh — facility sample: %s" % [sample_fac_keys])
		print("[Market] _refresh — matched=%d unmatched=%d (first unmatched: %s)" % [
			sorted_facs.size(), GameState.facilities.size() - sorted_facs.size(), unmatched_facs,
		])

	# Price range per commodity for color coding current value
	var min_prices: Dictionary = {}
	var max_prices: Dictionary = {}
	for commodity in KEY_COMMODITIES:
		min_prices[commodity] = 999999.0
		max_prices[commodity] = 0.0
	for market in markets_by_fac.values():
		var prices = market.get("prices", {})
		if not (prices is Dictionary):
			continue
		for commodity in KEY_COMMODITIES:
			var p = prices.get(commodity)
			if p == null:
				continue
			var pf: float = float(p)
			if pf <= 0 or pf >= 500:
				continue
			if pf < min_prices[commodity]:
				min_prices[commodity] = pf
			if pf > max_prices[commodity]:
				max_prices[commodity] = pf

	var rows_created: int = 0
	for fac in sorted_facs:
		var fac_loc: String = str(fac.get("location", ""))
		var fac_name: String = str(fac.get("name", fac_loc))
		var market: Dictionary = markets_by_fac.get(fac_loc, {})
		var prices = market.get("prices", {})
		var supply = market.get("supply", {})
		var shortage = market.get("shortage_ticks", {})

		if not _rows.has(fac_loc):
			_create_row(fac_loc, fac_name)
			rows_created += 1

		for commodity in KEY_COMMODITIES:
			var cell: MarketCell = _cells[fac_loc][commodity]
			var p = prices.get(commodity) if prices is Dictionary else null
			var s = supply.get(commodity, 0) if supply is Dictionary else 0
			var sh: int = (
				int(shortage.get(commodity, 0))
				if shortage is Dictionary else 0
			)
			var samples: Array = _history.get(
				fac_loc, {}
			).get(commodity, [])
			if p == null or float(p) >= 500:
				cell.update("-", Color.WHITE, samples, 0)
				continue
			var pf: float = float(p)
			var si: int = int(s)
			var text: String = "%d (%d)" % [int(pf), si]
			var color: Color = Color.WHITE
			var mn: float = min_prices[commodity]
			var mx: float = max_prices[commodity]
			if mx > mn:
				var t: float = (pf - mn) / (mx - mn)
				color = Color.GREEN.lerp(Color.RED, t)
			cell.update(text, color, samples, sh)

	if DEBUG:
		print("[Market] _refresh — rows_created=%d total_rows=%d rows_container_children=%d" % [
			rows_created, _rows.size(),
			rows_container.get_child_count() if rows_container else -1,
		])
		if _rows.size() > 0:
			var first_key = _rows.keys()[0]
			var first_row: Node = _rows[first_key]
			print("[Market] _refresh — first row '%s' has %d children, visible=%s" % [
				first_key, first_row.get_child_count(), first_row.visible,
			])


func _create_row(fac_loc: String, fac_name: String) -> void:
	var row := HBoxContainer.new()
	# Flat button instead of a plain Label so the facility name is
	# clickable without introducing any visible button chrome. Pressed
	# emits `location_selected` which main.gd routes to the same
	# camera-jump used by ship_list + events_ticker.
	var name_btn := Button.new()
	name_btn.text = fac_name
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.custom_minimum_size = Vector2(FAC_COL_WIDTH, ROW_HEIGHT)
	name_btn.tooltip_text = "Jump camera to %s" % fac_name
	name_btn.pressed.connect(
		func() -> void: location_selected.emit(fac_loc)
	)
	row.add_child(name_btn)

	_cells[fac_loc] = {}
	for commodity in KEY_COMMODITIES:
		var cell := MarketCell.new()
		cell.custom_minimum_size = Vector2(
			COMMODITY_COL_WIDTH, ROW_HEIGHT
		)
		row.add_child(cell)
		_cells[fac_loc][commodity] = cell

	rows_container.add_child(row)
	_rows[fac_loc] = row


# One cell = Label for text + custom _draw() for the sparkline below it.
class MarketCell extends Control:
	const GRAPH_HEIGHT := 44
	const TEXT_HEIGHT := 24
	# Price on the danger ramp, supply on the info ramp — keeps sparkline
	# colors aligned with every other red=expensive / cyan=info cue.
	static var price_color: Color = Color(
		ThemePalette.DANGER.r, ThemePalette.DANGER.g,
		ThemePalette.DANGER.b, 0.85
	)
	static var supply_color: Color = Color(
		ThemePalette.PRIMARY.r, ThemePalette.PRIMARY.g,
		ThemePalette.PRIMARY.b, 0.85
	)

	var _label: Label
	var _samples: Array = []
	var _shortage: int = 0

	func _init() -> void:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.anchor_left = 0.0
		_label.anchor_right = 1.0
		_label.anchor_top = 0.0
		_label.offset_top = 3
		_label.offset_bottom = TEXT_HEIGHT + 3
		add_child(_label)

	func update(
		text: String, color: Color, samples: Array, shortage: int = 0
	) -> void:
		_label.text = text
		_label.modulate = color
		_samples = samples
		_shortage = shortage
		queue_redraw()

	func _draw() -> void:
		var sz: Vector2 = self.size
		# Scarcity flare: top bar colored by shortage severity
		if _shortage > 0:
			var bar_col: Color = (
				ThemePalette.DANGER if _shortage >= 30
				else ThemePalette.WARN
			)
			draw_rect(Rect2(0, 0, sz.x, 3), bar_col)

		if _samples.size() < 2:
			return
		var graph_bot: float = sz.y - 2
		var graph_top: float = sz.y - GRAPH_HEIGHT
		var graph_h: float = graph_bot - graph_top
		if graph_h <= 0:
			return

		var min_p: float = INF
		var max_p: float = -INF
		var min_s: float = INF
		var max_s: float = -INF
		for sample in _samples:
			var p: float = float(sample["p"])
			var s: float = float(sample["s"])
			if p < min_p: min_p = p
			if p > max_p: max_p = p
			if s < min_s: min_s = s
			if s > max_s: max_s = s

		var n: int = _samples.size()
		var denom: float = max(float(n - 1), 1.0)
		var price_pts: PackedVector2Array = PackedVector2Array()
		var supply_pts: PackedVector2Array = PackedVector2Array()
		for i in range(n):
			var x: float = (float(i) / denom) * sz.x
			var p: float = float(_samples[i]["p"])
			var s: float = float(_samples[i]["s"])
			var py: float = graph_bot - graph_h * 0.5
			if max_p > min_p:
				py = graph_bot - ((p - min_p) / (max_p - min_p)) * graph_h
			var sy: float = graph_bot - graph_h * 0.5
			if max_s > min_s:
				sy = graph_bot - ((s - min_s) / (max_s - min_s)) * graph_h
			price_pts.append(Vector2(x, py))
			supply_pts.append(Vector2(x, sy))

		draw_polyline(supply_pts, supply_color, 1.0)
		draw_polyline(price_pts, price_color, 1.0)
