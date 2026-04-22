@tool
extends Node3D
class_name ProceduralPlanet

## Low-poly procedural planet. Deterministic from `planet_seed` — same seed
## + same params = same planet. Drop this node anywhere, tweak `preset` or
## the individual uniforms, and it rebuilds live.
##
## Design:
##  - SphereMesh at `radial_segments` × `rings`. Low values (e.g. 24×12)
##    give the faceted low-poly silhouette from the reference shot.
##  - ShaderMaterial wraps `res://shaders/procedural_planet.gdshader`. All
##    the visual knobs are shader uniforms — seed is converted to a vec3
##    offset so noise stays continuous but decorrelated across seeds.
##  - Preset changes overwrite the palette + shape knobs in one shot.
##    Individual property setters push straight to the shader so you can
##    fine-tune after picking a preset.

const SHADER_PATH := "res://shaders/procedural_planet.gdshader"
const CLOUD_SHADER_PATH := "res://shaders/procedural_clouds.gdshader"

enum Preset {
  CUSTOM,
  EARTHLIKE,
  ROCKY,
  DESERT,
  ICE,
  LAVA,
  GAS_GIANT,
  BARREN,
  OCEAN,
}

# ---- Geometry -------------------------------------------------------------
@export_range(0.01, 50.0, 0.01) var radius: float = 1.0:
  set(v): radius = v; _apply_geometry()
@export_range(6, 64, 1) var radial_segments: int = 24:
  set(v): radial_segments = v; _apply_geometry()
@export_range(4, 32, 1) var rings: int = 12:
  set(v): rings = v; _apply_geometry()

# ---- Seed & preset --------------------------------------------------------
@export var planet_seed: int = 1337:
  set(v): planet_seed = v; _apply_seed()

@export var preset: Preset = Preset.EARTHLIKE:
  set(v):
    preset = v
    if v != Preset.CUSTOM:
      _apply_preset(v)

# ---- Palette --------------------------------------------------------------
@export_group("Palette")
@export var color_low: Color = Color(0.20, 0.35, 0.15):
  set(v): color_low = v; _set_uniform(&"color_low", v)
@export var color_mid: Color = Color(0.45, 0.38, 0.22):
  set(v): color_mid = v; _set_uniform(&"color_mid", v)
@export var color_high: Color = Color(0.80, 0.78, 0.75):
  set(v): color_high = v; _set_uniform(&"color_high", v)
@export var sea_color: Color = Color(0.05, 0.18, 0.40):
  set(v): sea_color = v; _set_uniform(&"sea_color", v)
@export var pole_color: Color = Color(0.95, 0.97, 1.00):
  set(v): pole_color = v; _set_uniform(&"pole_color", v)
@export var emission_color: Color = Color(1.0, 0.35, 0.05):
  set(v): emission_color = v; _set_uniform(&"emission_color", v)

# ---- Shape knobs ----------------------------------------------------------
@export_group("Shape")
@export var sea_enabled: bool = true:
  set(v): sea_enabled = v; _set_uniform(&"sea_enabled", v)
@export_range(0.0, 1.0, 0.01) var sea_level: float = 0.45:
  set(v): sea_level = v; _set_uniform(&"sea_level", v)
@export_range(0.0, 1.0, 0.01) var pole_threshold: float = 0.78:
  set(v): pole_threshold = v; _set_uniform(&"pole_threshold", v)
@export_range(0.001, 0.5, 0.001) var pole_softness: float = 0.08:
  set(v): pole_softness = v; _set_uniform(&"pole_softness", v)
@export_range(0.1, 12.0, 0.01) var noise_frequency: float = 2.0:
  set(v): noise_frequency = v; _set_uniform(&"noise_frequency", v)
@export_range(1, 6, 1) var noise_octaves: int = 4:
  set(v): noise_octaves = v; _set_uniform(&"noise_octaves", v)
@export_range(1.5, 3.5, 0.01) var noise_lacunarity: float = 2.0:
  set(v): noise_lacunarity = v; _set_uniform(&"noise_lacunarity", v)
@export_range(0.2, 0.8, 0.01) var noise_gain: float = 0.5:
  set(v): noise_gain = v; _set_uniform(&"noise_gain", v)
@export_range(0.0, 2.0, 0.01) var noise_warp: float = 0.0:
  set(v): noise_warp = v; _set_uniform(&"noise_warp", v)
