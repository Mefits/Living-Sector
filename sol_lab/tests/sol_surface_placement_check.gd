extends SceneTree
## Earth/Moon placement acceptance. Real UI, actual stock/queue, legacy
## checkpoint migration, and actual current planet sprite projection.
const Scene = preload("res://scenes/main.tscn")
const Main = preload("res://scripts/main.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const Sites = preload("res://scripts/view/sol_surface_sites.gd")
var game: Control
var problems: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func check(value: bool, message: String) -> void:
 if not value:
  problems.append(message)
  push_error("SOL_PLACEMENT_FAIL: " + message)

func inventory(body: String) -> float:
 return float(game.construction.colony_inventory(body).get(
  "supply", {}).get("metals", -1))

func find_facility(id: String) -> Dictionary:
 for f in game.world.get("facilities", []):
  if str(f.get("id", "")) == id:
   return f
 return {}

func select_body(body: String) -> void:
 for value in game.world.get("bodies", []):
  if str(value.get("id", "")) == body:
   game.native_view.body_selected.emit(value)
   return
 check(false, "Cannot select "+body)

func advance_to(deadline: float) -> void:
 for tick in range(450):
  if game.native_time >= deadline:
   return
  game._step()
 check(false, "Test clock didn't reach "+str(deadline))

func settle(body: String) -> void:
 game.native_view.focus_body(body)
 for tick in range(75):
  await process_frame

func capture(name: String) -> void:
 if OS.get_environment("SOL_CAPTURE_PLACEMENT") != "1" or (
     DisplayServer.get_name() == "headless"):
  return
 await create_timer(0.25).timeout
 for tick in range(6):
  await process_frame
 await RenderingServer.frame_post_draw
 var screenshot: Image = root.get_texture().get_image()
 check(screenshot != null and not screenshot.is_empty(),
  "Screenshot "+name)
 if screenshot != null and not screenshot.is_empty():
  var path: String = "res://sol-placement-%s-1366x768.png" % name
  var err: Error = screenshot.save_png(path)
  check(err == OK, "Screenshot saved "+name)
  print("SOL_PLACEMENT_SCREENSHOT ",
   ProjectSettings.globalize_path(path))

func start_build(body: String, kind: String) -> void:
 select_body(body)
 if game.browser == null or not game.browser.visible:
  game._open_build()
 var controls: Dictionary = game.browser.build_controls.get(kind, {})
 check(not controls.is_empty(), "Build row "+body+" "+kind)
 if controls.is_empty():
  return
 var button: Button = controls["button"]
 check(not button.disabled and button.visible,
  "Can start site selection for "+kind)
 if button.disabled:
  return
 button.pressed.emit()
 check(game.browser.placement_panel.visible and
  game.native_view._placement_body_id == body and
  game.native_view._placement_building_id == kind,
  "Catalog starts placement without ordering "+kind)

func choose_and_confirm(site_id: String) -> String:
 var slot: Dictionary = Sites.get_site(game.selected, site_id)
 check(not slot.is_empty(), "Valid target slot "+site_id)
 if slot.is_empty():
  return ""
 game.native_view.choose_placement(site_id)
 game.browser.select_placement(site_id)
 check(not game.browser.placement_confirm.disabled,
  "Explicit site confirmation enabled")
 var before: int = game.construction.sites.size()
 game.browser.placement_confirm.pressed.emit()
 check(game.construction.sites.size() == before + 1,
  "Only confirmed site creates a paid order")
 if game.construction.sites.size() != before + 1:
  return ""
 return str(game.construction.sites.back().get("id", ""))

func _run() -> void:
 if FileAccess.file_exists(Main.USER_SAVE) or FileAccess.file_exists(Main.USER_CONFIG):
  push_error("SOL_PLACEMENT_FAIL: use isolated XDG_DATA_HOME")
  quit(1)
  return
 root.size = Vector2i(1366,768)
 Engine.max_fps = 60
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 game._set_speed(16)
 # Validate the hand-authored sites against BOTH real sprites: stable IDs,
 # drawable disc coordinates, screen-scale footprints and free port apron.
 for body in ["earth","luna"]:
  var keys: Dictionary = {}
  var entries: Array = Sites.entries(body)
  check(entries.size() >= 12, "Multiple actual sites on "+body)
  for item in entries:
   var id: String = str(item.get("id", ""))
   check(not id.is_empty() and not keys.has(id),
    "Stable unique site "+body+" "+id)
   keys[id] = true
   check(item.get("types", []) is Array and not item["types"].is_empty(),
    "Site has compatible types")
   var at: Vector2 = Sites.site_position(item)
   if str(item.get("kind","ground")) == "ground":
    check(at.length() <= 0.88,
     "Ground site inside sprite disc "+id)
  for i in range(entries.size()):
   for j in range(i+1,entries.size()):
    if entries[i].get("kind") != "ground" or (
        entries[j].get("kind") != "ground"):
     continue
    check(Sites.site_position(entries[i]).distance_to(
     Sites.site_position(entries[j])) >= 0.19,
     "Building sprites not overlapping between site centres")
  for entry in entries:
   if not entry.has("landing"):
    continue
   for pad_name in ["landing","loading"]:
    var pad: Dictionary = entry[pad_name]
    check(Sites.site_position(pad).length() <= 0.89,
     "Port "+pad_name+" within usable disc")
    for other in entries:
     if str(other.get("kind")) != "ground" or (
         str(other.get("id")) == str(entry.get("id"))):
      continue
     check(Sites.site_position(pad).distance_to(
      Sites.site_position(other)) >= 0.24,
      "Port apron kept free from buildings")
  print("SOL_PLACEMENT_SITES ",body,"=",entries.size())
 for expectation in [
  ["facility-earth-administrative-center","earth-ac-01"],
  ["facility-earth-starter-farm","earth-farm-01"],
  ["facility-earth-spaceport","earth-port-01"]]:
  check(find_facility(str(expectation[0])).get(
   "surface_site_id", "") == expectation[1],
   "New-game starter uses named plot "+str(expectation[0]))

 var first_stock: float = inventory("earth")
 start_build("earth","mining_rig")
 check(inventory("earth") == first_stock and
  game.construction.sites.is_empty(),
  "Selecting a building does not debit inventory")
 await settle("earth")
 check(game.native_view._placement_pins.size() >= 3,
  "Display several free mine plots on the globe")
 var first_marker: Dictionary = game.native_view._placement_pins[0]
 var target_site: String = str(first_marker["id"])
 # Exercise real Godot mouse click, not just a synthetic direct order.
 var pointer := InputEventMouseButton.new()
 pointer.button_index = MOUSE_BUTTON_LEFT
 pointer.position = first_marker["position"]
 pointer.pressed = true
 game.native_view._gui_input(pointer)
 check(game.browser.placement_chosen_id == target_site and
  not game.browser.placement_confirm.disabled,
  "Actual globe click selects the named construction plot")
 await capture("earth-choose")
 game.browser.placement_cancelled.emit()
 check(inventory("earth") == first_stock and
  game.construction.sites.is_empty() and
  game.native_view._placement_body_id.is_empty(),
  "Exiting placement is free and leaves no site reserved")
 start_build("earth", "mining_rig")
 var first_mine: String = choose_and_confirm(target_site)
 check(inventory("earth") == first_stock - 1 and
  str(find_facility(first_mine).get(
  "surface_site_id", "")) == target_site,
  "Confirmed order pays exactly one metal and reserves chosen site")
 check(Sites.reservable("earth", "mining_rig",
  target_site, game.world["facilities"]).is_empty(),
  "Occupied site blocked from further orders")
 var blocked_stock: float = inventory("earth")
 check(not game.construction.order("earth", "mining_rig",
  target_site).get("ok", false) and inventory("earth") == blocked_stock,
  "Attempting to double book a site cannot debit stock")
 game._cancel_build(first_mine)
 check(inventory("earth") == first_stock and
  Sites.reservable("earth", "mining_rig",
  target_site, game.world["facilities"]).has("id"),
  "Cancel returns 100% and releases the plot")
 game._cancel_build(first_mine)
 check(inventory("earth") == first_stock,
  "Repeated cancellation cannot refund twice")
 start_build("earth","mining_rig")
 var first_complete: String = choose_and_confirm(target_site)
 advance_to(float(game.construction.sites.back()["finish_native"]))
 check(find_facility(first_complete).get("type") == "mining_rig" and
  find_facility(first_complete).get("surface_site_id") == target_site,
  "Finished building keeps the same reserved plot")
 start_build("earth","mining_rig")
 var second_slot: String = str(game.native_view._placement_sites[0]["id"])
 check(second_slot != target_site,"Already built plot never reappears")
 var next_mine: String = choose_and_confirm(second_slot)
 check(first_complete != next_mine, "Second mine is distinct")
 var next_finish: float = float(game.construction.sites.back()[
  "finish_native"])
 # Mimic an older checkpoint: real buildings and one unfinished site,
 # persisted coordinates but no modern site IDs.
 var legacy: Dictionary = JSON.parse_string(JSON.stringify(
  game.construction.snapshot()))
 var legacy_stock: float = inventory("earth")
 for facility in legacy["facilities"]:
  if str(facility.get("body","")) == "earth":
   facility.erase("surface_site_id")
   var kind: String = str(facility.get("type", ""))
   if kind == "station":
    kind = "administrative_center"
   elif kind == "construction_site":
    kind = str(facility.get("construction_building_id", ""))
   var earlier: Array = Model.surface_site(kind)
   if earlier.size() == 2:
    facility["surface_site"] = earlier.duplicate()
 for order in legacy["sites"]:
  order.erase("surface_site_id")
 check(game.construction.restore(legacy),
  "Legacy built+pending checkpoint accepted")
 check(inventory("earth") == legacy_stock and
  game.construction.sites.size() == 1 and
  absf(float(game.construction.sites[0]["finish_native"])-
  next_finish) < 0.001,
  "Migration preserves stock, paid order and existing deadline")
 check(not str(find_facility(first_complete).get(
  "surface_site_id", "")).is_empty() and not str(
  find_facility(next_mine).get("surface_site_id", "")).is_empty(),
  "Old completed and pending facilities assigned distinct named sites")
 check(str(find_facility(first_complete).get("surface_site_id")) !=
  str(find_facility(next_mine).get("surface_site_id")),
  "Legacy migration cannot double-occupy a plot")
 check(str(game.construction.sites[0].get(
  "surface_site_id", "")) == str(find_facility(next_mine).get(
  "surface_site_id", "")),
  "Pending site and its world facility share the same canonical ID")
 game._update_native_map()
 game._show_selected()
 game._save_game()
 game._load_game()
 check(game.construction.sites.size() == 1 and
  inventory("earth") == legacy_stock and not str(
  game.construction.sites[0].get("surface_site_id","")).is_empty(),
  "New save reload retains migrated pending site without extra debit")
 var saved_build_id: String = str(game.construction.sites[0]["id"])
 game._cancel_build(saved_build_id)
 check(inventory("earth") == legacy_stock + 1 and
  find_facility(saved_build_id).is_empty(),
  "Refund after migrating an old pending construction works once")
 game._cancel_build(saved_build_id)
 check(inventory("earth") == legacy_stock + 1,
  "Repeated post-migration cancellation is harmless")

 # Actual founding and real lunar orders, not injected stock.
 select_body("luna")
 game._colonize_luna()
 advance_to(float(game.construction.expedition.ship.get("arrival",0)))
 check(game.construction.colony_population("luna") == 100 and
  inventory("luna") == 2.0 and str(find_facility(
  "facility-luna-ac").get("surface_site_id","")) == "luna-ac-01",
  "Real lunar arrival places AC on canonical plot")
 var port: Dictionary = game.construction.order(
  "luna","spaceport","luna-port-01")
 var mine: Dictionary = game.construction.order(
  "luna","mining_rig","luna-mine-01")
 check(port.get("ok",false) and mine.get("ok",false) and
  inventory("luna") == 0.0,
  "Moon spends actual two-metal manifest on selected plots")
 var completion: float = 0.0
 for site in game.construction.sites:
  completion = maxf(completion,float(site["finish_native"]))
 advance_to(completion)
 check(find_facility(str(port.get("id",""))).get(
  "type","") == "spaceport" and find_facility(str(mine.get(
  "id",""))).get("type","") == "mining_rig",
  "Moon port and mine actually constructed")
 var pads: Dictionary = Sites.port_pads("luna",find_facility(
  str(port.get("id",""))))
 check(str(pads.get("landing",{}).get("id","")) == "luna-landing-01" and
  str(pads.get("loading",{}).get("id","")) == "luna-loading-01",
  "Lunar port exposes stable future landing and loading pads")
 # Get more real metal from the scheduled Earth-to-Moon freight.
 game.construction.set_freight_line_enabled(true)
 game._step()
 var cargo: Dictionary = game.construction.freight_status()
 check(cargo.get("location") == "transit",
  "Real shipment starts without granting resources")
 if cargo.get("location") == "transit":
  advance_to(float(cargo.get("arrival",0)))
 game.construction.set_freight_line_enabled(false)
 check(inventory("luna") >= 10.0,
  "Luna receives material through existing cargo simulation")
 for pair in [["refinery","luna-industry-02"],
              ["power_plant","luna-industry-01"],
              ["farm","luna-common-03"],
              ["factory","luna-industry-03"]]:
  var order: Dictionary = game.construction.order(
   "luna",str(pair[0]),str(pair[1]))
  check(order.get("ok",false),
   "Built-up Moon can reserve "+str(pair[1]))
 var last: float = 0.0
 for site in game.construction.sites:
  last = maxf(last,float(site["finish_native"]))
 advance_to(last)
 game._update_native_map()
 select_body("luna")
 game._show_selected()
 await settle("luna")
 check(game.native_view._focused_body_id == "luna",
  "Camera focused on genuinely constructed Moon")
 var drawn_pads: Dictionary = {}
 for site in game.native_view._physical_assets.get("surface", []):
  if site.get("type") == "spaceport" and site.get("body") == "luna":
   drawn_pads = site.get("port_pads", {})
 check(not drawn_pads.is_empty() and
  not drawn_pads.get("landing",{}).is_empty(),
  "Visible lunar port has pad projections from the same catalogue")
 check(game.native_view._facility_pins.size() >= 5,
  "Built lunar structures selectable as independent facilities")
 await capture("luna-built")
 print("SOL_PLACEMENT_RESULT ",JSON.stringify({
  "first":first_complete,"second":next_mine,"port":port.get("id",""),
  "pads":pads,"moon_metal":inventory("luna"),
  "failed":problems.size()
 }))
 if FileAccess.file_exists(Main.USER_SAVE):
  DirAccess.remove_absolute(ProjectSettings.globalize_path(
   Main.USER_SAVE))
 if problems.is_empty():
  print("SOL_PLACEMENT_PASS")
  quit(0)
 else:
  print("SOL_PLACEMENT_FAILURES ",JSON.stringify(problems))
  quit(1)
