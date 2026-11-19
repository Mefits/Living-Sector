extends SceneTree
## Scene-level acceptance: real UI presses, lunar stock, all facility click paths,
## loaded warehouse unchanged, and fixed-header geometry at two resolutions.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
var game: Control
var errors: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func _check(value: bool, label: String) -> void:
 if not value:
  errors.append(label)
  push_error("SOL_COLONY_WINDOW: " + label)

func _select(id: String) -> void:
 for body in game.world.get("bodies", []):
  if str(body.get("id", "")) == id:
   game.native_view.body_selected.emit(body)
   return
 _check(false, "Could not select " + id)

func _press_button(root_node: Node, caption: String) -> void:
 for candidate in root_node.find_children("*", "Button", true, false):
  var button: Button = candidate
  if button.text == caption and button.is_visible_in_tree():
   _check(not button.disabled, "Disabled " + caption)
   if not button.disabled:
    button.pressed.emit()
   return
 _check(false, "Missing visible button " + caption)

func _menu(id: int) -> void:
 for node in game.find_children("*", "MenuButton", true, false):
  if node.text == "Игра":
   node.get_popup().id_pressed.emit(id)
   return
 _check(false, "Missing game menu")

func _advance_to(deadline: float) -> void:
 for i in range(250):
  if game.native_time >= deadline:
   return
  game._step()
 _check(false, "In-game day not reached")

func _build(id: String) -> void:
 var controls: Dictionary = game.browser.build_controls.get(id, {})
 _check(not controls.is_empty(), "No catalog row " + id)
 if controls.is_empty():
  return
 var button: Button = controls["button"]
 _check(not button.disabled and button.is_visible_in_tree(),
  "Catalog cannot build " + id)
 if not button.disabled and button.is_visible_in_tree():
  button.pressed.emit()

func _stock(body: String, kind: String) -> float:
 return float(game.construction.colony_inventory(body).get(
  "supply", {}).get(kind, 0))

func _layout(width: int, height: int, context: String) -> void:
 root.size = Vector2i(width, height)
 game.size = Vector2(width, height)
 game._layout_right_side()
 await process_frame
 var side: Rect2 = game.sidebar.get_global_rect()
 var heading: Rect2 = game.colony_panel.heading.get_global_rect()
 var summary: Rect2 = game.colony_panel.summary.get_global_rect()
 var stock: Rect2 = game.colony_panel.metal.get_global_rect()
 var view: Rect2 = game.colony_panel.scroll.get_global_rect()
 var last_controls: Rect2 = game.freight_line_buttons.get_global_rect()
 _check(side.position.x >= 0 and side.end.x <= width + 1.0 and
  side.position.y >= 45.0 and side.end.y <= height + 1.0,
  context + " side within viewport")
 for pair in [{"name": "title", "rect": heading},
     {"name": "summary", "rect": summary},
     {"name": "stock", "rect": stock},
     {"name": "list", "rect": view},
     {"name": "line actions", "rect": last_controls}]:
  var rect: Rect2 = pair["rect"]
  _check(rect.position.y >= 45.0 and rect.end.y <= height + 1.0,
   context + " " + str(pair["name"]) + " vertically visible")
 _check(game.colony_panel.scroll.size.y > 100.0,
  context + " list has usable scroll area")
 _check(game.colony_panel.heading.is_visible_in_tree(),
  context + " title visible")
 for caption in ["Строить", "Склад", "Построено", "Линия"]:
  var found := false
  for node in game.colony_panel.find_children("*", "Button", true, false):
   if node.text != caption:
    continue
   found = true
   var rect: Rect2 = node.get_global_rect()
   _check(node.is_visible_in_tree() and rect.end.x <= width + 1.0
    and rect.end.y <= height + 1.0, context + " action " + caption)
  _check(found, context + " missing action " + caption)
 if OS.get_environment("SOL_CAPTURE_UI") == "1" and DisplayServer.get_name() != "headless":
  await RenderingServer.frame_post_draw
  var image: Image = root.get_texture().get_image()
  if image != null and not image.is_empty():
   var destination := "res://sol-colony-%dx%d.png" % [width, height]
   image.save_png(destination)
   print("SOL_COLONY_SCREENSHOT ", ProjectSettings.globalize_path(destination))
 print("SOL_COLONY_LAYOUT ", JSON.stringify({
  "resolution": "%dx%d" % [width, height],
  "context": context, "side_x": side.position.x,
  "side_width": side.size.x, "header_bottom": heading.end.y,
  "scroll_height": view.size.y, "actions_bottom": last_controls.end.y
 }))

