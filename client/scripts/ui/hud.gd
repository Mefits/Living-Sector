extends CanvasLayer

## HUD overlay showing tick count, FPS, ship count, simulation speed controls,
## and observer toggle.

signal observer_toggled(active: bool)
signal ship_list_toggled
signal market_toggled

@onready var tick_label: Label = %TickLabel
@onready var speed_label: Label = %SpeedLabel
@onready var ship_count_label: Label = %ShipCountLabel
@onready var fps_label: Label = %FPSLabel
@onready var status_label: Label = %StatusLabel
@onready var pause_button: Button = %PauseButton
@onready var speed_1x_button: Button = %Speed1xButton
@onready var speed_2x_button: Button = %Speed2xButton
@onready var speed_5x_button: Button = %Speed5xButton
@onready var speed_10x_button: Button = %Speed10xButton
@onready var observer_button: Button = %ObserverButton
@onready var ship_list_button: Button = %ShipListButton
@onready var market_button: Button = %MarketButton
@onready var save_button: Button = %SaveButton
@onready var save_as_button: Button = %SaveAsButton

var _observer_active := false
var _save_as_dialog: AcceptDialog
var _save_as_input: LineEdit


func _ready() -> void:
	GameState.tick_updated.connect(_on_tick_updated)
	GameState.world_loaded.connect(_on_world_loaded)
	NetworkManager.connected.connect(func(): status_label.text = "Connected")
	NetworkManager.disconnected.connect(
		func(): status_label.text = "Disconnected"
	)

	pause_button.pressed.connect(_on_pause_pressed)
	# Speed buttons tune `world_speed` (gameplay pace) — NOT tick
	# resolution. `1×` is literal real-time; `10×` is Earth↔Mars in
	# ~6s (demo-speed). Tick resolution stays at whatever the sim was
	# configured with (client smoothness is independent).
	speed_1x_button.pressed.connect(func(): _set_world_speed(1.0))
	speed_2x_button.pressed.connect(func(): _set_world_speed(2.0))
	speed_5x_button.pressed.connect(func(): _set_world_speed(5.0))
	speed_10x_button.pressed.connect(func(): _set_world_speed(10.0))
	observer_button.pressed.connect(_on_observer_pressed)
	ship_list_button.pressed.connect(
		func(): ship_list_toggled.emit()
	)
	market_button.pressed.connect(
		func(): market_toggled.emit()
	)
	save_button.pressed.connect(_on_save_pressed)
	save_as_button.pressed.connect(_on_save_as_pressed)

	status_label.text = "Connecting..."


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _on_tick_updated(tick: int) -> void:
	tick_label.text = "Tick: %d" % tick


func _on_world_loaded() -> void:
	ship_count_label.text = "Ships: %d" % GameState.ships.size()
	_update_speed_label()


func _on_pause_pressed() -> void:
	if GameState.running:
		NetworkManager.post_sim_control("pause")
		GameState.running = false
		pause_button.text = "Resume"
	else:
		NetworkManager.post_sim_control("resume")
		GameState.running = true
		pause_button.text = "Pause"


func _on_observer_pressed() -> void:
	set_observer_active(not _observer_active)


func set_observer_active(active: bool) -> void:
	## Public setter so other systems (e.g. POV mode cancelling observer)
	## can update button state and fire the signal consistently.
	if active == _observer_active:
		return
	_observer_active = active
	observer_button.text = ">> Free Cam" if active else ">> Observer"
	observer_toggled.emit(_observer_active)


func _set_world_speed(world_speed: float) -> void:
	## Tune game-time pace. Does NOT change tick resolution (smoothness).
	## Route via HTTP — world-speed changes land on the next tick.
	NetworkManager.post_sim_control(
		"set_world_speed", {"world_speed": world_speed}
	)
	_update_speed_label()


func _update_speed_label() -> void:
	var multiplier: int = int(250.0 / GameState.tick_interval_ms)
	speed_label.text = "Speed: %dx" % multiplier


# -------------------- Save / Save As --------------------

func _on_save_pressed() -> void:
	NetworkManager.admin_save(_on_save_response)


func _on_save_response(code: int, body: String) -> void:
	if code == 200:
		var parsed = JSON.parse_string(body)
		var ticks := 0
		if parsed is Dictionary:
			ticks = int(parsed.get("tick", 0))
		GameState.show_toast(
			"saved (tick %d)" % ticks, ThemePalette.SUCCESS
		)
	else:
		GameState.show_toast(
			"save failed (%d)" % code, ThemePalette.DANGER
		)


func _on_save_as_pressed() -> void:
	# Lazily build the dialog so it only exists if the user invokes
	# it. AcceptDialog has OK/Cancel built in; we add a LineEdit.
	if _save_as_dialog == null:
		_save_as_dialog = AcceptDialog.new()
		_save_as_dialog.title = "Save As"
		_save_as_dialog.ok_button_text = "Save"
		_save_as_dialog.add_cancel_button("Cancel")
		_save_as_input = LineEdit.new()
		_save_as_input.placeholder_text = "save_name"
		_save_as_input.custom_minimum_size = Vector2(280, 0)
		_save_as_dialog.add_child(_save_as_input)
		_save_as_dialog.register_text_enter(_save_as_input)
		_save_as_dialog.confirmed.connect(_on_save_as_confirmed)
		add_child(_save_as_dialog)
	_save_as_input.text = ""
	_save_as_dialog.popup_centered()
	_save_as_input.grab_focus()


func _on_save_as_confirmed() -> void:
	var name_val: String = _save_as_input.text.strip_edges()
	if name_val == "":
		GameState.show_toast(
			"save-as: name required", ThemePalette.WARN
		)
		return
	NetworkManager.admin_save_as(name_val, _on_save_as_response)


func _on_save_as_response(code: int, body: String) -> void:
	if code == 201:
		var parsed = JSON.parse_string(body)
		var saved_name := ""
		if parsed is Dictionary:
			saved_name = str(parsed.get("name", ""))
		GameState.show_toast(
			"saved as: %s" % saved_name, ThemePalette.SUCCESS
		)
		return
	# 400 / 404 etc — surface server's error string.
	var err_msg := "save-as failed (%d)" % code
	var parsed_err = JSON.parse_string(body)
	if parsed_err is Dictionary and parsed_err.has("error"):
		err_msg = "save-as: %s" % parsed_err["error"]
	GameState.show_toast(err_msg, ThemePalette.DANGER)
