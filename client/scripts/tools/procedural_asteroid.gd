@tool
extends Node3D
class_name ProceduralAsteroid

## Low-poly procedural asteroid. Irregular shape comes from per-vertex
## displacement of a UV sphere along its normal, amount driven by 3D fbm.
## Faces use flat shading (normals per-face) for the faceted look.
##
## Shares the planet shader (`res://shaders/procedural_planet.gdshader`)
## for surface coloring — saves a whole second shader. Features the
## shader has but rocks don't use (sea, poles, bands, emission) are
## zeroed out in `_apply_all`. Planet-specific `seed_offset` drives the
## color noise pattern while our local `_deform_offset` drives the
## geometry bumps; both derived from `asteroid_seed` so rocks are
## deterministic across runs.
##
## Scope: a single rock. Asteroid-field scattering will reuse this node
## later via `MultiMeshInstance3D` with a pool of pre-baked meshes.

const SHADER_PATH := "res://shaders/procedural_planet.gdshader"

# ---- Geometry -------------------------------------------------------------
@export_range(6, 32, 1) var radial_segments: int = 16:
  set(v): radial_segments = v; _rebuild_mesh()
@export_range(4, 16, 1) var rings: int = 10:
  set(v): rings = v; _rebuild_mesh()
@export_range(0.1, 5.0, 0.01) var base_radius: float = 1.0:
  set(v): base_radius = v; _rebuild_mesh()
@export_range(0.0, 0.8, 0.01) var deformation: float = 0.35:
  set(v): deformation = v; _rebuild_mesh()
@export_range(0.3, 8.0, 0.01) var deform_frequency: float = 1.8:
  set(v): deform_frequency = v; _rebuild_mesh()
@export_range(1, 5, 1) var deform_octaves: int = 3:
  set(v): deform_octaves = v; _rebuild_mesh()
@export var squash: Vector3 = Vector3.ONE:
  set(v): squash = v; _rebuild_mesh()

# ---- Seed -----------------------------------------------------------------
@export var asteroid_seed: int = 42:
  set(v):
    asteroid_seed = v
    _rebuild_mesh()
    _apply_color_seed()

# ---- Palette --------------------------------------------------------------
@export_group("Palette")
@export var color_low: Color = Color(0.22, 0.19, 0.16):
  set(v): color_low = v; _set_uniform(&"color_low", v)
@export var color_mid: Color = Color(0.45, 0.38, 0.32):
  set(v): color_mid = v; _set_uniform(&"color_mid", v)
@export var color_high: Color = Color(0.65, 0.58, 0.50):
  set(v): color_high = v; _set_uniform(&"color_high", v)

# ---- Surface noise --------------------------------------------------------
@export_group("Surface")
@export_range(0.1, 12.0, 0.01) var noise_frequency: float = 3.8:
  set(v): noise_frequency = v; _set_uniform(&"noise_frequency", v)
@export_range(1, 6, 1) var noise_octaves: int = 4:
  set(v): noise_octaves = v; _set_uniform(&"noise_octaves", v)
@export_range(0.0, 2.0, 0.01) var noise_warp: float = 0.6:
  set(v): noise_warp = v; _set_uniform(&"noise_warp", v)
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.95:
  set(v): roughness = v; _set_uniform(&"roughness_val", v)
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0:
  set(v): metallic = v; _set_uniform(&"metallic_val", v)

# ---- Tumble ---------------------------------------------------------------
# Per-axis angular velocity (radians/sec). Independent axes so rocks
# really tumble rather than spinning on one axis like planets.
@export var tumble: Vector3 = Vector3(0.05, 0.10, 0.03)

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
  if _mesh_instance:
    _mesh_instance.rotate_x(tumble.x * delta)
    _mesh_instance.rotate_y(tumble.y * delta)
    _mesh_instance.rotate_z(tumble.z * delta)


func _build() -> void:
  _mesh_instance = MeshInstance3D.new()
  _mesh_instance.name = "RockMesh"
  add_child(_mesh_instance)
  _material = ShaderMaterial.new()
  _material.shader = load(SHADER_PATH)
  _mesh_instance.material_override = _material
  _rebuild_mesh()


# ---------------------------------------------------------------------------
# Mesh generation
# ---------------------------------------------------------------------------

func _rebuild_mesh() -> void:
  if not _mesh_instance:
    return
  # Deform offset is derived inside build_mesh from the seed — single
  # source of truth, no instance-side copy to keep in sync.
  _mesh_instance.mesh = _build_rock_mesh()


func _build_rock_mesh() -> ArrayMesh:
  ## Instance-method delegate around the static builder — same output,
  ## just threads the instance's current properties through.
  return ProceduralAsteroid.build_mesh(
    asteroid_seed,
    radial_segments, rings,
    base_radius,
    deformation, deform_frequency, deform_octaves,
    squash,
  )