@export_range(0.0, 1.0, 0.01) var band_strength: float = 0.0:
  set(v): band_strength = v; _set_uniform(&"band_strength", v)

# ---- Emission / surface ---------------------------------------------------
@export_group("Emission & Surface")
@export_range(0.0, 4.0, 0.01) var emission_strength: float = 0.0:
  set(v): emission_strength = v; _set_uniform(&"emission_strength", v)
@export_range(0.0, 1.0, 0.01) var emission_cutoff: float = 0.6:
  set(v): emission_cutoff = v; _set_uniform(&"emission_cutoff", v)
@export var flat_shading: bool = true:
  set(v): flat_shading = v; _set_uniform(&"flat_shading", v)
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.9:
  set(v): roughness = v; _set_uniform(&"roughness_val", v)
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0:
  set(v): metallic = v; _set_uniform(&"metallic_val", v)

# ---- Rotation -------------------------------------------------------------
@export_range(-2.0, 2.0, 0.01) var spin_speed: float = 0.1

# ---- Rings ----------------------------------------------------------------
# Up to MAX_RINGS flat annular rings, each independently tilted, coloured,
# and spun. Geometry is a two-sided triangle fan built via SurfaceTool so
# rings render correctly from above and below. Per-ring state lives in
# `_ring_configs` as Dictionaries (stable keys listed in DEFAULT_RING); the
# playground edits them via `set_ring_param`.

const MAX_RINGS := 4
const DEFAULT_RING := {
  "inner": 1.35,
  "outer": 1.85,
  "tilt_x": 15.0,     # degrees
  "tilt_z": 0.0,      # degrees
  "color": Color(0.85, 0.78, 0.62, 0.7),
  "emission": 0.0,
  "spin_speed": 0.05,
  "segments": 64,
}

signal rings_changed

@export_range(0, 4, 1) var ring_count: int = 0:
  set(v):
    ring_count = clampi(v, 0, MAX_RINGS)
    _resize_rings()

# ---- Clouds ---------------------------------------------------------------
# Transparent shell sphere slightly larger than the planet, sampled from a
# separate 3D-noise shader. Independent spin axis from the planet so the
# cloud layer drifts visibly. Seed is derived from `planet_seed` + an
# offset so clouds decorrelate from terrain but stay deterministic.
@export_group("Clouds")
@export var cloud_enabled: bool = false:
  set(v):
    cloud_enabled = v
    _refresh_clouds()
@export var cloud_color: Color = Color(1.0, 1.0, 1.0):
  set(v): cloud_color = v; _set_cloud_uniform(&"cloud_color", v)
@export_range(0.0, 1.0, 0.01) var cloud_opacity: float = 1.0:
  set(v): cloud_opacity = v; _set_cloud_uniform(&"cloud_opacity", v)
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.55:
  set(v): cloud_coverage = v; _set_cloud_uniform(&"cloud_coverage", v)
@export_range(0.001, 0.5, 0.001) var cloud_softness: float = 0.08:
  set(v): cloud_softness = v; _set_cloud_uniform(&"cloud_softness", v)
@export_range(0.1, 12.0, 0.01) var cloud_frequency: float = 2.8:
  set(v): cloud_frequency = v; _set_cloud_uniform(&"cloud_frequency", v)
@export_range(1, 6, 1) var cloud_octaves: int = 4:
  set(v): cloud_octaves = v; _set_cloud_uniform(&"cloud_octaves", v)
@export_range(1.001, 1.3, 0.001) var cloud_height: float = 1.04:
  set(v):
    cloud_height = v
    # Height change means the shell sphere radius moved — rebuild.
    if _cloud_mesh: _apply_cloud_geometry()
@export_range(-2.0, 2.0, 0.01) var cloud_spin_speed: float = 0.03

# Internal state
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _ready_done := false
var _rings_node: Node3D
var _ring_configs: Array = []   # Array[Dictionary]
var _ring_meshes: Array = []    # Array[MeshInstance3D]
var _cloud_mesh: MeshInstance3D
var _cloud_material: ShaderMaterial


func _ready() -> void:
  _build()
  _rings_node = Node3D.new()
  _rings_node.name = "Rings"
  add_child(_rings_node)
  _resize_rings()  # materialise whatever ring_count was at construction
  _refresh_clouds()  # materialise cloud shell if enabled
  _ready_done = true
  # Push everything after ready so setters that ran pre-ready land correctly.
  _apply_all()


