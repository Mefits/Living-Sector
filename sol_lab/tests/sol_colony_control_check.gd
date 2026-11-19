extends SceneTree
## Real Sol Lab UI acceptance: manual logistics, build cancellation,
## saved refunds, shared shipyard platform, double-click focus and Space.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Model = preload("res://scripts/sol_building_model.gd")
var game: Control
var failures: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func check(ok: bool, label: String) -> void:
 if not ok:
  failures.append(label)
  push_error("SOL_COLONY_CONTROL_FAIL: " + label)

func find_button(root_node: Node, value: String) -> Button:
 for node in root_node.find_children("*", "Button", true, false):
  if node.text == value:
   return node
 return null

func select(id: String) -> void:
 for row in game.world.get("bodies", []):
  if str(row.get("id", "")) == id:
   game.native_view.body_selected.emit(row)
   return
 check(false, "missing body " + id)

func stock(id: String) -> float:
 return float(game.construction.colony_inventory(id).get(
  "supply",{}).get("metals",0))

func click_build(id: String) -> String:
 var controls: Dictionary = game.browser.build_controls.get(id, {})
 check(not controls.is_empty(), "catalog row exists "+id)
 if controls.is_empty():
  return ""
 var button: Button = controls["button"]
 check(not button.disabled, "catalog order enabled "+id)
 if button.disabled:
  return ""
 button.pressed.emit()
 check(not game.construction.sites.is_empty(), "UI created actual site")
 return str(game.construction.sites.back().get("id", ""))

func run() -> void:
 pass

