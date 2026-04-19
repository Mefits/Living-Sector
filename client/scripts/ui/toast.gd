extends VBoxContainer

## Toast notification system. Shows brief messages that fade out.
## Call GameState.show_toast("message") from anywhere.

const MAX_TOASTS := 5
const TOAST_DURATION := 4.0
const FADE_DURATION := 0.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_toast(
	message: String, color: Color = ThemePalette.TEXT
) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override(
		"font_shadow_color", Color(0, 0, 0, 0.8)
	)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# Remove oldest if too many
	while get_child_count() > MAX_TOASTS:
		get_child(0).queue_free()

	# Fade out and remove after duration
	var tween := create_tween()
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(label.queue_free)
