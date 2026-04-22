extends Node3D

## Renders an orbital body using a planet 3D model.
##
## Position is server-driven: `universe.gd` routes the per-tick `positions`
## broadcast into `update_position(x, y)` and we lerp toward it exactly
## like `facility.gd` does. This keeps bodies and their orbiting facilities
## in lockstep — facilities are anchored to body positions server-side, so
## consuming the same stream here prevents the drift/jump we saw when the
## client predicted orbits independently while server positions advanced
## at a different rate after a world_speed change.
##
## Orbital params (radius/period/angle) are kept only as a *fallback* used
## briefly during scene build, before the first server position arrives.

var body_id: String
var _ring: MeshInstance3D

# Bodies that get an animated ring
const RINGED_BODIES := ["saturn", "mars"]
const RING_COLOR := Color(0.8, 0.75, 0.6, 0.4)

# System-space offset cached at setup time. Server positions arrive in
# absolute universe coordinates; this body lives inside a star_system
# Node3D already translated to `_system_offset`, so we convert on arrival.
var _system_offset: Vector2 = Vector2.ZERO

# Server-driven position state (primary path).
var _prev_pos: Vector3
var _next_pos: Vector3
var _lerp_t: float = 1.0
var _received_server_pos: bool = false

# Orbital prediction fallback — only used before first server position.
var _orbit_radius: float = 0.0
var _orbit_period: float = 0.0
var _initial_angle: float = 0.0
var _initial_tick: int = 0
var _has_orbit := false
var _visual_radius: float = 0.5

@onready var label: Label3D = $Label3D

const BODY_MODELS := {
  "earth": "res://assets/planets/Planet_1.gltf",
  "mars": "res://assets/planets/Planet_11.gltf",
  "venus": "res://assets/planets/Planet_2.gltf",
  "jupiter": "res://assets/planets/Planet_6.gltf",
  "saturn": "res://assets/planets/Planet_7.gltf",
  "luna": "res://assets/planets/Planet_3.gltf",
  "mercury": "res://assets/planets/Planet_4.gltf",
  "proxima": "res://assets/planets/Planet_8.gltf",
  "haven": "res://assets/planets/Planet_9.gltf",
  "asteroid-belt": "res://assets/planets/Planet_5.gltf",
  "near-earth asteroid": "res://assets/planets/Planet_5.gltf",
  "trojan cluster": "res://assets/planets/Planet_5.gltf",
  "hilda group": "res://assets/planets/Planet_5.gltf",
  "kuiper object": "res://assets/planets/Planet_4.gltf",
  "ac belt": "res://assets/planets/Planet_5.gltf",
  "outer rocks": "res://assets/planets/Planet_5.gltf",
  "slag field": "res://assets/planets/Planet_11.gltf",
  "deep ice": "res://assets/planets/Planet_9.gltf",
  "forge": "res://assets/planets/Planet_11.gltf",
  "anvil": "res://assets/planets/Planet_3.gltf",
  "crucible": "res://assets/planets/Planet_2.gltf",
  "frostheim": "res://assets/planets/Planet_9.gltf",
  "refuge": "res://assets/planets/Planet_1.gltf",
}

const DEFAULT_MODEL := "res://assets/planets/Planet_3.gltf"
const BASE_SCALE := 0.4