func _process(delta: float) -> void:
  # Don't rotate while we're just sitting in the editor — it's distracting
  # when tweaking the inspector. Only spin at play time.
  if Engine.is_editor_hint():
    return
  if _mesh_instance and not is_zero_approx(spin_speed):
    _mesh_instance.rotate_y(spin_speed * delta)
  if _cloud_mesh and not is_zero_approx(cloud_spin_speed):
    _cloud_mesh.rotate_y(cloud_spin_speed * delta)
  for i in range(_ring_meshes.size()):
    var cfg: Dictionary = _ring_configs[i]
    var rspeed: float = float(cfg.get("spin_speed", 0.0))
    if not is_zero_approx(rspeed):
      var mi: MeshInstance3D = _ring_meshes[i]
      # Spin around the ring's local up axis so tilt is preserved.
      mi.rotate_object_local(Vector3.UP, rspeed * delta)


func _build() -> void:
  _mesh_instance = MeshInstance3D.new()
  _mesh_instance.name = "PlanetMesh"
  add_child(_mesh_instance)

  var shader: Shader = load(SHADER_PATH)
  _material = ShaderMaterial.new()
  _material.shader = shader
  _mesh_instance.material_override = _material

  _apply_geometry()


func _apply_geometry() -> void:
  if not _mesh_instance:
    return
  var sphere := SphereMesh.new()
  sphere.radius = radius
  sphere.height = radius * 2.0
  sphere.radial_segments = radial_segments
  sphere.rings = rings
  _mesh_instance.mesh = sphere
  # Cloud shell tracks the planet's radius + poly budget.
  _apply_cloud_geometry()


# ---- Rings ----------------------------------------------------------------

func _resize_rings() -> void:
  # Grow/shrink the ring-config array to match ring_count, then sync the
  # MeshInstance3D children. Rebuild every ring mesh so geometry reflects
  # any config that was edited while hidden.
  if not _rings_node:
    return  # pre-ready; _ready() calls us again once _rings_node exists

  while _ring_configs.size() < ring_count:
    _ring_configs.append(DEFAULT_RING.duplicate(true))
  while _ring_configs.size() > ring_count:
    _ring_configs.pop_back()

  while _ring_meshes.size() > ring_count:
    var dead: MeshInstance3D = _ring_meshes.pop_back()
    dead.queue_free()
  while _ring_meshes.size() < ring_count:
    var mi := MeshInstance3D.new()
    mi.name = "Ring%d" % _ring_meshes.size()
    _rings_node.add_child(mi)
    _ring_meshes.append(mi)

  for i in range(ring_count):
    _rebuild_ring(i)

  rings_changed.emit()


func _rebuild_ring(i: int) -> void:
  if i < 0 or i >= _ring_meshes.size():
    return
  var cfg: Dictionary = _ring_configs[i]
  var mi: MeshInstance3D = _ring_meshes[i]

  var inner: float = float(cfg.get("inner", 1.35))
  var outer: float = float(cfg.get("outer", 1.85))
  var segments: int = int(cfg.get("segments", 64))
  if outer <= inner:
    outer = inner + 0.01
  segments = max(segments, 8)

  mi.mesh = _build_annulus(inner, outer, segments)

  # Reset rotation (preserve position/scale) then apply tilts.
  mi.transform = Transform3D.IDENTITY
  mi.rotate_x(deg_to_rad(float(cfg.get("tilt_x", 15.0))))
  mi.rotate_z(deg_to_rad(float(cfg.get("tilt_z", 0.0))))

  var col: Color = cfg.get("color", Color(1, 1, 1, 0.7))
  var mat := StandardMaterial3D.new()
  mat.albedo_color = col
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.cull_mode = BaseMaterial3D.CULL_BACK  # annulus is two-sided geometry
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
  var em: float = float(cfg.get("emission", 0.0))
  if em > 0.0:
    mat.emission_enabled = true
    mat.emission = Color(col.r, col.g, col.b)
    mat.emission_energy_multiplier = em
  mi.material_override = mat


