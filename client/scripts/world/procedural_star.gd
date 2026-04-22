class_name ProceduralStar
extends Node3D

## A system's sun. Four layers:
##   1. Core sphere — unshaded, high-emission, animated plasma shader.
##      Emission >> 1.0 pushes it past the bloom threshold so it blows
##      out to near-white in the bloom, which reads as "shining".
##   2. Inner glow billboard — additive radial gradient, tight + bright.
##   3. Outer corona billboard — additive radial gradient, wide + soft.
##   4. OmniLight3D — actual scene light so planets get lit.
##
## The glows are camera-facing QuadMesh billboards rather than a 3D
## halo shell: sphere shells show visible polygon banding on their
## fresnel gradient at low subdivisions, whereas a billboard's radial
## gradient is smooth from any angle. Additive blend so they only
## brighten what's behind them; default depth-test so planets in front
## of the star properly occlude the halo.
##
## Star colour drives all four layers so changing one uniform (or
## passing a new tint at setup) flows through.

const CORE_SHADER := "res://shaders/procedural_star.gdshader"
const HALO_SHADER := "res://shaders/procedural_star_halo.gdshader"

const CORE_RADIAL_SEGMENTS := 32
const CORE_RINGS := 16
# Billboard glow sizes (diameter multipliers of the core radius). Inner
# is a tight hot disc; outer is a wide soft corona. Stacking two layers
# additively gives a smooth bright-center → faint-edge falloff with no
# polygon banding, which is what killed the old 3D-shell halo.
const INNER_GLOW_MULT := 3.2
const OUTER_GLOW_MULT := 7.0
const LIGHT_RANGE_MULT := 25.0  # omni light reach vs core radius

var core_radius: float = 0.6
var tint: Color = Color(1.0, 0.95, 0.6)

var _core_mesh: MeshInstance3D
var _light: OmniLight3D
var _core_mat: ShaderMaterial


func setup(radius: float, color: Color, seed_int: int = 0) -> void:
  core_radius = radius
  tint = color
  _build_core()
  _build_glow()
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
  # Push emission hard past bloom threshold — we want the core to blow
  # out to near-white in glow, which is what reads as "shining" vs the
  # old "flat yellow ball" look.
  _core_mat.set_shader_parameter(&"emission_strength", 7.0)
  _core_mat.set_shader_parameter(&"noise_frequency", 3.5)
  _core_mat.set_shader_parameter(&"noise_octaves", 5)
  _core_mat.set_shader_parameter(&"flow_speed", 0.45)
  # Near-zero limb darkening. The old 0.30 value bled too much dimness
  # into the edges, which combined with the banded halo made the star
  # read as "solid disc in fog". Keep a tiny bit so we still sell the
  # sphere shape.
  _core_mat.set_shader_parameter(&"limb_darkening", 0.08)

  _core_mesh = MeshInstance3D.new()
  _core_mesh.name = "Core"
  _core_mesh.mesh = sphere
  _core_mesh.material_override = _core_mat
  add_child(_core_mesh)


func _build_glow() -> void:
  # Inner glow: hot near-white, tight + bright. Steep falloff keeps it
  # from bleeding too far past the star silhouette.
  var inner_col := tint.lerp(Color(1, 1, 0.95), 0.35)
  _spawn_glow_quad(
    "InnerGlow",
    core_radius * INNER_GLOW_MULT,
    inner_col,
    3.0,   # intensity
    2.8,   # falloff — tight
  )
  # Outer corona: full tint, wide, soft. Low intensity so it lingers as
  # a dim aura stretching well past the bright disc.
  _spawn_glow_quad(
    "OuterGlow",
    core_radius * OUTER_GLOW_MULT,
    tint,
    1.1,   # intensity
    3.6,   # falloff — spreads further
  )


func _spawn_glow_quad(
  quad_name: String, radius: float, color: Color,
  intensity: float, falloff: float
) -> void:
  var quad := QuadMesh.new()
  quad.size = Vector2(radius * 2.0, radius * 2.0)

  var mat := ShaderMaterial.new()
  mat.shader = load(HALO_SHADER)
  mat.set_shader_parameter(&"glow_color", color)
  mat.set_shader_parameter(&"glow_intensity", intensity)
  mat.set_shader_parameter(&"glow_falloff", falloff)

  var mi := MeshInstance3D.new()
  mi.name = quad_name
  mi.mesh = quad
  mi.material_override = mat
  add_child(mi)


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