func _run() -> void:
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_COLONY_CONTROL_FAIL: run with isolated XDG_DATA_HOME")
  quit(1)
  return
 Engine.max_fps = 60
 root.size = Vector2i(1366,768)
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 check(game.freight_button != null and not game.freight_button.visible,
  "no one-off delivery button on main planet card")
 check(find_button(game.colony_panel,"Разовый рейс") != null,
  "manual flight action beside scheduled line")
 var old_metals: float = stock("earth")
 select("earth")
 game._open_build()
 await process_frame
 check(absf(game.browser.size.x - game.sidebar.size.x) < 2,
  "construction window matches colony width 1366")
 for item in Model.BUILDINGS:
  var id: String = str(item["id"])
  var row: Dictionary = game.browser.build_controls.get(id,{})
  if row.is_empty() or not row["card"].visible:
   continue
  check(str(row["title"].text) == str(item["name"]),
   "full building title "+id)
  check(str(row["button"].text) != "" and row["card"].size.x <=
   game.browser.size.x, "order button inside dock "+id)
 var refinery_id: String = click_build("refinery")
 check(stock("earth") == old_metals - 1,
  "building debits once")
 var site: Dictionary = game.construction.sites.back()
 check(site.get("paid_resources",{}).get("metals") == 1,
  "site remembers actual paid metal")
 for i in range(45):
  game._step()
 check(game.native_time < float(site["finish_native"]),
  "mid-build really before completion")
 game._save_game()
 game._load_game()
 game._refresh_construction_ui()
 var queued: Dictionary = game.browser.queue_rows.get(refinery_id,{})
 check(not queued.is_empty(), "restored build in queue UI")
 if not queued.is_empty():
  var button: Button = queued["cancel"]
  check(button != null and button.text == "Отменить",
   "queue has cancel action")
  button.pressed.emit()
 check(stock("earth") == old_metals,
  "100% refunded to original Earth warehouse")
 check(game.construction.sites.is_empty(),
  "cancel removed site after load")
 check(not game.world["facilities"].any(
  func(f): return str(f.get("id","")) == refinery_id),
  "cancel removed actual construction facility")
 var second: Dictionary = game.construction.cancel_order(refinery_id)
 check(not bool(second.get("ok",false)) and stock("earth") == old_metals,
  "double-click cannot refund twice")
 var mine_id: String = click_build("mining_rig")
 check(not mine_id.is_empty() and stock("earth") == old_metals-1,
  "next construction can proceed normally")
 game._open_manual_freight()
 check(game.manual_freight_dialog.visible,
  "one-off flight opens editable logistics form")
 check(game.manual_preview.text.contains("Земля") and
  game.manual_preview.text.contains("Луна") and
  game.manual_preview.text.contains("10"),
  "shows route, cargo type and quantity before departure")
 check(game.manual_freight_dialog.get_ok_button().disabled,
  "no moon port yet blocks manual flight")
 game.manual_freight_dialog.hide()

 # Advance to finish; canceled refinery must never reappear.
 var finish: float = float(game.construction.sites[0]["finish_native"])
 for i in range(400):
  if game.native_time >= finish:
   break
  game._step()
 check(game.construction.sites.is_empty(),
  "the following mine completed")
 check(not game.world["facilities"].any(
  func(f): return str(f.get("id","")) == refinery_id),
  "canceled refinery does not materialize later")
 check(game.world["facilities"].any(
  func(f): return str(f.get("id","")) == mine_id and
   str(f.get("type","")) == "mining_rig"),
  "next building completed")

 # Reproduce duplicate shipyard station: separate game facility IDs,
 # but exactly ONE drawn orbital hull with a clickable module.
 var platform: Dictionary = game.construction.order("earth","orbital_platform")
 var yard: Dictionary = game.construction.order("earth","shipyard")
 check(bool(platform.get("ok",false)) and bool(yard.get("ok",false)),
  "two separately paid orbital facilities")
 var platform_id: String = str(platform.get("id",""))
 var yard_id: String = str(yard.get("id",""))
 var due: float = float(game.construction.sites.back()["finish_native"])
 for i in range(400):
  if game.native_time >= due:
   break
  game._step()
 check(game.world["facilities"].any(
  func(f): return f.get("id") == platform_id and
   f.get("type") == "orbital_platform") and
  game.world["facilities"].any(
  func(f): return f.get("id") == yard_id and
   f.get("type") == "shipyard"),
  "platform and shipyard retain separate saved simulation identities")
 game.native_view.focus_body("earth")
 for i in range(55):
  await process_frame
 var origin: Dictionary = {}
 var other: Dictionary = {}
 for pin in game.native_view._facility_pins:
  if str(pin.get("id","")) == platform_id:
   origin = pin
  if str(pin.get("id","")) == yard_id:
   other = pin
 check(not origin.is_empty() and not other.is_empty(),
  "hull and module both clickable")
 if not origin.is_empty() and not other.is_empty():
  var distance: float = (origin["position"] as Vector2).distance_to(
   other["position"])
  check(distance > 2 and distance < 38,
   "module co-located next to parent station not second orbiting hull")
  game.native_view._pick(other["position"])
  check(game.colony_panel.selected_facility == yard_id,
   "click selects actual shipyard module")
  game.native_view._pick(origin["position"])
  check(game.colony_panel.selected_facility == platform_id,
   "click selects parent orbital platform")

 # Direct double click uses the existing body follow routine.
 game.native_view.reset_view()
 for i in range(30):
  await process_frame
 var earth_pin: Dictionary = {}
 for pin in game.native_view._body_pins:
  if str(pin["body"].get("id","")) == "earth":
   earth_pin = pin
 check(not earth_pin.is_empty(), "Earth clickable on map")
 if not earth_pin.is_empty():
  var click := InputEventMouseButton.new()
  click.button_index = MOUSE_BUTTON_LEFT
  click.pressed = true
  click.double_click = true
  click.position = earth_pin["position"]
  game.native_view._gui_input(click)
  check(game.native_view._focused_body_id == "earth",
   "double click immediately locks Earth tracking")
 for i in range(65):
  await process_frame
 var moon_pin: Dictionary = {}
 for pin in game.native_view._body_pins:
  if str(pin["body"].get("id","")) == "luna":
   moon_pin = pin
 check(not moon_pin.is_empty(), "Moon clickable while tracking Earth")
 if not moon_pin.is_empty():
  var click_moon := InputEventMouseButton.new()
  click_moon.button_index = MOUSE_BUTTON_LEFT
  click_moon.pressed = true
  click_moon.double_click = true
  click_moon.position = moon_pin["position"]
  game.native_view._gui_input(click_moon)
  check(game.native_view._focused_body_id == "luna",
   "double click switches focus from Earth to Moon")
 for i in range(65):
  await process_frame
 if game.native_view._focused_body_id == "luna":
  var midpoint: Vector2 = game.native_view._body_position(
   game.native_view._body_by_id("luna"),
   game.native_view._orbit_scale())
  check(midpoint.distance_to(game.native_view.size*0.5) < 20,
   "moving Moon stays centered")

 # Space is global, handles key echo and cannot retrigger focused UI buttons.
 game._set_speed(16)
 game.paused = false
 game.visual_clock.set_paused(false)
 game.pause_button.grab_focus()
 var metal_before_key: float = stock("earth")
 var orders_before_key: int = game.construction.sites.size()
 var space := InputEventKey.new()
 space.keycode = KEY_SPACE
 space.pressed = true
 game._input(space)
 check(game.paused and game.speed == 16, "Space pauses at x16")
 space.echo = true
 game._input(space)
 check(game.paused, "auto-repeat Space ignored")
 space.echo = false
 game._input(space)
 check(not game.paused and game.speed == 16,
  "Space resumes original x16 speed")
 check(stock("earth") == metal_before_key and
  game.construction.sites.size() == orders_before_key,
  "Space does not repeat the last UI command")

 game._pause()
 game._close_browser()
 await process_frame
 for dimension in [[1366,768],[1920,1080]]:
  root.size = Vector2i(dimension[0],dimension[1])
  await process_frame
  await process_frame
  game._layout_right_side()
  game._open_build()
  await process_frame
  check(absf(game.browser.size.x-game.sidebar.size.x) < 2,
   "catalog same width at %dx%d" % [dimension[0],dimension[1]])
  check(game.browser.scroll.size.y > 120,
   "catalog list scroll fits %dx%d" % [dimension[0],dimension[1]])
  for id in ["administrative_center","mining_rig","spaceport"]:
   var row: Dictionary = game.browser.build_controls.get(id,{})
   if row.is_empty() or not row["card"].visible:
    continue
   check((row["button"] as Button).get_global_rect().end.x <=
    game.size.x+1, "visible action within window "+id)
  game._close_browser()

 if FileAccess.file_exists(Lab.USER_SAVE):
  DirAccess.remove_absolute(ProjectSettings.globalize_path(Lab.USER_SAVE))
 print("SOL_COLONY_CONTROL_RESULT ", JSON.stringify({
  "refund":old_metals,
  "yard":yard_id,
  "platform":platform_id,
  "failures":failures.size()
 }))
 if failures.is_empty():
  print("SOL_COLONY_CONTROL_PASS")
  quit(0)
 else:
  print("SOL_COLONY_CONTROL_FAILURES ",JSON.stringify(failures))
  quit(1)