func _build_annulus(
  inner: float, outer: float, segments: int
) -> ArrayMesh:
  # Flat annulus, two-sided (top normal +Y, bottom normal -Y with reversed
  # winding) so lighting is correct from either side without disabling
  # backface culling.
  var st := SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)

  st.set_normal(Vector3.UP)
  for s in range(segments):
    var a0 := float(s) * TAU / float(segments)
    var a1 := float(s + 1) * TAU / float(segments)
    var c0i := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
    var c0o := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
    var c1i := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
    var c1o := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
    st.add_vertex(c0i); st.add_vertex(c0o); st.add_vertex(c1o)
    st.add_vertex(c0i); st.add_vertex(c1o); st.add_vertex(c1i)

  st.set_normal(Vector3.DOWN)
  for s in range(segments):
    var a0 := float(s) * TAU / float(segments)
    var a1 := float(s + 1) * TAU / float(segments)
    var c0i := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
    var c0o := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
    var c1i := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
    var c1o := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
    st.add_vertex(c0i); st.add_vertex(c1o); st.add_vertex(c0o)
    st.add_vertex(c0i); st.add_vertex(c1i); st.add_vertex(c1o)

  return st.commit()


# ---- Clouds ---------------------------------------------------------------

func _refresh_clouds() -> void:
  ## Create/destroy the cloud shell to match `cloud_enabled`. No-op if the
  ## node is still being constructed — `_ready` calls us again once the
  ## planet tree exists.
  if not _mesh_instance:
    return  # pre-ready; setter fired during var init, will retry in _ready
  if cloud_enabled and _cloud_mesh == null:
    _build_clouds()
  elif not cloud_enabled and _cloud_mesh != null:
    _cloud_mesh.queue_free()
    _cloud_mesh = null
    _cloud_material = null


func _build_clouds() -> void:
  var shader: Shader = load(CLOUD_SHADER_PATH)
  _cloud_material = ShaderMaterial.new()
  _cloud_material.shader = shader

  _cloud_mesh = MeshInstance3D.new()
  _cloud_mesh.name = "Clouds"
  _cloud_mesh.material_override = _cloud_material
  add_child(_cloud_mesh)

  _apply_cloud_geometry()
  _apply_cloud_uniforms()


func _apply_cloud_geometry() -> void:
  if not _cloud_mesh:
    return
  var sphere := SphereMesh.new()
  # Shell radius = planet radius × cloud_height. Same poly budget as the
  # planet so silhouettes line up at close range.
  var r := radius * cloud_height
  sphere.radius = r
  sphere.height = r * 2.0
  sphere.radial_segments = radial_segments
  sphere.rings = rings
  _cloud_mesh.mesh = sphere


func _apply_cloud_uniforms() -> void:
  if not _cloud_material:
    return
  _set_cloud_uniform(&"cloud_color", cloud_color)
  _set_cloud_uniform(&"cloud_opacity", cloud_opacity)
  _set_cloud_uniform(&"cloud_coverage", cloud_coverage)
  _set_cloud_uniform(&"cloud_softness", cloud_softness)
  _set_cloud_uniform(&"cloud_frequency", cloud_frequency)
  _set_cloud_uniform(&"cloud_octaves", cloud_octaves)
  _apply_cloud_seed()


func _set_cloud_uniform(name: StringName, value: Variant) -> void:
  if not _cloud_material:
    return
  _cloud_material.set_shader_parameter(name, value)


func _apply_cloud_seed() -> void:
  # Derive a second offset decorrelated from the terrain one so clouds
  # don't line up with continents. Same planet_seed → same cloud pattern.
  var rng := RandomNumberGenerator.new()
  rng.seed = planet_seed + 0x5EEDBEEF
  var off := Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  )
  _set_cloud_uniform(&"cloud_seed_offset", off)


func set_ring_param(index: int, key: String, value: Variant) -> void:
  if index < 0 or index >= _ring_configs.size():
    return
  _ring_configs[index][key] = value
  # spin_speed is consumed by _process directly — no mesh rebuild required.
  if key == "spin_speed":
    return
  _rebuild_ring(index)


func get_ring_param(index: int, key: String) -> Variant:
  if index < 0 or index >= _ring_configs.size():
    return DEFAULT_RING.get(key, null)
  return _ring_configs[index].get(key, DEFAULT_RING.get(key, null))


func _set_uniform(name: StringName, value: Variant) -> void:
  if not _material:
    return
  _material.set_shader_parameter(name, value)


