extends PanelContainer

## Options panel. Built programmatically so there's one file to edit
## when adding new settings — no .tscn to keep in sync. Drops in like
## the save picker: main menu toggles its `visible` flag to show/hide.
##
## Currently: Music + SFX volume sliders (linear 0–1, piped through
## SettingsManager which owns the audio buses + persistence). Adding
## a new row is just another `_add_slider` call.

signal back_requested

const ThemePalette := preload("res://scripts/ui/theme_palette.gd")

var _music_slider: HSlider
var _music_readout: Label
var _sfx_slider: HSlider
var _sfx_readout: Label


func _ready() -> void:
  custom_minimum_size = Vector2(480, 0)
  _build_ui()
  _refresh_from_settings()


func _build_ui() -> void:
  var vbox := VBoxContainer.new()
  vbox.add_theme_constant_override(&"separation", 10)
  add_child(vbox)

  var title := Label.new()
  title.text = "Options"
  title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  title.add_theme_font_size_override(&"font_size", 20)
  vbox.add_child(title)

  vbox.add_child(HSeparator.new())

  var header_audio := Label.new()
  header_audio.text = "Audio"
  header_audio.add_theme_font_size_override(&"font_size", 15)
  header_audio.add_theme_color_override(
    &"font_color", ThemePalette.PRIMARY
  )
  vbox.add_child(header_audio)

  var music_row := _add_slider(
    vbox, "Music", SettingsManager.music_volume_linear,
    _on_music_changed
  )
  _music_slider = music_row[0]
  _music_readout = music_row[1]

  var sfx_row := _add_slider(
    vbox, "Sound Effects", SettingsManager.sfx_volume_linear,
    _on_sfx_changed
  )
  _sfx_slider = sfx_row[0]
  _sfx_readout = sfx_row[1]

  vbox.add_child(HSeparator.new())

  var footer := HBoxContainer.new()
  footer.alignment = BoxContainer.ALIGNMENT_END
  vbox.add_child(footer)
  var back_btn := Button.new()
  back_btn.text = "Back"
  back_btn.pressed.connect(_on_back_pressed)
  footer.add_child(back_btn)


func _add_slider(
  parent: Container, label_text: String, initial: float, cb: Callable
) -> Array:
  ## Emits a [slider, readout_label] pair so the caller can update
  ## both when the settings change externally.
  var row := HBoxContainer.new()
  row.add_theme_constant_override(&"separation", 8)
  var lbl := Label.new()
  lbl.text = label_text
  lbl.custom_minimum_size = Vector2(130, 0)
  row.add_child(lbl)

  var slider := HSlider.new()
  slider.min_value = 0.0
  slider.max_value = 1.0
  slider.step = 0.01
  slider.value = initial
  slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  slider.value_changed.connect(cb)
  row.add_child(slider)

  var readout := Label.new()
  readout.custom_minimum_size = Vector2(45, 0)
  readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
  readout.text = "%d%%" % int(initial * 100.0)
  readout.add_theme_color_override(
    &"font_color", Color(0.9, 0.9, 0.5)
  )
  row.add_child(readout)

  parent.add_child(row)
  return [slider, readout]


func _refresh_from_settings() -> void:
  ## Called when opening the panel so sliders reflect the current
  ## settings (someone could have changed them via another flow, or
  ## the save file could have been edited between sessions).
  if _music_slider:
    _music_slider.set_value_no_signal(
      SettingsManager.music_volume_linear
    )
    _music_readout.text = "%d%%" % int(
      SettingsManager.music_volume_linear * 100.0
    )
  if _sfx_slider:
    _sfx_slider.set_value_no_signal(
      SettingsManager.sfx_volume_linear
    )
    _sfx_readout.text = "%d%%" % int(
      SettingsManager.sfx_volume_linear * 100.0
    )


# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_music_changed(value: float) -> void:
  SettingsManager.set_music_volume(value)
  _music_readout.text = "%d%%" % int(value * 100.0)


func _on_sfx_changed(value: float) -> void:
  SettingsManager.set_sfx_volume(value)
  _sfx_readout.text = "%d%%" % int(value * 100.0)


func _on_back_pressed() -> void:
  back_requested.emit()


# ---------------------------------------------------------------------------
# External entry points
# ---------------------------------------------------------------------------

func show_panel() -> void:
  _refresh_from_settings()
  visible = true


func hide_panel() -> void:
  visible = false
