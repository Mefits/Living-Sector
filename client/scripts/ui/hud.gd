extends CanvasLayer

## HUD overlay showing tick count, FPS, ship count, simulation speed controls,
## and observer toggle.

signal observer_toggled(active: bool)
signal ship_list_toggled
signal market_toggled
signal contracts_toggled
signal factions_toggled
signal pops_toggled
signal retirements_toggled
signal events_toggled
signal perf_toggled
signal step_requested(ticks: int)

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
@onready var contracts_button: Button = %ContractsButton
@onready var factions_button: Button = %FactionsButton
@onready var pops_button: Button = %PopsButton
@onready var retirements_button: Button = %RetirementsButton
@onready var events_button: Button = %EventsButton
@onready var perf_button: Button = %PerfButton
@onready var step1_button: Button = %Step1Button
@onready var step8_button: Button = %Step8Button
var _observer_active := false


func _ready() -> void:
	GameState.tick_updated.connect(_on_tick_updated)
	GameState.world_loaded.connect(_on_world_loaded)
	NetworkManager.connected.connect(func(): status_label.text = "Connected")
	NetworkManager.disconnected.connect(
		func(): status_label.text = "Disconnected"
	)

	pause_button.pressed.connect(_on_pause_pressed)
	# Speed buttons tune `world_speed` (gameplay pace) — NOT tick
	# resolution. `1×` = default chill play speed (0.25 world_speed,
	# Earth↔Mars ≈ 4 min). `10×` = 2.5 world_speed (≈ 25 s). Tick
	# resolution stays put so client smoothness is independent.
	speed_1x_button.pressed.connect(func(): _set_world_speed(0.25))
	speed_2x_button.pressed.connect(func(): _set_world_speed(0.5))
	speed_5x_button.pressed.connect(func(): _set_world_speed(1.25))
	speed_10x_button.pressed.connect(func(): _set_world_speed(2.5))
	observer_button.pressed.connect(_on_observer_pressed)
	ship_list_button.pressed.connect(
		func(): ship_list_toggled.emit()
	)
	market_button.pressed.connect(
		func(): market_toggled.emit()
	)
	contracts_button.pressed.connect(
		func(): contracts_toggled.emit()
	)
	factions_button.pressed.connect(
		func(): factions_toggled.emit()
	)
	pops_button.pressed.connect(
		func(): pops_toggled.emit()
	)
	retirements_button.pressed.connect(
		func(): retirements_toggled.emit()
	)
	events_button.pressed.connect(
		func(): events_toggled.emit()
	)
	perf_button.pressed.connect(
		func(): perf_toggled.emit()
	)
	step1_button.pressed.connect(
		func(): step_requested.emit(1)
	)
	step8_button.pressed.connect(
		func(): step_requested.emit(8)
	)

	status_label.text = "Connecting..."


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _on_tick_updated(tick: int) -> void:
	tick_label.text = "Tick: %d" % tick


func _on_world_loaded() -> void:
	ship_count_label.text = "Ships: %d" % GameState.ships.size()
	_update_speed_label()
	_sync_step_buttons()


const _PAUSE_ICON := preload("res://assets/icons/ui/pause.svg")
const _PLAY_ICON := preload("res://assets/icons/ui/play.svg")


func _on_pause_pressed() -> void:
	if GameState.running:
		NetworkManager.post_sim_control("pause")
		GameState.running = false
		pause_button.text = "Resume"
		pause_button.icon = _PLAY_ICON
	else:
		NetworkManager.post_sim_control("resume")
		GameState.running = true
		pause_button.text = "Pause"
		pause_button.icon = _PAUSE_ICON
	_sync_step_buttons()


func _sync_step_buttons() -> void:
	# Step buttons only make sense while the tick loop is halted —
	# stepping a running sim is a no-op against the server-side clock
	# and just confuses the HUD. Tooltip flips too so the player
	# understands why they're greyed out.
	var paused := not GameState.running
	step1_button.disabled = not paused
	step8_button.disabled = not paused
	step1_button.tooltip_text = (
		"Step 1 tick" if paused else "Step 1 tick (pause first)"
	)
	step8_button.tooltip_text = (
		"Step 8 ticks" if paused else "Step 8 ticks (pause first)"
	)


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
	## Route via HTTP — world-speed changes land on the next tick. HTTP
	## responses aren't consumed here, so update GameState optimistically
	## so the HUD label reflects the change immediately. The next
	## server_hello heartbeat (or /api/report refresh) will authoritatively
	## reconcile it.
	GameState.world_speed = world_speed
	NetworkManager.post_sim_control(
		"set_world_speed", {"world_speed": world_speed}
	)
	_update_speed_label()


func _update_speed_label() -> void:
	## Format GameState.world_speed as a clean ×-suffixed string.
	## Read this from world_speed (gameplay pace) — NOT tick_interval_ms
	## (which is resolution/smoothness). The old impl computed
	## `250 / tick_interval_ms` which always returned 2 at default
	## tick_interval_ms=125, so the label never changed.
	var ws: float = GameState.world_speed
	# Drop trailing zeros: 0.25×, 0.5×, 1×, 2.5×.
	var text: String
	if absf(ws - roundf(ws)) < 0.01:
		text = "Speed: %dx" % int(roundf(ws))
	elif absf(ws * 10.0 - roundf(ws * 10.0)) < 0.01:
		text = "Speed: %.1fx" % ws
	else:
		text = "Speed: %.2fx" % ws
	speed_label.text = text


