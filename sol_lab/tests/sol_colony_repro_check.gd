extends SceneTree
## Pre-change UI reproduction, with real button events and real save/load.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
var game: Control
var problems: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func _assert(value: bool, description: String) -> void:
 if not value:
  problems.append(description)
  push_error("SOL_COLONY_REPRO: " + description)

func _press(button: Button) -> void:
 _assert(button != null and not button.disabled, "Button must be enabled")
 if button != null and not button.disabled:
  button.pressed.emit()

func _select(body_id: String) -> void:
 for body in game.world.get("bodies", []):
  if str(body.get("id", "")) == body_id:
   game.native_view.body_selected.emit(body)
   return
 _assert(false, "Cannot select body " + body_id)

func _stock() -> float:
 return float(game.construction.colony_inventory("luna").get("supply", {}).get("metals", -100))

func _run() -> void:
 # This test is deliberately run with an isolated XDG_DATA_HOME.
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_COLONY_REPRO_FAIL: user directory not isolated")
  quit(1)
  return
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 _press(game.pause_button)
 _select("luna")
 _assert(game.selected == "luna", "selected body before landing")
 _press(game.colony_button)
 var arrival: float = float(game.construction.expedition.ship.get("arrival", -1))
 for tick in range(200):
  if game.native_time >= arrival:
   break
  game._step()
 _assert(game.native_time >= arrival, "landing arrived")
 _assert(game.selected == "luna", "selected Luna after landing")
 _assert(int(game.construction.expedition.settlers.get("population_count", -1)) == 100, "population 100")
 _assert(_stock() == 2.0, "real lunar warehouse 2 metals")
 _assert(game.colony_stock_panel.visible, "stock panel exists for lunar colony")
 _assert(game.colony_panel.metal.text.contains("2"), "overview metal count visible")
 _assert(str(game.colony_stock_panel.amount_labels.get("metals", Label.new()).text) == "2",
  "Lunar display shows 2 metals")
 var build_button: Button = null
 for button in game.colony_panel.find_children("*", "Button", true, false):
  if button.text == "Строить":
   build_button = button
   break
 _press(build_button)
 _assert(game.browser.body_id == "luna", "catalog is on Luna")
 _assert(not game.browser.build_controls["mining_rig"].button.disabled, "mine button enabled")
 _assert(not game.browser.build_controls["administrative_center"].card.visible, "AC hidden from catalog")
 _assert(not game.browser.build_controls["spaceport"].button.disabled, "spaceport button enabled")
 print("SOL_COLONY_REPRO_LAND ", JSON.stringify({
  "selected": game.selected,
  "residents": game.construction.expedition.settlers.get("population_count"),
  "warehouse_metals": _stock(),
  "panel_metals": game.colony_stock_panel.amount_labels["metals"].text,
  "panel_visible_when_build": game.colony_stock_panel.is_visible_in_tree(),
  "catalog_summary": game.browser.colony_line.text,
  "catalog_body": game.browser.body_id,
  "mine_enabled": not game.browser.build_controls["mining_rig"].button.disabled,
  "port_enabled": not game.browser.build_controls["spaceport"].button.disabled
 }))
 _press(game.browser.build_controls["mining_rig"].button)
 _assert(_stock() == 2.0, "starting placement is free")
 var mine_site: String = str(game.native_view._placement_sites[0]["id"])
 game.native_view.choose_placement(mine_site)
 game.browser.select_placement(mine_site)
 _press(game.browser.placement_confirm)
 _assert(_stock() == 1.0, "mine subtracts exactly one lunar metal")
 _press(game.browser.build_controls["spaceport"].button)
 var port_site: String = str(game.native_view._placement_sites[0]["id"])
 game.native_view.choose_placement(port_site)
 game.browser.select_placement(port_site)
 _press(game.browser.placement_confirm)
 _assert(_stock() == 0.0, "spaceport subtracts exactly one lunar metal")
 _assert(game.construction.sites.size() == 2, "both lunar sites pending")
 game._save_game()
 var saved: Dictionary = game.construction.snapshot()
 game._load_game()
 _assert(game.message_line.text.begins_with("Игра загружена"), "load accepted")
 _assert(_stock() == 0.0, "loading doesn't grant metal")
 _assert(game.construction.sites.size() == 2, "load keeps two sites")
 _assert(game.browser.colony_line.text.contains("металл 0"),
  "catalog retains warehouse balance after load")
 print("SOL_COLONY_REPRO_AFTER_ORDERS ", JSON.stringify({
  "selected": game.selected,
  "warehouse_metals": _stock(),
  "sites": game.construction.sites.size(),
  "loaded_sites": game.construction.sites.size(),
  "version": saved.version
 }))
 if FileAccess.file_exists(Lab.USER_SAVE):
  DirAccess.remove_absolute(ProjectSettings.globalize_path(Lab.USER_SAVE))
 if problems.is_empty():
  print("SOL_COLONY_REPRO_PASS")
  quit(0)
 else:
  print("SOL_COLONY_REPRO_FAILURES ", JSON.stringify(problems))
  quit(1)
