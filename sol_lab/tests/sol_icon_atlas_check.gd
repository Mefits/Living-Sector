extends SceneTree
## Regression check for user-supplied building/resource atlases.
const Icons = preload("res://scripts/view/sol_icon_atlas.gd")
const Glyph = preload("res://scripts/view/colony_building_glyph.gd")
const Stock = preload("res://scripts/view/colony_stock_panel.gd")
const Browser = preload("res://scripts/building_browser.gd")
const Model = preload("res://scripts/sol_building_model.gd")

func _initialize() -> void:
 call_deferred("_run")

func _run() -> void:
 var errors: Array[String] = []
 for px in [20, 32, 64]:
  var atlas: Texture2D = Icons._texture(px)
  if atlas == null or atlas.get_width() != 5 * px or (
      atlas.get_height() != 4 * px):
   errors.append("Missing/invalid %dpx atlas" % px)
 for key in ["metals", "ore", "water", "food", "fuel", "ice",
             "components", "gas", "polymers", "electronics",
             "tools", "medical_supplies", "medical", "luxury"]:
  for px in [20, 32, 64]:
   var icon: Texture2D = Icons.icon_texture(key, false, px)
   if icon == null or icon.get_width() != px or icon.get_height() != px:
    errors.append("Resource icon %s / %dpx" % [key, px])
 for building in Model.BUILDINGS:
  var id: String = str(building["id"])
  var expected: bool = id not in ["orbital_platform", "shipyard"]
  for px in [20, 32, 64]:
   var texture: Texture2D = Icons.icon_texture(id, true, px)
   if (texture != null) != expected:
    errors.append("Building icon %s / %dpx" % [id, px])
 if Icons.icon_texture("energy_cells") != null:
  errors.append("Energy cells must not be mislabeled as electronics")
 if Icons.icon_texture("rare_ore") != null:
  errors.append("No invented rare ore icon")
 if Icons.icon_texture("orbital_platform", true) != null:
  errors.append("No invented orbital platform sprite")
 var glyph := Glyph.new()
 glyph.kind = "mining_rig"
 root.add_child(glyph)
 var panel := Stock.new()
 root.add_child(panel)
 panel.show_inventory("Луна", {"present":true,
  "supply":{"metals":2, "ore":10, "energy_cells":0}})
 var resource_glyphs: int = 0
 for child in panel.find_children("*", "TextureRect", true, false):
  if child.texture != null:
   resource_glyphs += 1
 if resource_glyphs != 2:
  errors.append("Warehouse must show two available resource icons, no unrelated fallback")
 if not panel.amount_labels.has("metals") or (
     panel.amount_labels["metals"].text != "2"):
  errors.append("Resource sprites must not alter actual market amount")
 var browser := Browser.new()
 root.add_child(browser)
 # Nine catalog icons are still rendered through the same Glyph lookup.
 if Icons.BUILDING_IDS.get("mining_rig", -1) != (
     Icons.BUILDING_IDS.get("mining_complex", -1)):
  errors.append("mining_rig mapping mismatch")
 if Icons.BUILDING_IDS.get("refinery", -1) != (
     Icons.BUILDING_IDS.get("processing_complex", -1)):
  errors.append("refinery mapping mismatch")
 print("SOL_ICON_ATLAS_RESULT ", JSON.stringify({
  "sprite_sizes":[20,32,64],"resource_keys":Icons.RESOURCE_IDS.size(),
  "building_keys":Icons.BUILDING_IDS.size(),
  "warehouse_sprite_rows":resource_glyphs,
  "errors":errors.size()
 }))
 if errors.is_empty():
  print("SOL_ICON_ATLAS_PASS")
  quit(0)
 else:
  for error in errors:
   push_error("SOL_ICON_ATLAS_FAIL: " + error)
  quit(1)
