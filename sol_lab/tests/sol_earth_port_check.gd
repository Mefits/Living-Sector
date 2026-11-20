extends SceneTree
## Launch the normal game, then mount the same scene the district will mount.
## Optional SOL_PORT_FRAMES points to a writable folder for rendered evidence.
const Lab = preload("res://scripts/main.gd")
const Port = preload("res://sol_lab/earth_port/EarthPort.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
		push_error("Use an isolated user-data directory")
		quit(1)
		return
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	var game = current_scene
	game._pause()
	var sim = game.construction
	assert(sim.expedition.depart(0.0))
	sim.advance_to(sim.expedition.ship.arrival)
	assert(sim.order("luna", "spaceport").ok)
	assert(sim.order("earth", "shipyard").ok)
	sim.advance_to(sim.sites.back().finish_native)
	var earth: Dictionary = sim._market_for("earth").supply
	earth.metals = 110
	for facility in game.world.facilities:
		if facility.type == "shipyard":
			assert(sim.order_second_freighter(facility.id))
	assert(not sim.ship_order.is_empty())
	sim.advance_to(sim.ship_order.finish_native)
	var lunar: Dictionary = sim._market_for("luna").supply
	lunar.ore = 13
	var port = Port.instantiate()
	var layer := CanvasLayer.new()
	game.add_child(layer)
	var backing := ColorRect.new()
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backing.color = Color("#151e1a")
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backing)
	layer.add_child(port)
	port.position = Vector2(495, 267)
	port.scale = Vector2.ONE * 3.3
	port.bind_runtime(sim, "earth")
	var heading := Label.new()
	layer.add_child(heading)
	heading.position = Vector2(75, 17)
	heading.add_theme_font_size_override("font_size", 22)
	var out := OS.get_environment("SOL_PORT_FRAMES")
	var initial_metals := float(earth.metals)
	for slot in [1, 2]:
		assert(sim.depart_manual_freight("luna", "metals", 4, slot))
	assert(earth.metals == initial_metals - 8)
	await frame(heading, out, "01-loading", "Земля · погрузка двух бортов")
	sim.advance_to(maxf(sim.freight_status(1).arrival, sim.freight_status(2).arrival))
	assert(sim.depart_manual_freight("earth", "ore", 3, 1))
	assert(sim.depart_manual_freight("earth", "ore", 10, 2))
	var eta: float = sim.freight_status(1).arrival
	assert(is_equal_approx(eta, sim.freight_status(2).arrival))
	var before := float(earth.ore)
	sim.advance_to(eta - 0.43)
	assert(earth.ore == before)
	await frame(heading, out, "02-approach", "Земля · два грузовика на заходе")
	sim.advance_to(eta)
	assert(earth.ore == before + 13)
	await frame(heading, out, "03-touchdown", "Земля · посадка, склад получил 13 ед. руды")
	sim.advance_to(eta + 3.25 * 0.35)
	await frame(heading, out, "04-pickup", "Земля · перегрузка контейнеров на погрузчики")
	port.queue_free()
	await process_frame
	game._set_speed(16)
	game.native_time = sim.now_native
	game._step()
	assert(sim.now_native > eta + 3.25 * 0.35)
	assert(earth.ore == before + 13)
	port = Port.instantiate()
	layer.add_child(port)
	port.position = Vector2(495, 267)
	port.scale = Vector2.ONE * 3.3
	port.bind_runtime(sim, "earth")
	sim.advance_to(maxf(sim.now_native, eta + 3.25 * 0.72))
	await frame(heading, out, "05-road", "Земля · погрузчики везут партии к складу")
	sim.advance_to(maxf(sim.now_native, eta + 3.25 * 0.94))
	await frame(heading, out, "06-gate", "Земля · контейнеры у ворот склада")
	sim.advance_to(maxf(sim.now_native, eta + 3.25))
	assert(earth.ore == before + 13)
	await frame(heading, out, "07-empty", "Земля · пустые грузовики на площадках")
	assert(sim.depart_manual_freight("luna", "metals", 1, 1))
	sim.advance_to(sim.freight_status().arrival)
	assert(sim.depart_manual_freight("earth", "ore", 0, 1))
	sim.advance_to(sim.freight_status().arrival)
	assert(earth.ore == before + 13)
	assert(sim.earth_port_state().bays[0].last_arrival.amount == 0)
	port.queue_free()
	await process_frame
	assert(sim.depart_manual_freight("luna", "metals", 1, 1))
	sim.advance_to(sim.freight_status().arrival)
	lunar.ore = 2
	assert(sim.depart_manual_freight("earth", "ore", 2, 1))
	sim.advance_to(sim.freight_status().arrival - 1)
	game.native_time = sim.now_native
	game._step()
	assert(earth.ore == before + 15)
	assert(sim.earth_port_state().bays[0].last_arrival.amount == 2)
	game._step()
	assert(earth.ore == before + 15)
	print("SOL_EARTH_PORT_PASS")
	quit()

func frame(heading: Label, folder: String, filename: String, title: String) -> void:
	heading.text = title
	await process_frame
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(folder.path_join(filename + ".png")) == OK)
