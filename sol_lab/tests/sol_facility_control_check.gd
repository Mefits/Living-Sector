extends SceneTree
## Real Sol Lab scenario. Two distinct miners on Earth and Moon, read-only
## production receipts, shared map/list selection and live freight controls.
## With SOL_CAPTURE_FACILITIES=1, capture two 1366x768 UI states.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
var game: Control
var problems: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func verify(ok: bool, message: String) -> void:
 if not ok:
  problems.append(message)
  push_error("SOL_FACILITY_CONTROL_FAIL: " + message)

func choose_planet(body_id: String) -> void:
 for item in game.world.get("bodies", []):
  if str(item.get("id", "")) == body_id:
   game.native_view.body_selected.emit(item)
   return
 verify(false, "Missing planet "+body_id)

func deliver_steps(deadline: float) -> void:
 for i in range(520):
  if game.native_time >= deadline:
   return
  game._step()
 verify(false, "Could not reach in-game deadline: "+str(deadline))

func build(body_id: String, kind: String) -> String:
 choose_planet(body_id)
 game._open_build()
 var control: Dictionary = game.browser.build_controls.get(kind,{})
 verify(not control.is_empty(), "Catalog exists for "+kind)
 if control.is_empty():
  return ""
 var b: Button = control["button"]
 verify(b.visible and not b.disabled, "Order ready: "+kind+" on "+body_id)
 if b.disabled:
  return ""
 var before: int = game.construction.sites.size()
 b.pressed.emit()
 verify(game.browser.placement_panel.visible and
  not game.browser.placement_options.is_empty(),
  "catalog enters placement instead of billing immediately")
 if not game.browser.placement_options.is_empty():
  var site_id: String = str(game.browser.placement_options[0]["id"])
  if not game.district.visible:
   game.native_view.choose_placement(site_id)
  game.browser.select_placement(site_id)
  game.browser.placement_confirm.pressed.emit()
 verify(game.construction.sites.size() == before + 1,
  "Order creates distinct facility: "+kind)
 var id: String = str(game.construction.sites.back().get("id", ""))
 game._close_browser()
 return id

func facility(id: String) -> Dictionary:
 for value in game.world.get("facilities",[]):
  if str(value.get("id", "")) == id:
   return value
 return {}

func actual(id: String) -> Dictionary:
 return game.construction.production_details(id)

func choose_from_list(id: String) -> void:
 var row: Button = game.colony_panel.built_buttons.get(id)
 verify(row != null, "Built list contains ID "+id)
 if row != null:
  row.pressed.emit()
  verify(game.colony_panel.selected_facility == id,
   "Built-list click selected SAME ID "+id)

func pin(id: String) -> Dictionary:
 for value in game.native_view._facility_pins:
  if str(value.get("id", "")) == id:
   return value
 return {}

func choose_from_globe(id: String) -> void:
 var candidate: Dictionary = pin(id)
 verify(not candidate.is_empty(), "Globe has real pin "+id)
 if not candidate.is_empty():
  game.native_view._pick(candidate["position"])
  verify(game.colony_panel.selected_facility == id,
   "Globe click selected SAME ID "+id)

func focus_and_settle(id: String) -> void:
 if game.district.visible:
  game._close_district()
 game.native_view.focus_body(id)
 for i in range(100):
  await process_frame

func capture(slug: String) -> void:
 if OS.get_environment("SOL_CAPTURE_FACILITIES") != "1" or (
     DisplayServer.get_name() == "headless"):
  return
 await create_timer(0.25).timeout
 for i in range(6):
  await process_frame
 await RenderingServer.frame_post_draw
 var image: Image = root.get_texture().get_image()
 verify(image != null and not image.is_empty(), "Screenshot "+slug)
 if image != null and not image.is_empty():
  var name: String = "res://sol-facility-%s-1366x768.png" % slug
  image.save_png(name)
  print("SOL_FACILITY_SCREENSHOT "+ProjectSettings.globalize_path(name))

