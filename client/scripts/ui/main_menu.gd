extends Control

## Title screen. Spawns / connects to the simulator via ServerManager,
## then transitions into the main game scene on success.
##
## Load Game opens an inline save picker that lists .db files in the
## sim's saves directory (via DirAccess — no server needed since we
## may not have one running yet). Picking a save calls
## ServerManager.start(..., save_name) so the spawned Rust sim opens
## that file instead of the default sim.db. Each row also offers a
## delete action that wipes the `.db` (plus any WAL sidecars) after
## a confirmation prompt.

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

## Shared ConfirmationDialog for the delete flow. Lazily created on
## first use so the scene tree stays light when nobody's deleting.
## The `confirmed` signal is hooked once and rebound per-row via a
## pending-save-name member so we don't fan out to many dialogs.
var _delete_confirm: ConfirmationDialog = null
var _pending_delete_name: String = ""


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
  # Godot 4 doesn't let you assign the whole theme_override_font_sizes
  # dict as a property — use the virtual setter instead.
  title.add_theme_font_size_override(&"font_size", 15)
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
  # Pass the bare save name (basename minus `.db`), not the full path.
  # ServerManager.start now only accepts names and always resolves
  # under saves_dir — no absolute-path escape hatch.
  btn.pressed.connect(_on_load_save.bind(entry.name))
  row.add_child(btn)

  # Delete button. Tinted red to signal "destructive" without needing
  # a custom theme — `modulate` colours the whole button including
  # its label, which is enough to make the intent read at a glance.
  # Confirmation dialog gates the actual file removal.
  var del := Button.new()
  del.text = "Delete"
  del.modulate = Color(1.0, 0.55, 0.55, 1.0)
  del.pressed.connect(_on_delete_pressed.bind(entry.name))
  row.add_child(del)

  rows_box.add_child(row)


func _on_load_save(save_name: String) -> void:
  _hide_save_picker()
  _disable_buttons()
  _show_loading("Loading save…")
  ServerManager.start(_on_start_result, save_name)


# -------------------- Delete --------------------

func _on_delete_pressed(save_name: String) -> void:
  ## First click on a row's Delete button: stash which save we're
  ## about to remove and pop the confirmation dialog. The dialog's
  ## `confirmed` handler consults `_pending_delete_name` so we
  ## don't multiplex a dialog per row.
  _pending_delete_name = save_name
  _ensure_delete_dialog()
  # Dialog text rebuilt each time so the current save name shows.
  # ConfirmationDialog.dialog_text accepts plain text; line breaks
  # inside get respected at render time.
  _delete_confirm.dialog_text = (
    "Delete save \"%s\"?\nThis permanently removes the "
    + "database file and cannot be undone."
  ) % save_name
  _delete_confirm.popup_centered()


func _ensure_delete_dialog() -> void:
  if _delete_confirm != null:
    return
  _delete_confirm = ConfirmationDialog.new()
  _delete_confirm.title = "Delete save"
  _delete_confirm.ok_button_text = "Delete"
  _delete_confirm.cancel_button_text = "Cancel"
  _delete_confirm.confirmed.connect(_on_delete_confirmed)
  # Parent to the save picker so focus returns there when dismissed.
  save_picker.add_child(_delete_confirm)


func _on_delete_confirmed() -> void:
  # Avoid a `name` local that would shadow Node.name — use
  # `target_name` explicitly.
  var target_name := _pending_delete_name
  _pending_delete_name = ""
  if target_name == "":
    return
  var removed := _delete_save(target_name)
  if removed:
    status_label.text = "Deleted save: %s" % target_name
  else:
    status_label.text = "Failed to delete save: %s" % target_name
  # Rebuild the list regardless — whatever state we're in, the UI
  # should reflect what's now on disk.
  _populate_saves()


func _delete_save(save_name: String) -> bool:
  ## Remove the `.db` plus its SQLite sidecars (WAL mode leaves
  ## `-wal` and `-shm` files behind if the sim was killed mid-write).
  ## Returns true if the main `.db` file was removed; sidecar
  ## removals are best-effort.
  var path := ServerManager.database_path_for_name(save_name)
  if path == "" or not FileAccess.file_exists(path):
    push_warning("[MainMenu] delete: no file at %s" % path)
    return false
  var err := DirAccess.remove_absolute(path)
  if err != OK:
    push_error(
      "[MainMenu] delete failed: %s (err=%d)" % [path, err]
    )
    return false
  # Best-effort sidecar cleanup. Both files may not exist on a
  # cleanly-shutdown sim; ignore OK-or-NOT-FOUND outcomes.
  for suffix in ["-wal", "-shm"]:
    var sidecar := path + suffix
    if FileAccess.file_exists(sidecar):
      DirAccess.remove_absolute(sidecar)
  print("[MainMenu] deleted save: %s" % path)
  return true


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