func _apply_seed() -> void:
  var rng := RandomNumberGenerator.new()
  rng.seed = planet_seed
  var off := Vector3(
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
    rng.randf_range(-1000.0, 1000.0),
  )
  _set_uniform(&"seed_offset", off)
  _apply_cloud_seed()


func _apply_all() -> void:
  ## Push every current property to the shader. Used after ready and after
  ## a preset change, so the material state is exactly the inspector state.
  _set_uniform(&"color_low", color_low)
  _set_uniform(&"color_mid", color_mid)
  _set_uniform(&"color_high", color_high)
  _set_uniform(&"sea_color", sea_color)
  _set_uniform(&"pole_color", pole_color)
  _set_uniform(&"emission_color", emission_color)
  _set_uniform(&"sea_enabled", sea_enabled)
  _set_uniform(&"sea_level", sea_level)
  _set_uniform(&"pole_threshold", pole_threshold)
  _set_uniform(&"pole_softness", pole_softness)
  _set_uniform(&"noise_frequency", noise_frequency)
  _set_uniform(&"noise_octaves", noise_octaves)
  _set_uniform(&"noise_lacunarity", noise_lacunarity)
  _set_uniform(&"noise_gain", noise_gain)
  _set_uniform(&"noise_warp", noise_warp)
  _set_uniform(&"band_strength", band_strength)
  _set_uniform(&"emission_strength", emission_strength)
  _set_uniform(&"emission_cutoff", emission_cutoff)
  _set_uniform(&"flat_shading", flat_shading)
  _set_uniform(&"roughness_val", roughness)
  _set_uniform(&"metallic_val", metallic)
  _apply_seed()
  _apply_cloud_uniforms()


func _apply_preset(p: Preset) -> void:
  match p:
    Preset.EARTHLIKE:
      color_low = Color(0.18, 0.38, 0.18)
      color_mid = Color(0.48, 0.42, 0.25)
      color_high = Color(0.82, 0.80, 0.76)
      sea_color = Color(0.05, 0.20, 0.42)
      pole_color = Color(0.95, 0.97, 1.0)
      sea_enabled = true
      sea_level = 0.48
      pole_threshold = 0.78
      pole_softness = 0.08
      noise_frequency = 2.2
      noise_octaves = 5
      noise_lacunarity = 2.0
      noise_gain = 0.5
      noise_warp = 0.3
      band_strength = 0.0
      emission_strength = 0.0
      flat_shading = true
      roughness = 0.9
      metallic = 0.0
    Preset.ROCKY:
      color_low = Color(0.30, 0.22, 0.18)
      color_mid = Color(0.50, 0.38, 0.30)
      color_high = Color(0.70, 0.62, 0.55)
      pole_color = Color(0.85, 0.82, 0.78)
      sea_enabled = false
      pole_threshold = 0.92
      pole_softness = 0.05
      noise_frequency = 3.0
      noise_octaves = 5
      noise_lacunarity = 2.1
      noise_gain = 0.55
      noise_warp = 0.4
      band_strength = 0.0
      emission_strength = 0.0
      roughness = 0.95
      metallic = 0.0
    Preset.DESERT:
      color_low = Color(0.62, 0.48, 0.28)
      color_mid = Color(0.78, 0.60, 0.35)
      color_high = Color(0.92, 0.80, 0.55)
      pole_color = Color(0.88, 0.80, 0.62)
      sea_enabled = false
      pole_threshold = 0.95
      noise_frequency = 2.5
      noise_octaves = 4
      noise_warp = 0.5
      band_strength = 0.15
      emission_strength = 0.0
      roughness = 0.9
    Preset.ICE:
      color_low = Color(0.55, 0.70, 0.85)
      color_mid = Color(0.78, 0.88, 0.95)
      color_high = Color(0.95, 0.97, 1.0)
      sea_color = Color(0.12, 0.32, 0.55)
      pole_color = Color(1.0, 1.0, 1.0)
      sea_enabled = true
      sea_level = 0.30
      pole_threshold = 0.50
      pole_softness = 0.20
      noise_frequency = 2.0
      noise_octaves = 4
      noise_warp = 0.2
      emission_strength = 0.0
      roughness = 0.5
      metallic = 0.1
    Preset.LAVA:
      color_low = Color(0.08, 0.04, 0.03)
      color_mid = Color(0.30, 0.10, 0.05)
      color_high = Color(0.80, 0.25, 0.08)
      emission_color = Color(1.0, 0.45, 0.10)
      pole_color = Color(0.25, 0.10, 0.05)
      sea_enabled = false
      pole_threshold = 0.95
      noise_frequency = 3.5
      noise_octaves = 5
      noise_warp = 0.6
      emission_strength = 2.0
      emission_cutoff = 0.55
      roughness = 0.7
    Preset.GAS_GIANT:
      color_low = Color(0.70, 0.55, 0.40)
      color_mid = Color(0.85, 0.75, 0.60)
      color_high = Color(0.55, 0.40, 0.32)
      pole_color = Color(0.85, 0.82, 0.78)
      sea_enabled = false
      pole_threshold = 0.90
      pole_softness = 0.15
      noise_frequency = 1.5
      noise_octaves = 4
      noise_lacunarity = 2.2
      noise_gain = 0.55
      noise_warp = 0.8
      band_strength = 0.85
      emission_strength = 0.0
      roughness = 0.8
      flat_shading = false  # smooth bands read better
    Preset.BARREN:
      color_low = Color(0.28, 0.27, 0.26)
      color_mid = Color(0.48, 0.46, 0.44)
      color_high = Color(0.72, 0.70, 0.68)
      pole_color = Color(0.80, 0.80, 0.82)
      sea_enabled = false
      pole_threshold = 0.95
      noise_frequency = 3.2
      noise_octaves = 4
      noise_warp = 0.2
      band_strength = 0.0
      emission_strength = 0.0
      roughness = 0.95
    Preset.OCEAN:
      color_low = Color(0.05, 0.20, 0.45)
      color_mid = Color(0.10, 0.35, 0.58)
      color_high = Color(0.25, 0.55, 0.72)
      sea_color = Color(0.04, 0.14, 0.32)
      pole_color = Color(0.95, 0.97, 1.0)
      sea_enabled = true
      sea_level = 0.78
      pole_threshold = 0.80
      noise_frequency = 2.0
      noise_octaves = 4
      noise_warp = 0.3
      emission_strength = 0.0
      roughness = 0.4
      metallic = 0.1
    _:
      pass
  if _ready_done:
    _apply_all()


