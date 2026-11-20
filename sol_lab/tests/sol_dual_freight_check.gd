extends SceneTree
# Run with an isolated XDG_DATA_HOME.
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
		push_error("Use an isolated user-data directory")
		quit(1)
		return
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var g = current_scene
	g._pause()
	var r = g.construction
	var legacy: Dictionary = r.snapshot()
	legacy.version = 6
	legacy.erase("second_freighter")
	legacy.erase("ship_order")
	assert(r.restore(legacy))
	assert(r.freight_status(2).is_empty())
	assert(r.expedition.depart(0.0))
	r.advance_to(r.expedition.ship.arrival)
	assert(r.order("luna", "spaceport").ok)
	assert(r.order("earth", "shipyard").ok)
	r.advance_to(r.sites.back().finish_native)
	var yard: String
	for f in g.world.facilities:
		if f.type == "shipyard":
			yard = f.id
	var earth: Dictionary = r._market_for("earth").supply
	earth.metals = 110
	assert(r.configure_freight_line({"luna":{"resource":"food","amount":10,"reserve":0},"earth":{"resource":"ore","amount":10,"reserve":0}}))
	r.set_freight_line_enabled(true)
	r.advance_to(r.now_native)
	r.advance_to(r.freight_status().arrival)
	assert(r.freight_status().location == "luna" and not r.freight_line_wait().is_empty())
	g.native_time = r.now_native
	g._activate_facility(yard)
	assert(g.yard_controls.visible and not g.yard_order.disabled)
	g.yard_order.pressed.emit()
	assert(earth.metals == 30)
	g.yard_cancel.pressed.emit()
	assert(earth.metals == 110 and not r.cancel_second_freighter(yard))
	g.yard_order.pressed.emit()
	r.advance_to(r.now_native + Calendar.days_to_native(14))
	g.native_time = r.now_native
	g._save_game()
	g._load_game()
	assert(r.colony_inventory("earth").supply.metals == 30 and r.progress(r.ship_order) > 0.4)
	r.advance_to(r.ship_order.finish_native)
	assert(r.freight_status(2).location == "earth" and r.freight_status().location == "luna")
	g.native_time = r.now_native
	var lunar_before: float = r.colony_inventory("luna").supply.metals
	g._open_manual_freight()
	assert(g._manual_ship_slot() == 2 and not g.manual_freight_dialog.get_ok_button().disabled)
	g._submit_manual_freight()
	assert(r.colony_inventory("earth").supply.metals == 20 and r.freight_status(2).order.resource == "metals")
	r._market_for("luna").supply.ore = 10
	r.advance_to(r.now_native)
	assert(r.freight_status().order.resource == "ore")
	g._save_game()
	g._load_game()
	assert(r.freight_status().location == "transit" and r.freight_status(2).location == "transit")
	var ore_before: float = r.colony_inventory("earth").supply.ore
	r.advance_to(maxf(r.freight_status().arrival, r.freight_status(2).arrival))
	r.advance_to(r.now_native)
	assert(r.colony_inventory("luna").supply.metals == lunar_before + 10)
	assert(r.colony_inventory("earth").supply.metals == 20)
	assert(r.freight_line().enabled and r.freight_status(2).location == "luna")
	assert(r.colony_inventory("earth").supply.ore == ore_before + 10)
	assert(r.freight_status().location == "earth" or r.freight_status().order.source == "earth")
	DirAccess.remove_absolute(Lab.USER_SAVE)
	print("SOL_DUAL_FREIGHT_PASS")
	quit()