# ---------------------------------------------------------------------------
# Static builders — used both by the Node3D (single rock) path and by
# AsteroidField (scatter fields). Keeping these stateless means a field
# can generate a pool of meshes without constructing tree-resident nodes.
# ---------------------------------------------------------------------------

static func build_mesh(
  seed_int: int,
  radial_segments_n: int, rings_n: int,
  base_radius_f: float,
  deformation_f: float, deform_frequency_f: float, deform_octaves_n: int,
  squash_v: Vector3,
) -> ArrayMesh:
  ## UV sphere with per-vertex displacement, emitted as flat-shaded tris
  ## (normals computed per-triangle). Deterministic: same seed + same
  ## params = same mesh, byte-for-byte.
  var rng := RandomNumberGenerator.new()
  rng.seed = seed_int
  var deform_offset := Vector3(
    rng.randf_range(-100.0, 100.0),
    rng.randf_range(-100.0, 100.0),
    rng.randf_range(-100.0, 100.0),
  )

  var st := SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)

  var seg := radial_segments_n
  var rc := rings_n
  var verts := PackedVector3Array()
  verts.resize((rc + 1) * (seg + 1))

  for r in range(rc + 1):
    var theta := PI * float(r) / float(rc)
    var sin_t := sin(theta)
    var cos_t := cos(theta)
    for s in range(seg + 1):
      var phi := TAU * float(s) / float(seg)
      var dir := Vector3(sin_t * cos(phi), cos_t, sin_t * sin(phi))
      var disp := _static_fbm3(
        (dir + deform_offset) * deform_frequency_f,
        deform_octaves_n,
      )
      var r_local := base_radius_f * (1.0 + disp * deformation_f)
      var pt := dir * r_local
      pt.x *= squash_v.x
      pt.y *= squash_v.y
      pt.z *= squash_v.z
      verts[r * (seg + 1) + s] = pt

  for r in range(rc):
    for s in range(seg):
      var i00 := r * (seg + 1) + s
      var i01 := r * (seg + 1) + s + 1
      var i10 := (r + 1) * (seg + 1) + s
      var i11 := (r + 1) * (seg + 1) + s + 1
      var v00: Vector3 = verts[i00]
      var v01: Vector3 = verts[i01]
      var v10: Vector3 = verts[i10]
      var v11: Vector3 = verts[i11]
      # Triangle 1: v00, v10, v11 (CCW viewed from outside)
      var n1 := (v10 - v00).cross(v11 - v00).normalized()
      st.set_normal(n1)
      st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v11)
      # Triangle 2: v00, v11, v01
      var n2 := (v11 - v00).cross(v01 - v00).normalized()
      st.set_normal(n2)
      st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v01)

  return st.commit()


static func build_material_from_cfg(
  cfg: Dictionary, seed_int: int
) -> ShaderMaterial:
  ## Build a rock ShaderMaterial from a catalog config dict. Mirrors
  ## `_apply_all` on the instance side but reads directly from the dict,
  ## so fields (which never instantiate a node) can share the same look.
  var mat := ShaderMaterial.new()
  mat.shader = load(SHADER_PATH)
  mat.set_shader_parameter(
    &"color_low", cfg.get("color_low", Color(0.22, 0.19, 0.16))
  )
  mat.set_shader_parameter(
    &"color_mid", cfg.get("color_mid", Color(0.45, 0.38, 0.32))
  )
  mat.set_shader_parameter(
    &"color_high", cfg.get("color_high", Color(0.65, 0.58, 0.50))
  )
  mat.set_shader_parameter(&"noise_frequency", float(cfg.get("noise_frequency", 3.8)))
  mat.set_shader_parameter(&"noise_octaves", int(cfg.get("noise_octaves", 4)))
  mat.set_shader_parameter(&"noise_lacunarity", 2.0)
  mat.set_shader_parameter(&"noise_gain", 0.5)
  mat.set_shader_parameter(&"noise_warp", float(cfg.get("noise_warp", 0.6)))
  mat.set_shader_parameter(&"flat_shading", true)
  mat.set_shader_parameter(&"roughness_val", float(cfg.get("roughness", 0.95)))
  mat.set_shader_parameter(&"metallic_val", float(cfg.get("metallic", 0.0)))
  # Unused-by-rocks uniforms.
  mat.set_shader_parameter(&"sea_enabled", false)
  mat.set_shader_parameter(&"sea_level", 0.0)
  mat.set_shader_parameter(&"sea_color", Color.BLACK)
  mat.set_shader_parameter(&"pole_threshold", 2.0)
  mat.set_shader_parameter(&"pole_softness", 0.01)
  mat.set_shader_parameter(&"pole_color", Color.WHITE)
  mat.set_shader_parameter(&"band_strength", 0.0)
  mat.set_shader_parameter(&"emission_strength", 0.0)
  mat.set_shader_parameter(&"emission_cutoff", 1.0)
  mat.set_shader_parameter(&"emission_color", Color.WHITE)
  # Colour noise offset derived from seed + 999 (same as instance path).
  var rng := RandomNumberGenerator.new()
  rng.seed = seed_int + 999
  mat.set_shader_parameter(&"seed_offset", Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  ))
  return mat


