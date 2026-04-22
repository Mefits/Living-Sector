class_name ProceduralStar
extends Node3D

## A system's sun. Three layers:
##   1. Core sphere — unshaded, high-emission, animated plasma shader.
##      Emission > 1.0 pushes it past the bloom threshold so it blooms
##      against the black sky.
##   2. Halo shell — additive, fresnel-on-limb shader. Bigger sphere
##      that draws the soft ring glow around the star's silhouette.
##   3. OmniLight3D — actual scene light so planets get lit.
##
## Star colour drives all three layers so changing one uniform (or
## passing a new tint at setup) flows through.

const CORE_SHADER := "res://shaders/procedural_star.gdshader"
const HALO_SHADER := "res://shaders/procedural_star_halo.gdshader"

const CORE_RADIAL_SEGMENTS := 32
const CORE_RINGS := 16
const HALO_RADIUS_MULT := 2.6   # halo shell vs core radius
const LIGHT_RANGE_MULT := 25.0  # omni light reach vs core radius

var core_radius: float = 0.6
var tint: Color = Color(1.0, 0.95, 0.6)

var _core_mesh: MeshInstance3D
var _halo_mesh: MeshInstance3D
var _light: OmniLight3D
var _core_mat: ShaderMaterial
var _halo_mat: ShaderMaterial


func setup(radius: float, color: Color, seed_int: int = 0) -> void:
  core_radius = radius
  tint = color
  _build_core()
  _build_halo()
  _build_light()
  _apply_seed(seed_int)


func _build_core() -> void:
  var sphere := SphereMesh.new()
  sphere.radius = core_radius
  sphere.height = core_radius * 2.0
  sphere.radial_segments = CORE_RADIAL_SEGMENTS
  sphere.rings = CORE_RINGS

  _core_mat = ShaderMaterial.new()
  _core_mat.shader = load(CORE_SHADER)
  # Colour ramp derived from the tint — core pushes toward white, mid is
  # the tint as-given, edge cools toward orange/red so the plasma has
  # visible temperature variation even at a single-colour star.
  var core_col := tint.lerp(Color(1, 1, 1), 0.55)
  var edge_col := tint.lerp(Color(1.0, 0.30, 0.08), 0.50)
  _core_mat.set_shader_parameter(&"star_color_core", core_col)
  _core_mat.set_shader_parameter(&"star_color_mid", tint)
  _core_mat.set_shader_parameter(&"star_color_edge", edge_col)
  _core_mat.set_shader_parameter(&"emission_strength", 4.5)
  _core_mat.set_shader_parameter(&"noise_frequency", 2.5)
  _core_mat.set_shader_parameter(&"noise_octaves", 4)
  _core_mat.set_shader_parameter(&"flow_speed", 0.35)
  _core_mat.set_shader_parameter(&"limb_darkening", 0.30)

  _core_mesh = MeshInstance3D.new()
  _core_mesh.name = "Core"
  _core_mesh.mesh = sphere
  _core_mesh.material_override = _core_mat
  add_child(_core_mesh)


func _build_halo() -> void:
  var sphere := SphereMesh.new()
  var r := core_radius * HALO_RADIUS_MULT
  sphere.radius = r
  sphere.height = r * 2.0
  sphere.radial_segments = 32
  sphere.rings = 16

  _halo_mat = ShaderMaterial.new()
  _halo_mat.shader = load(HALO_SHADER)
  _halo_mat.set_shader_parameter(&"halo_color", tint)
  _halo_mat.set_shader_parameter(&"halo_intensity", 2.2)
  _halo_mat.set_shader_parameter(&"halo_power", 2.2)
  _halo_mat.set_shader_parameter(&"halo_floor", 0.04)

  _halo_mesh = MeshInstance3D.new()
  _halo_mesh.name = "Halo"
  _halo_mesh.mesh = sphere
  _halo_mesh.material_override = _halo_mat
  add_child(_halo_mesh)


func _build_light() -> void:
  _light = OmniLight3D.new()
  _light.name = "StarLight"
  _light.light_color = tint
  _light.light_energy = 2.5
  _light.omni_range = core_radius * LIGHT_RANGE_MULT
  _light.omni_attenuation = 1.3
  add_child(_light)


func _apply_seed(seed_int: int) -> void:
  if not _core_mat:
    return
  var rng := RandomNumberGenerator.new()
  rng.seed = seed_int
  var off := Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  )
  _core_mat.set_shader_parameter(&"seed_offset", off)
