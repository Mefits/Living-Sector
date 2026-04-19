extends PanelContainer

## God-mode toolbar at the bottom-left. Three actions:
##   - Destroy: toggles a persistent destroy-mode cursor (left-click
##     any ship/facility in the viewport to delete). ESC or re-click
##     to exit.
##   - + Ship: opens the Add Ship panel
##   - + Facility: opens the Add Facility panel
##
## State for destroy-mode and panel visibility lives on main.gd.
## This is just the UI surface.

signal destroy_toggled(active: bool)
signal add_ship_pressed
signal add_facility_pressed

@onready var destroy_button: Button = $HBox/DestroyButton
@onready var add_ship_button: Button = $HBox/AddShipButton
@onready var add_facility_button: Button = $HBox/AddFacilityButton


func _ready() -> void:
	destroy_button.toggled.connect(_on_destroy_toggled)
	add_ship_button.pressed.connect(func(): add_ship_pressed.emit())
	add_facility_button.pressed.connect(
		func(): add_facility_pressed.emit()
	)


func set_destroy_pressed(active: bool) -> void:
	## Main.gd calls this when destroy mode is cancelled externally
	## (ESC, or a destroy fired). Keeps the button visual in sync
	## without re-firing the toggled signal.
	if destroy_button.button_pressed != active:
		destroy_button.set_pressed_no_signal(active)


func _on_destroy_toggled(active: bool) -> void:
	destroy_toggled.emit(active)
