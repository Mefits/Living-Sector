extends Control

## Title screen. Spawns / connects to the simulator via ServerManager,
## then transitions into the main game scene on success.
##
## Load Game opens an inline save picker that lists .db files in the
## sim's saves directory (via DirAccess — no server needed since we
## may not have one running yet). Picking a save calls
## ServerManager.start(..., database_path) so the spawned BEAM opens
## that file instead of the default sim.db.

@onready var start_button: Button = $CenterContainer/VBox/StartButton
@onready var load_button: Button = $CenterContainer/VBox/LoadButton
@onready var quit_button: Button = $CenterContainer/VBox/QuitButton
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var menu_buttons: VBoxContainer = $CenterContainer/VBox
@onready var save_picker: PanelContainer = $SavePicker
@onready var rows_box: VBoxContainer = $SavePicker/VBox/RowsBox
@onready var empty_label: Label = $SavePicker/VBox/EmptyLabel
@onready var back_button: Button = $SavePicker/VBox/Footer/BackButton
@onready var loading_overlay: ColorRect = $LoadingOverlay
@onready var loading_label: Label = $LoadingOverlay/CenterBox/VBox/LoadingLabel

var _overlay_tween: Tween


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	load_button.pressed.connect(_on_load_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_hide_save_picker)
	if ServerManager.last_error != "":
		status_label.text = "Simulator stopped: %s" % ServerManager.last_error


# -------------------- Start / Load / Quit --------------------

func _on_start_pressed() -> void:
	_disable_buttons()
	_show_loading("Starting simulator…")
	ServerManager.start(_on_start_result)


func _on_load_pressed() -> void:
	_show_save_picker()


func _on_start_result(status: int, message: String) -> void:
	if status == OK:
		# Push overlay to full opacity briefly so the handoff reads
		# as a deliberate transition rather than an abrupt cut.
		_fade_overlay_then(1.0, 0.18, func():
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		)
	else:
		_hide_loading()
		_enable_buttons()
		status_label.text = "Failed to start: %s" % message


func _on_quit_pressed() -> void:
	get_tree().quit()


# -------------------- Save picker --------------------

func _show_save_picker() -> void:
	_populate_saves()
	menu_buttons.visible = false
	save_picker.visible = true


func _hide_save_picker() -> void:
	save_picker.visible = false
	menu_buttons.visible = true


func _populate_saves() -> void:
	for child in rows_box.get_children():
		child.queue_free()

	var dir_path := ServerManager.saves_dir()
	var active_path := ServerManager.default_database_path()
	var entries: Array = _scan_saves(dir_path)
	entries.sort_custom(
		func(a, b): return str(a.modified) > str(b.modified)
	)

	empty_label.visible = entries.is_empty()
	for e in entries:
		_add_save_row(e, e.path == active_path)


func _scan_saves(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	while true:
		var n := d.get_next()
		if n == "":
			break
		if d.current_is_dir():
			continue
		if not n.ends_with(".db"):
			continue
		var full := dir_path.path_join(n)
		out.append({
			"name": n.trim_suffix(".db"),
			"filename": n,
			"path": full,
			"size": FileAccess.get_file_as_bytes(full).size(),
			"modified": FileAccess.get_modified_time(full),
		})
	d.list_dir_end()
	return out


func _add_save_row(entry: Dictionary, is_active: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	var title_text: String = entry.name
	if is_active:
		title_text += " (current)"
	title.text = title_text
	title.theme_override_font_sizes = {"font_size": 15}
	info.add_child(title)

	var subtitle := Label.new()
	var modified_unix: int = entry.modified
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(modified_unix)
	var when: String = "%04d-%02d-%02d %02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute
	]
	var size_kb: float = float(entry.size) / 1024.0
	subtitle.text = "%s  ·  %.0f KB" % [when, size_kb]
	subtitle.modulate = Color(0.7, 0.75, 0.85, 1)
	info.add_child(subtitle)

	row.add_child(info)

	var btn := Button.new()
	btn.text = "Load"
	btn.pressed.connect(_on_load_save.bind(entry.path))
	row.add_child(btn)

	rows_box.add_child(row)


func _on_load_save(database_path: String) -> void:
	_hide_save_picker()
	_disable_buttons()
	_show_loading("Loading save…")
	ServerManager.start(_on_start_result, database_path)


# -------------------- Loading overlay --------------------

func _show_loading(msg: String) -> void:
	loading_label.text = msg
	loading_overlay.modulate.a = 0.0
	loading_overlay.visible = true
	_fade_overlay_then(1.0, 0.22, Callable())


func _hide_loading() -> void:
	_fade_overlay_then(0.0, 0.25, func():
		loading_overlay.visible = false
	)


func _fade_overlay_then(
	target_alpha: float, duration: float, on_done: Callable
) -> void:
	if _overlay_tween != null and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween()
	_overlay_tween.tween_property(
		loading_overlay, "modulate:a", target_alpha, duration
	)
	if on_done.is_valid():
		_overlay_tween.tween_callback(on_done)


# -------------------- Helpers --------------------

func _disable_buttons() -> void:
	start_button.disabled = true
	load_button.disabled = true
	quit_button.disabled = true


func _enable_buttons() -> void:
	start_button.disabled = false
	load_button.disabled = false
	quit_button.disabled = false