func setup(
  id: String, display_name: String,
  world_pos: Vector3, radius: float,
  orbit_data: Dictionary = {}
) -> void:
  body_id = id
  position = world_pos
  _prev_pos = world_pos
  _next_pos = world_pos
  label.text = display_name
  _visual_radius = radius

  # Cache the owning system's offset so `update_position` can convert the
  # absolute universe coordinates the server sends into local system space
  # cheaply (no tree walk per tick).
  for sys in GameState.systems.values():
    for body in sys.get("bodies", []):
      if str(body.get("id", "")) == body_id:
        _system_offset = GameState.get_system_offset(sys["id"])
        break

  # Store orbital params for fallback prediction (used only until the first
  # server `positions` broadcast lands — usually < 1 tick).
  if orbit_data.has("orbit_radius") and orbit_data.has("orbit_period"):
    _orbit_radius = float(orbit_data["orbit_radius"])
    _orbit_period = float(orbit_data["orbit_period"])
    _initial_angle = float(orbit_data.get("current_angle", 0.0))
    _initial_tick = GameState.tick
    _has_orbit = _orbit_period > 0.0

  # Load planet model
  var model_path: String = BODY_MODELS.get(id, DEFAULT_MODEL)
  var scene: PackedScene = load(model_path)
  if scene:
    var model := scene.instantiate()
    var s := BASE_SCALE * radius
    model.scale = Vector3(s, s, s)
    model.rotation_degrees.x = -90.0
    add_child(model)

  label.position = Vector3(0, radius * BASE_SCALE + 1.0, 0)

  # Animated ring for gas giants
  if id in RINGED_BODIES:
    _create_ring(radius)

  GameState.zoom_changed.connect(_on_zoom_changed)
  _on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)


func update_position(abs_x: float, abs_y: float) -> void:
  ## Called by `universe.gd::_on_positions_updated` each tick. `abs_x` and
  ## `abs_y` are absolute universe coordinates; we subtract the cached
  ## system offset to get local coords inside the star_system Node3D.
  var rel_x := abs_x - _system_offset.x
  var rel_y := abs_y - _system_offset.y
  _prev_pos = _next_pos
  _next_pos = GameState.server_to_world(rel_x, rel_y)
  _lerp_t = 0.0
  _received_server_pos = true


func _process(_delta: float) -> void:
  # Slowly rotate ring
  if _ring:
    _ring.rotation_degrees.y += _delta * 5.0

  if _received_server_pos:
    # Server-driven path (primary). Lerp between the last two broadcast
    # positions over the wall-clock gap. `get_effective_interval_seconds`
    # uses the observed cadence so we don't jitter if the server's
    # reported interval briefly disagrees with reality.
    if _lerp_t < 1.0:
      var interval := GameState.get_effective_interval_seconds()
      _lerp_t = minf(_lerp_t + _delta / interval, 1.0)
      var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
      position = _prev_pos.lerp(_next_pos, t)
    return

  # Pre-first-broadcast fallback: use the seed orbit math so we don't
  # snap from origin when the scene first builds. Dropped the moment the
  # first server position arrives.
  if not _has_orbit:
    return
  var ticks_elapsed: int = GameState.tick - _initial_tick
  var delta_per_tick := 360.0 / _orbit_period * GameState.tick_scale
  var angle_deg := fmod(
    _initial_angle + delta_per_tick * ticks_elapsed, 360.0
  )
  var angle_rad := deg_to_rad(angle_deg)
  var local_x := _orbit_radius * cos(angle_rad)
  var local_y := _orbit_radius * sin(angle_rad)
  position = GameState.server_to_world(local_x, local_y)


func _create_ring(radius: float) -> void:
  var torus := TorusMesh.new()
  var ring_radius := radius * BASE_SCALE * 1.8
  torus.inner_radius = ring_radius * 0.85
  torus.outer_radius = ring_radius * 1.15
  torus.rings = 32
  torus.ring_segments = 16

  _ring = MeshInstance3D.new()
  _ring.mesh = torus
  _ring.rotation_degrees.x = -80.0  # Slight tilt

  var mat := StandardMaterial3D.new()
  mat.albedo_color = RING_COLOR
  mat.emission_enabled = true
  mat.emission = Color(RING_COLOR, 1.0) * 0.3
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  _ring.material_override = mat

  add_child(_ring)


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
  # Body labels visible at SYSTEM and closer
  label.visible = (tier <= GameState.ZoomTier.SYSTEM)