func _run() -> void:
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_FACILITY_CONTROL_FAIL: require isolated XDG_DATA_HOME")
  quit(1)
  return
 root.size = Vector2i(1366, 768)
 Engine.max_fps = 60
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 game._set_speed(16)
 var earth_start: float = float(game.construction.colony_inventory(
  "earth").get("supply",{}).get("metals",0))
 var earth_1: String = build("earth","mining_rig")
 for i in range(4):
  game._step()
 var earth_2: String = build("earth","mining_rig")
 verify(earth_1 != earth_2 and not earth_1.is_empty() and
  not earth_2.is_empty(), "Two real miner IDs on Earth")
 var site_a: Array = facility(earth_1).get("surface_site",[])
 var site_b: Array = facility(earth_2).get("surface_site",[])
 verify(site_a != site_b and site_a.size() == 2 and site_b.size() == 2,
  "Identical mines have separate persistent globe anchors")
 verify(float(game.construction.colony_inventory(
  "earth").get("supply",{}).get("metals",0)) == earth_start-2,
  "Separate mine orders each debit one metal")
 var due: float = 0.0
 for site in game.construction.sites:
  due = maxf(due,float(site.get("finish_native",0)))
 deliver_steps(due)
 verify(facility(earth_1).get("type") == "mining_rig" and
  facility(earth_2).get("type") == "mining_rig",
  "Both mines completed as separate enterprises")
 var never: Dictionary = actual(earth_2)
 verify(not bool(never.get("last_present",true)) and
  float(never.get("forecast",0)) > 0 and
  is_finite(float(never.get("next_native",INF))),
  "First batch absent and forecast/next date explicitly known")
 choose_from_list(earth_2)
 verify(game.colony_panel.detail_description.text.contains(
  "Выпуска ещё не было") and game.colony_panel.detail_description.text.contains(
  "Прогноз"), "Before first batch card does not pretend output is actual")
 deliver_steps(float(never.get("next_native",0))+0.01)
 var actual_a: Dictionary = actual(earth_1)
 var actual_b: Dictionary = actual(earth_2)
 verify(bool(actual_a.get("last_present",false)) and bool(
  actual_b.get("last_present",false)),
  "Both Earth mining receipts are actual sim batches")
 verify(float(actual_a.get("last_native",0)) != float(
  actual_b.get("last_native",0)),
  "Two same-type enterprises maintain distinct batch clocks")
 choose_from_list(earth_1)
 var first_caption: String = game.colony_panel.detail_title.text
 var first_text: String = game.colony_panel.detail_description.text
 verify(first_text.contains("Фактическая последняя партия") and
  first_text.contains("Прогноз следующего выпуска") and
  first_text.contains("Следующая партия"), "Miner explains actual vs predicted")
 choose_from_list(earth_2)
 verify(game.colony_panel.detail_title.text != first_caption and
  game.colony_panel.detail_description.text != first_text,
  "Selection switches instance-specific production dates")
 await focus_and_settle("earth")
 choose_from_globe(earth_1)
 verify(game.colony_panel.page == "overview" and
  game.colony_panel.detail_description.text.contains(
  "Фактическая последняя партия"), "Globe opens production panel")
 await capture("mine")

 # A source-backed idle reason does not erase the last successful receipt.
 var refinery: String = build("earth", "refinery")
 var refinery_site: float = float(game.construction.sites.back().get(
  "finish_native",0))
 deliver_steps(refinery_site)
 var factory_due: float = float(actual(refinery).get("next_native",0))
 deliver_steps(factory_due)
 if actual(refinery).get("delivery", "").contains("в пути"):
  deliver_steps(float(actual(refinery).get("next_native", 0)))
 verify(bool(actual(refinery).get("last_present",false)),
  "Refinery has first successful actual receipt")
 for market in game.world.get("markets",[]):
  if market.get("facility_id") == "earth-colony":
   market["supply"]["fuel"] = 0.0
 var retry: float = float(actual(refinery).get("next_native",0))
 deliver_steps(retry)
 var blocked: Dictionary = actual(refinery)
 verify(bool(blocked.get("last_present",false)) and
  str(blocked.get("idle_reason","")).contains("топлива"),
  "Concrete shortage preserves last completed batch")
 choose_from_list(refinery)
 verify(game.colony_panel.detail_description.text.contains("Простой") and
  game.colony_panel.detail_description.text.contains(
  "Фактическая последняя партия") and
  game.colony_panel.detail_description.text.contains("Следующая попытка"),
  "Card shows actual, idle reason and retry schedule")

 # Found Moon via actual colonizer, not injected colony data.
 choose_planet("luna")
 verify(game.colony_panel.selected_facility.is_empty(),
  "Switching planets clears stale Earth facility")
 game._colonize_luna()
 var land: float = float(game.construction.expedition.ship.get(
  "arrival",0))
 deliver_steps(land)
 verify(game.construction.colony_population("luna") == 100 and
  float(game.construction.colony_inventory("luna").get(
  "supply",{}).get("metals",0)) == 2.0,
  "Moon founded with authoritative colonizer manifest")
 var port: String = build("luna","spaceport")
 var luna_1: String = build("luna","mining_rig")
 var luna_due: float = 0.0
 for site in game.construction.sites:
  luna_due = maxf(luna_due,float(site.get("finish_native",0)))
 deliver_steps(luna_due)
 verify(facility(port).get("type") == "spaceport",
  "Lunar ground spaceport completed")
 # Scheduled freight is real: 10 metals Earth->Moon in transit.
 game._toggle_freight_line()
 game._step()
 var freight: Dictionary = game.construction.freight_status()
 verify(game.construction.freight_line().enabled and
  freight.get("location") == "transit",
  "Real regular line dispatches an actual cargo flight")
 verify(int(freight.get("order",{}).get("amount",0)) == 10,
  "Cargo manifest is simulation owned, 10 units")
 choose_planet("luna")
 await focus_and_settle("luna")
 choose_from_globe(port)
 verify(game.colony_panel.page == "logistics" and
  game.colony_panel.logistics_view.visible,
  "Ground port opens ONE shared logistics panel")
 var logistics: String = game.colony_panel.logistics_status.text
 verify(logistics.contains("Регулярная линия: включена") and
  game.colony_panel.ship_rows[0].text.contains("В пути") and
  game.colony_panel.ship_rows[0].text.contains("10") and logistics.contains(
  "Земля") and logistics.contains("Луна"),
  "Port shows line, direction, hold and truck status")
 verify(game.freight_line_buttons.is_ancestor_of(
  game.colony_panel.logistics_view) == false and
  game.colony_panel.logistics_view.is_ancestor_of(
  game.freight_line_buttons),
  "Logistics uses existing regular/manual flight actions")
 await capture("spaceport")
 var delivery: float = float(freight.get("arrival",0))
 deliver_steps(delivery)
 game._toggle_freight_line()
 verify(float(game.construction.colony_inventory("luna").get(
  "supply",{}).get("metals",0)) >= 10,
  "Moon receives resources through a genuine flight")
 var luna_2: String = build("luna","mining_rig")
 verify(luna_1 != luna_2 and not luna_1.is_empty() and
  not luna_2.is_empty(), "Two distinct lunar miners can be built")
 verify(facility(luna_1).get("surface_site",[]) !=
  facility(luna_2).get("surface_site",[]),
  "Lunar duplicate miners use separate surface anchors")
 deliver_steps(float(game.construction.sites.back().get(
  "finish_native",0)))
 choose_from_list(luna_2)
 verify(game.colony_panel.detail_description.text.contains(
  "Выпуска ещё не было"), "Newly built second lunar mine has no fake receipt")
 var lunar_first_due: float = float(actual(luna_2).get("next_native",0))
 deliver_steps(lunar_first_due)
 verify(bool(actual(luna_1).get("last_present",false)) and
  bool(actual(luna_2).get("last_present",false)),
  "Both lunar mining instances eventually produce real batches")
 await focus_and_settle("luna")
 choose_from_globe(luna_1)
 choose_from_globe(luna_2)
 choose_from_list(luna_1)
 var lunar_caption: String = game.colony_panel.detail_title.text
 choose_from_list(luna_2)
 verify(lunar_caption != game.colony_panel.detail_title.text,
  "Lunar built list selects separate facility instances")
 # AC must route to the *existing* construction catalog + actual queue.
 await focus_and_settle("luna")
 choose_from_globe("facility-luna-ac")
 verify(game.browser.visible and game.browser.body_id == "luna" and
  game.browser.queue_panel != null,
  "Lunar AC opens existing construction and queue")
 verify(game.colony_stock_panel.is_visible_in_tree() and
  game.colony_stock_panel.get_parent() == game.browser.dock_layout,
  "The existing warehouse stays visible in construction")
 game._close_browser()
 # Quick entry returns to SAME logistics panel used by port click.
 game._open_colony_logistics()
 verify(game.colony_panel.logistics_view.visible and
  game.colony_panel.ship_rows[0].text.contains("Грузовик"),
  "Quick logistics and port click share an identical panel")

 game._save_game()
 game._load_game()
 verify(bool(actual(luna_1).get("last_present",false)) and
  bool(actual(luna_2).get("last_present",false)),
  "Actual per-facility receipts persist over save and load")
 choose_planet("earth")
 verify(game.colony_panel.selected_facility.is_empty(),
  "Changing planets clears selected Moon enterprise")
 choose_from_list(earth_2)
 verify(game.colony_panel.selected_facility == earth_2 and
  game.colony_panel.detail_title.text.contains("№2"),
  "Earth instance selection remains stable after Moon and save/load")
 print("SOL_FACILITY_CONTROL_RESULT ",JSON.stringify({
  "earth":[earth_1,earth_2],"moon":[luna_1,luna_2],
  "port":port, "earth_receipts":[actual_a.get("last_native"),
  actual_b.get("last_native")], "failures":problems.size()
 }))
 if FileAccess.file_exists(Lab.USER_SAVE):
  DirAccess.remove_absolute(ProjectSettings.globalize_path(Lab.USER_SAVE))
 if problems.is_empty():
  print("SOL_FACILITY_CONTROL_PASS")
  quit(0)
 else:
  print("SOL_FACILITY_CONTROL_FAILURES ", JSON.stringify(problems))
  quit(1)
