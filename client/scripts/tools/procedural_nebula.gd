@tool
extends Node3D
class_name ProceduralNebula

## Volumetric-looking nebula built from a sphere mesh + additive noise
## shader. Deterministic from `nebula_seed` — same seed + same params =
## same cloud, so the server can eventually ship `(seed, position,
## size, palette)` per nebula and the client rebuilds identically.
##
## Rendering is cheap: one mesh, one shader, additive blend. Can
## instance hundreds without breaking a sweat. Non-uniform `scale`
## stretches the cloud for pill-shaped or sheet-like nebulas.
##
## Scope: a single cloud. A "nebula field" later would be a MultiMesh
## of these with varied scales/rotations — same trick we used for
## asteroid fields.

const SHADER_PATH := "res://shaders/procedural_nebula.gdshader"

# ---- Geometry -------------------------------------------------------------
@export_range(0.2, 50.0, 0.05) var radius: float = 3.0:
  set(v): radius = v; _apply_geometry()
@export var shape_scale: Vector3 = Vector3(1.0, 0.6, 1.0):
  set(v): shape_scale = v; _apply_geometry()
@export_range(8, 48, 1) var mesh_segments: int = 24:
  set(v): mesh_segments = v; _apply_geometry()

# ---- Seed -----------------------------------------------------------------
@export var nebula_seed: int = 1234:
  set(v): nebula_seed = v; _apply_seed()

# ---- Palette --------------------------------------------------------------
@export_group("Palette")
@export var primary_color: Color = Color(0.80, 0.35, 0.95):
  set(v): primary_color = v; _set_uniform(&"primary_color", v)
@export var secondary_color: Color = Color(0.25, 0.60, 1.00):
  set(v): secondary_color = v; _set_uniform(&"secondary_color", v)
@export_range(0.0, 1.0, 0.01) var color_mix_shift: float = 0.5:
  set(v): color_mix_shift = v; _set_uniform(&"color_mix_shift", v)
@export_range(0.05, 0.5, 0.01) var color_mix_band: float = 0.22:
  set(v): color_mix_band = v; _set_uniform(&"color_mix_band", v)

# ---- Shape / noise --------------------------------------------------------
@export_group("Noise")
@export_range(0.0, 3.0, 0.01) var density: float = 1.0:
  set(v): density = v; _set_uniform(&"density", v)
@export_range(0.0, 6.0, 0.01) var brightness: float = 1.8:
  set(v): brightness = v; _set_uniform(&"brightness", v)
@export_range(0.1, 8.0, 0.01) var noise_frequency: float = 1.6:
  set(v): noise_frequency = v; _set_uniform(&"noise_frequency", v)
@export_range(1, 6, 1) var noise_octaves: int = 4:
  set(v): noise_octaves = v; _set_uniform(&"noise_octaves", v)
@export_range(0.0, 2.0, 0.01) var noise_warp: float = 0.75:
  set(v): noise_warp = v; _set_uniform(&"noise_warp", v)
@export_range(0.0, 2.0, 0.01) var wisp_strength: float = 0.9:
  set(v): wisp_strength = v; _set_uniform(&"wisp_strength", v)
@export_range(0.3, 8.0, 0.01) var radial_falloff: float = 2.5:
  set(v): radial_falloff = v; _set_uniform(&"radial_falloff", v)
@export_range(0.0, 0.8, 0.01) var density_threshold: float = 0.1:
  set(v): density_threshold = v; _set_uniform(&"density_threshold", v)

# ---- Rotation -------------------------------------------------------------
# Slow tumble reads as "this cloud is real, volumetric matter"
# rather than a static decal. Per-axis so nebulas rotate off-axis.
@export var tumble: Vector3 = Vector3(0.0, 0.01, 0.005)

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _ready_done: bool = false


func _ready() -> void:
  _build()
  _ready_done = true
  _apply_all()


func _process(delta: float) -> void:
  if Engine.is_editor_hint():
    return
  if _mesh_instance and (
    tumble.x != 0.0 or tumble.y != 0.0 or tumble.z != 0.0
  ):
    _mesh_instance.rotate_x(tumble.x * delta)
    _mesh_instance.rotate_y(tumble.y * delta)
    _mesh_instance.rotate_z(tumble.z * delta)


func _build() -> void:
  _mesh_instance = MeshInstance3D.new()
  _mesh_instance.name = "NebulaMesh"
  add_child(_mesh_instance)
  _material = ShaderMaterial.new()
  _material.shader = load(SHADER_PATH)
  _mesh_instance.material_override = _material
  _apply_geometry()


func _apply_geometry() -> void:
  if not _mesh_instance:
    return
  var sphere := SphereMesh.new()
  sphere.radius = radius
  sphere.height = radius * 2.0
  sphere.radial_segments = mesh_segments
  sphere.rings = max(int(mesh_segments * 0.6), 4)
  _mesh_instance.mesh = sphere
  # Non-uniform scale applied on the mesh so the shader's `v_local_pos`
  # — which drives radial falloff — stays in sphere-space. Without this
  # shape_scale would warp the noise too.
  _mesh_instance.scale = shape_scale


func _set_uniform(name: StringName, value: Variant) -> void:
  if not _material:
    return
  _material.set_shader_parameter(name, value)


func _apply_seed() -> void:
  var rng := RandomNumberGenerator.new()
  rng.seed = nebula_seed
  _set_uniform(&"seed_offset", Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  ))


func _apply_all() -> void:
  _set_uniform(&"primary_color", primary_color)
  _set_uniform(&"secondary_color", secondary_color)
  _set_uniform(&"color_mix_shift", color_mix_shift)
  _set_uniform(&"color_mix_band", color_mix_band)
  _set_uniform(&"density", density)
  _set_uniform(&"brightness", brightness)
  _set_uniform(&"noise_frequency", noise_frequency)
  _set_uniform(&"noise_octaves", noise_octaves)
  _set_uniform(&"noise_warp", noise_warp)
  _set_uniform(&"wisp_strength", wisp_strength)
  _set_uniform(&"radial_falloff", radial_falloff)
  _set_uniform(&"density_threshold", density_threshold)
  _apply_seed()


func to_config() -> Dictionary:
  return {
    "nebula_seed": nebula_seed,
    "radius": radius,
    "shape_scale": [shape_scale.x, shape_scale.y, shape_scale.z],
    "primary_color": primary_color.to_html(false),
    "secondary_color": secondary_color.to_html(false),
    "color_mix_shift": color_mix_shift,
    "color_mix_band": color_mix_band,
    "density": density,
    "brightness": brightness,
    "noise_frequency": noise_frequency,
    "noise_octaves": noise_octaves,
    "noise_warp": noise_warp,
    "wisp_strength": wisp_strength,
    "radial_falloff": radial_falloff,
    "density_threshold": density_threshold,
  }