func _run() -> void:
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_COLONY_WINDOW_FAIL: use isolated XDG_DATA_HOME")
  quit(1)
  return
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 _press_button(game.top_bar, "×16")
 _select("luna")
 _check(game.selected == "luna", "selected Luna")
 _press_button(game.colony_panel, "Колонизировать Луну")
 var arrival: float = float(game.construction.expedition.ship.get("arrival", -1))
 _advance_to(arrival)
 _check(game.selected == "luna", "Luna retained selection on landing")
 _check(game.construction.expedition.settlers.get("population_count") == 100,
  "100 lunar colonists")
 _check(_stock("luna", "metals") == 2.0 and
  game.colony_panel.metal.text.contains("2"),
  "two real lunar metals visible without opening catalog")
 _press_button(game.colony_panel, "Строить")
 _check(game.browser.body_id == "luna" and
  game.browser.colony_line.text.contains("металл 2"),
  "Lunar catalog shows actual two metals")
 _build("mining_rig")
 _check(_stock("luna", "metals") == 1.0, "mine debit 1")
 _build("spaceport")
 _check(_stock("luna", "metals") == 0.0 and
  not game.browser.build_controls["spaceport"].card.visible,
  "port debit 1 and unique is hidden")
 _check(game.construction.sites.size() == 2, "two real sites")
 _menu(2)
 _menu(3)
 _check(_stock("luna", "metals") == 0.0 and
  game.construction.sites.size() == 2, "saved+loaded no duplicated cargo")
 _press_button(game.browser, "Колония")
 _advance_to(float(game.construction.sites[0].get("finish_native", 0.0)))
 game._show_selected()
 var expected: Array[String] = ["facility-luna-ac",
  "sol-lab-build-0001", "sol-lab-build-0002"]
 for fid in expected:
  _check(game.colony_panel.built_buttons.has(fid), "built list " + fid)
  if game.colony_panel.built_buttons.has(fid):
   (game.colony_panel.built_buttons[fid] as Button).pressed.emit()
   _check(game.colony_panel.selected_facility == fid and
    game.colony_panel.detail_title.visible, "built list opens " + fid)
 _press_button(game.colony_panel, "Склад")
 _check(game.colony_panel.stock_view.visible and
  game.colony_stock_panel.amount_labels["metals"].text == "0",
  "full warehouse one click")
 _press_button(game.colony_panel, "Построено")
 _press_button(game.colony_panel, "Линия")
 _check(game.freight_line_dialog.visible, "line settings one click")
 game.freight_line_dialog.hide()
 # Zoom to the real globe and click actual rendered facility pins.
 game.native_view.focus_body("luna")
 for i in range(80):
  await process_frame
 var pins: Dictionary = {}
 for pin in game.native_view._facility_pins:
  pins[str(pin["id"])] = pin["position"]
 for fid in expected:
  _check(pins.has(fid), "globe shows clickable pin " + fid)
  if not pins.has(fid):
   continue
  game.native_view._pick(pins[fid])
  _check(game.colony_panel.selected_facility == fid,
   "globe pin selects same card " + fid)
 # Build several enterprises on Earth from its real warehouse.
 _select("earth")
 _press_button(game.colony_panel, "Строить")
 for id in ["mining_rig", "farm", "refinery", "factory", "power_plant"]:
  _build(id)
 _press_button(game.browser, "Колония")
 _check(_stock("earth", "metals") == 995.0,
  "five paid factories debit exactly five metals")
 for i in range(250):
  if game.construction.sites.is_empty():
   break
  game._step()
 _check(game.construction.sites.is_empty(), "Earth facilities completed")
 _select("luna")
 _press_button(game.colony_panel, "Включить линию")
 _check(game.construction.freight_line().enabled, "line enabled")
 # Worst-case content on Earth: five enterprises and enabled trade line.
 _select("earth")
 await _layout(1366, 768, "overview-many-buildings-and-line")
 await _layout(1920, 1080, "overview-many-buildings-and-line")
 _press_button(game.colony_panel, "Строить")
 for dimension in [[1366, 768], [1920, 1080]]:
  root.size = Vector2i(dimension[0], dimension[1])
  game.size = Vector2(dimension[0], dimension[1])
  game._layout_right_side()
  await process_frame
  var browser_rect: Rect2 = game.browser.get_global_rect()
  var title_rect: Rect2 = game.browser.title.get_global_rect()
  var scroll_rect: Rect2 = game.browser.scroll.get_global_rect()
  _check(title_rect.position.y >= 45 and title_rect.end.y <= dimension[1] and
   browser_rect.end.x <= dimension[0] + 1 and scroll_rect.size.y > 120,
   "catalog title/actions within %dx%d" % [dimension[0], dimension[1]])
 if FileAccess.file_exists(Lab.USER_SAVE):
  DirAccess.remove_absolute(ProjectSettings.globalize_path(Lab.USER_SAVE))
 if errors.is_empty():
  print("SOL_COLONY_WINDOW_PASS")
  quit(0)
 else:
  print("SOL_COLONY_WINDOW_FAILURES ", JSON.stringify(errors))
  quit(1)
