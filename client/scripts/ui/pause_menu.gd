extends PanelContainer

## Pause overlay. Toggled by ESC from main.gd. While visible:
##   - `get_tree().paused = true` freezes Godot nodes with the default
##     PROCESS_MODE_INHERIT — ships, particles, camera updates, etc.
##   - A `sim_control: pause` WS command also stops the Rust sim's
##     tick loop so time in the world actually halts (otherwise the
##     sim keeps ticking and the moment you unpause, everything
##     jumps forward catching up).
##   - This node sets `process_mode = PROCESS_MODE_ALWAYS` so its
##     buttons + input stay responsive despite the paused tree.
##
## Menu items:
##   - Resume          → hide + unpause
##   - Save            → POST /api/admin/save (no-op ack; persistence
##                       auto-flushes every 5 s, this is more of a
##                       "reassure the player" button)
##   - Save As…        → inline name input → POST /api/admin/save-as
##   - Options         → lazy-instance the OptionsPanel
##   - Return to Menu  → stop sim, load main_menu.tscn
##   - Exit            → quit application
##
## Back buttons on sub-panels (Options, Save-As input) route back to
## the root pause menu, not all the way out. Feels like a proper
## nested menu.

signal resume_requested

const OptionsPanelScript := preload(
  "res://scripts/ui/options_panel.gd"
)
const ThemePalette := preload("res://scripts/ui/theme_palette.gd")

var _root_vbox: VBoxContainer
var _save_as_panel: PanelContainer
var _save_as_input: LineEdit
var _status_label: Label
var _options_panel: PanelContainer = null


func _ready() -> void:
  # PROCESS_MODE_ALWAYS so our buttons still fire when the scene tree
  # is paused. Without this, the menu would freeze alongside the game
  # and ESC'ing out would be the only working input.
  process_mode = Node.PROCESS_MODE_ALWAYS
  custom_minimum_size = Vector2(360, 0)
  _build_ui()


# ---------------------------------------------------------------------------
# External entry points
# ---------------------------------------------------------------------------

func show_menu() -> void:
  _status_label.text = ""
  _show_root()
  visible = true


func hide_menu() -> void:
  visible = false
  _save_as_panel.visible = false
  if _options_panel:
    _options_panel.hide_panel()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
  var outer := VBoxContainer.new()
  outer.add_theme_constant_override(&"separation", 10)
  add_child(outer)

  # Title
  var title := Label.new()
  title.text = "Paused"
  title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  title.add_theme_font_size_override(&"font_size", 22)
  outer.add_child(title)
  outer.add_child(HSeparator.new())

  # Root button stack
  _root_vbox = VBoxContainer.new()
  _root_vbox.add_theme_constant_override(&"separation", 6)
  outer.add_child(_root_vbox)
  _add_button(_root_vbox, "Resume", _on_resume_pressed)
  _add_button(_root_vbox, "Save", _on_save_pressed)
  _add_button(_root_vbox, "Save As…", _on_save_as_pressed)
  _add_button(_root_vbox, "Options", _on_options_pressed)
  _add_button(_root_vbox, "Return to Menu", _on_return_to_menu_pressed)
  _add_button(_root_vbox, "Exit", _on_exit_pressed)

  # Save-As sub-panel (hidden until requested). Built inline so the
  # whole pause menu is one node.
  _save_as_panel = PanelContainer.new()
  _save_as_panel.visible = false
  outer.add_child(_save_as_panel)
  var sav_vbox := VBoxContainer.new()
  sav_vbox.add_theme_constant_override(&"separation", 6)
  _save_as_panel.add_child(sav_vbox)

  var sav_title := Label.new()
  sav_title.text = "Save As"
  sav_title.add_theme_font_size_override(&"font_size", 16)
  sav_vbox.add_child(sav_title)

  _save_as_input = LineEdit.new()
  _save_as_input.placeholder_text = "campaign1"
  _save_as_input.custom_minimum_size = Vector2(0, 32)
  sav_vbox.add_child(_save_as_input)

  var sav_row := HBoxContainer.new()
  sav_row.alignment = BoxContainer.ALIGNMENT_END
  sav_row.add_theme_constant_override(&"separation", 6)
  sav_vbox.add_child(sav_row)
  var cancel_btn := Button.new()
  cancel_btn.text = "Cancel"
  cancel_btn.pressed.connect(_show_root)
  sav_row.add_child(cancel_btn)
  var submit_btn := Button.new()
  submit_btn.text = "Save"
  submit_btn.pressed.connect(_on_save_as_submit)
  sav_row.add_child(submit_btn)

  # Toast-style status line at the bottom. Shows save results + errors.
  _status_label = Label.new()
  _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  _status_label.add_theme_color_override(
    &"font_color", Color(0.8, 0.85, 0.9)
  )
  outer.add_child(_status_label)


func _add_button(
  parent: Container, text: String, handler: Callable
) -> Button:
  var btn := Button.new()
  btn.text = text
  btn.custom_minimum_size = Vector2(0, 40)
  btn.pressed.connect(handler)
  parent.add_child(btn)
  return btn


# ---------------------------------------------------------------------------
# Visibility helpers — switching between root / save-as / options
# ---------------------------------------------------------------------------

func _show_root() -> void:
  _root_vbox.visible = true
  _save_as_panel.visible = false
  if _options_panel:
    _options_panel.hide_panel()


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_resume_pressed() -> void:
  resume_requested.emit()


func _on_save_pressed() -> void:
  _status_label.text = "Saving…"
  NetworkManager.admin_save(
    func(code: int, _body: String):
      if code == 200 or code == 204:
        _status_label.text = "Saved."
      else:
        _status_label.text = "Save failed (%d)." % code
  )


func _on_save_as_pressed() -> void:
  _root_vbox.visible = false
  _save_as_panel.visible = true
  _save_as_input.grab_focus()


func _on_save_as_submit() -> void:
  var raw := _save_as_input.text.strip_edges()
  if raw == "":
    _status_label.text = "Enter a name."
    return
  _save_as_panel.visible = false
  _root_vbox.visible = true
  SaveAsSwitch.perform(
    raw,
    func(_level: String, msg: String) -> void:
      _status_label.text = msg,
    func() -> void:
      # New sim is up on the fresh DB. Unpause + reload the main
      # scene so we bootstrap against the new backend cleanly, the
      # same way Load-Game does.
      get_tree().paused = false
      get_tree().change_scene_to_file("res://scenes/main.tscn")
  )


func _on_options_pressed() -> void:
  if _options_panel == null:
    _options_panel = OptionsPanelScript.new()
    _options_panel.custom_minimum_size = Vector2(360, 0)
    add_child(_options_panel)
    _options_panel.back_requested.connect(_show_root)
  _root_vbox.visible = false
  _save_as_panel.visible = false
  _options_panel.show_panel()


func _on_return_to_menu_pressed() -> void:
  # Unpause so the main menu scene isn't born paused. Stop the sim if
  # we spawned it (stop() is a no-op in dev mode where we connect to
  # an external server). Send an explicit sim-resume too so if the
  # sim *is* external and still running, ticks don't get stuck paused
  # from our pause command earlier.
  get_tree().paused = false
  NetworkManager.send_sim_control("resume")
  ServerManager.stop()
  get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_exit_pressed() -> void:
  # Unpause so _exit_tree cleanup can run in the autoloads' processes
  # as usual (ServerManager.stop, persistence worker flush).
  get_tree().paused = false
  get_tree().quit()