# ---------------------------------------------------------------------------
# Noise (CPU side — used for mesh displacement only; shader has its own)
# ---------------------------------------------------------------------------

static func _static_hash3(p: Vector3) -> float:
  var h := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
  return h - floor(h)


static func _static_value_noise3(p: Vector3) -> float:
  var i := p.floor()
  var f := p - i
  f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
  var n000 := _static_hash3(i)
  var n100 := _static_hash3(i + Vector3(1, 0, 0))
  var n010 := _static_hash3(i + Vector3(0, 1, 0))
  var n110 := _static_hash3(i + Vector3(1, 1, 0))
  var n001 := _static_hash3(i + Vector3(0, 0, 1))
  var n101 := _static_hash3(i + Vector3(1, 0, 1))
  var n011 := _static_hash3(i + Vector3(0, 1, 1))
  var n111 := _static_hash3(i + Vector3(1, 1, 1))
  var nx00 := lerpf(n000, n100, f.x)
  var nx10 := lerpf(n010, n110, f.x)
  var nx01 := lerpf(n001, n101, f.x)
  var nx11 := lerpf(n011, n111, f.x)
  var nxy0 := lerpf(nx00, nx10, f.y)
  var nxy1 := lerpf(nx01, nx11, f.y)
  return lerpf(nxy0, nxy1, f.z) * 2.0 - 1.0


static func _static_fbm3(p: Vector3, octaves: int) -> float:
  var amp := 0.5
  var sum := 0.0
  var norm := 0.0
  var q := p
  for i in range(octaves):
    sum += amp * _static_value_noise3(q)
    norm += amp
    q *= 2.05
    amp *= 0.55
  return sum / maxf(norm, 0.0001)


# ---------------------------------------------------------------------------
# Material plumbing
# ---------------------------------------------------------------------------

func _set_uniform(name: StringName, value: Variant) -> void:
  if not _material:
    return
  _material.set_shader_parameter(name, value)


func _apply_color_seed() -> void:
  if not _material:
    return
  var rng := RandomNumberGenerator.new()
  rng.seed = asteroid_seed + 999  # decorrelate from deform offset
  var off := Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  )
  _set_uniform(&"seed_offset", off)


func _apply_all() -> void:
  ## Push the full shader state. Rocks don't use sea/pole/band/emission/
  ## cloud/ring features, so we explicitly zero those — the shader always
  ## reads all uniforms, and GDShader treats missing ones as 0 which can
  ## look ugly (black pole caps, for example).
  _set_uniform(&"color_low", color_low)
  _set_uniform(&"color_mid", color_mid)
  _set_uniform(&"color_high", color_high)
  _set_uniform(&"noise_frequency", noise_frequency)
  _set_uniform(&"noise_octaves", noise_octaves)
  _set_uniform(&"noise_lacunarity", 2.0)
  _set_uniform(&"noise_gain", 0.5)
  _set_uniform(&"noise_warp", noise_warp)
  _set_uniform(&"flat_shading", true)
  _set_uniform(&"roughness_val", roughness)
  _set_uniform(&"metallic_val", metallic)
  # Unused-by-rocks uniforms — keep them in valid ranges.
  _set_uniform(&"sea_enabled", false)
  _set_uniform(&"sea_level", 0.0)
  _set_uniform(&"sea_color", Color.BLACK)
  _set_uniform(&"pole_threshold", 2.0)  # >1 → pole mask never activates
  _set_uniform(&"pole_softness", 0.01)
  _set_uniform(&"pole_color", Color.WHITE)
  _set_uniform(&"band_strength", 0.0)
  _set_uniform(&"emission_strength", 0.0)
  _set_uniform(&"emission_cutoff", 1.0)
  _set_uniform(&"emission_color", Color.WHITE)
  _apply_color_seed()


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_config() -> Dictionary:
  return {
    "asteroid_seed": asteroid_seed,
    "radial_segments": radial_segments,
    "rings": rings,
    "base_radius": base_radius,
    "deformation": deformation,
    "deform_frequency": deform_frequency,
    "deform_octaves": deform_octaves,
    "squash": [squash.x, squash.y, squash.z],
    "color_low": color_low.to_html(false),
    "color_mid": color_mid.to_html(false),
    "color_high": color_high.to_html(false),
    "noise_frequency": noise_frequency,
    "noise_octaves": noise_octaves,
    "noise_warp": noise_warp,
    "roughness": roughness,
    "metallic": metallic,
    "tumble": [tumble.x, tumble.y, tumble.z],
  }