func to_config() -> Dictionary:
  ## Serialise current params. Handy for pasting out of the playground
  ## into server-side planet definitions later.
  var ring_list: Array = []
  for cfg in _ring_configs:
    var c: Color = cfg.get("color", Color(1, 1, 1, 0.7))
    ring_list.append({
      "inner": cfg.get("inner"),
      "outer": cfg.get("outer"),
      "tilt_x": cfg.get("tilt_x"),
      "tilt_z": cfg.get("tilt_z"),
      "color": c.to_html(true),  # include alpha
      "emission": cfg.get("emission"),
      "spin_speed": cfg.get("spin_speed"),
      "segments": cfg.get("segments"),
    })
  return {
    "planet_seed": planet_seed,
    "preset": preset,
    "radial_segments": radial_segments,
    "rings": rings,
    "color_low": color_low.to_html(false),
    "color_mid": color_mid.to_html(false),
    "color_high": color_high.to_html(false),
    "sea_color": sea_color.to_html(false),
    "pole_color": pole_color.to_html(false),
    "emission_color": emission_color.to_html(false),
    "sea_enabled": sea_enabled,
    "sea_level": sea_level,
    "pole_threshold": pole_threshold,
    "pole_softness": pole_softness,
    "noise_frequency": noise_frequency,
    "noise_octaves": noise_octaves,
    "noise_lacunarity": noise_lacunarity,
    "noise_gain": noise_gain,
    "noise_warp": noise_warp,
    "band_strength": band_strength,
    "emission_strength": emission_strength,
    "emission_cutoff": emission_cutoff,
    "flat_shading": flat_shading,
    "roughness": roughness,
    "metallic": metallic,
    "ring_count": ring_count,
    "ring_configs": ring_list,
    "cloud_enabled": cloud_enabled,
    "cloud_color": cloud_color.to_html(true),
    "cloud_opacity": cloud_opacity,
    "cloud_coverage": cloud_coverage,
    "cloud_softness": cloud_softness,
    "cloud_frequency": cloud_frequency,
    "cloud_octaves": cloud_octaves,
    "cloud_height": cloud_height,
    "cloud_spin_speed": cloud_spin_speed,
  }
