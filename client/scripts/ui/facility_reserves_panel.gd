extends PanelContainer

## God-mode market supply editor. Reads from `GameState.markets` (the
## facility's co-located market, matched by facility.location ==
## market.facility_id), shows one row per commodity, and on Apply
## sends one POST /api/admin/markets/:loc/supply per commodity whose
## value changed — the server endpoint takes per-commodity deltas,
## not a full-replace map.
##
## The prior "reserves" naming was a misread of the data model: the
## admin endpoint targets market supply (what's for sale), not the
## facility's stockpile (`reserves`). Scene/script file names are
## unchanged to avoid churn; only the UX text uses "Supply".

signal apply_requested(
	facility_location: String, deltas: Dictionary
)

const KNOWN_COMMODITIES := [
	"ore", "fuel", "food", "metals", "water",
	"components", "electronics", "tools",
]

const QUICK_STEPS := [-100, -10, 10, 100]

@onready var title_label: Label = $VBox/TopRow/Title
@onready var close_button: Button = $VBox/TopRow/CloseButton
@onready var rows_box: VBoxContainer = $VBox/RowsBox
@onready var add_opt: OptionButton = $VBox/AddRow/AddOpt
@onready var add_spin: SpinBox = $VBox/AddRow/AddSpin
@onready var add_button: Button = $VBox/AddRow/AddButton
@onready var cancel_button: Button = $VBox/Footer/CancelButton
@onready var apply_button: Button = $VBox/Footer/ApplyButton

var _facility_location: String = ""
# commodity -> SpinBox so Apply can read current values
var _spins: Dictionary = {}
# commodity -> starting value for delta computation
var _baseline: Dictionary = {}


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): visible = false)
	cancel_button.pressed.connect(func(): visible = false)
	apply_button.pressed.connect(_on_apply_pressed)
	add_button.pressed.connect(_on_add_commodity_pressed)


func open_for(facility_id: String) -> void:
	var fac: Dictionary = GameState.facilities.get(facility_id, {})
	_facility_location = str(fac.get("location", ""))
	var fac_name: String = str(fac.get("name", facility_id))
	title_label.text = "Market Supply — %s" % fac_name

	var market: Dictionary = _find_market_for(_facility_location)
	var supply: Variant = market.get("supply", {})
	_build_rows(supply)
	_populate_add_options()
	visible = true


func _find_market_for(location: String) -> Dictionary:
	for m in GameState.markets.values():
		if str(m.get("facility_location", m.get("facility_id", ""))) == location:
			return m
	return {}


func _build_rows(supply: Variant) -> void:
	for child in rows_box.get_children():
		child.queue_free()
	_spins.clear()
	_baseline.clear()
	if not (supply is Dictionary):
		supply = {}
	var keys: Array = supply.keys()
	keys.sort()
	for commodity in keys:
		_add_row(str(commodity), int(supply[commodity]))


func _add_row(commodity: String, qty: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = commodity.capitalize()
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 1000000
	spin.step = 1
	spin.value = qty
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	_spins[commodity] = spin
	_baseline[commodity] = qty

	for step in QUICK_STEPS:
		var b := Button.new()
		b.text = "%+d" % step
		var s: int = step
		b.pressed.connect(
			func(): spin.value = clampf(spin.value + s, 0, spin.max_value)
		)
		row.add_child(b)

	rows_box.add_child(row)


func _populate_add_options() -> void:
	add_opt.clear()
	for commodity in KNOWN_COMMODITIES:
		if _spins.has(commodity):
			continue
		add_opt.add_item(commodity.capitalize())
		add_opt.set_item_metadata(add_opt.item_count - 1, commodity)
	add_button.disabled = add_opt.item_count == 0


func _on_add_commodity_pressed() -> void:
	if add_opt.selected < 0:
		return
	var commodity: String = str(add_opt.get_item_metadata(add_opt.selected))
	var qty: int = int(add_spin.value)
	# Baseline of 0 means Apply will send a +qty delta.
	_add_row(commodity, 0)
	_spins[commodity].value = qty
	_populate_add_options()


func _on_apply_pressed() -> void:
	# Build a per-commodity delta map, skipping zero-change rows so we
	# don't waste requests.
	var deltas: Dictionary = {}
	for commodity in _spins:
		var new_val: int = int(_spins[commodity].value)
		var base: int = int(_baseline.get(commodity, 0))
		var delta: int = new_val - base
		if delta != 0:
			deltas[commodity] = delta
	apply_requested.emit(_facility_location, deltas)
	visible = false
