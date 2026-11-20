extends SceneTree
## godot --headless --path sol_lab -s res://tests/sol_vector_icons_check.gd
const Icons = preload("res://scripts/view/sol_icon_atlas.gd")
const BUILDINGS: Array[String] = [
 "administrative_center", "mining_complex", "farm", "power_plant",
 "processing_complex", "factory", "spaceport"]
func _initialize() -> void:
 var errors: Array[String] = []
 for px in [20, 32, 64]:
  var path: String = "res://assets/icons/sol_icons_vector_%d.png" % px
  if not ResourceLoader.exists(path, "Texture2D"):
   errors.append("Missing SVG-derived atlas: %s" % path)
  var atlas: Texture2D = Icons._texture(px)
  if atlas == null or atlas.get_width() != px * 5 or (
      atlas.get_height() != px * 4):
   errors.append("Invalid atlas: %d" % px)
 for kind in BUILDINGS:
  var large: Texture2D = Icons._large_building(kind)
  if large == null or large.get_width() != 256:
   errors.append("Missing 256px SVG-derived building: %s" % kind)
 if Icons.icon_texture("energy_cells") != null:
  errors.append("Unexpected energy_cells fallback")
 if Icons.icon_texture("orbital_platform", true) != null:
  errors.append("Unexpected orbital_platform fallback")
 for issue in errors:
  push_error(issue)
 if errors.is_empty():
  print("SOL_VECTOR_ICONS_PASS")
 quit(0 if errors.is_empty() else 1)
