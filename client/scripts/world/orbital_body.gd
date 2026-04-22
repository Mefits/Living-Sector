extends Node3D

## Renders an orbital body. Primary path: procedural planet built from the
## biome + body-id catalog (`planet_catalog.gd`). Fallback: GLTF model if
## the body has no biome or the biome is unknown — kept so unexpected
## server data still renders something.
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

  # Build the body visual. Three paths:
  #   1. body.type in {asteroid, belt} → ProceduralAsteroid (deformed rock)
  #   2. biome or body_id match in planet catalog → ProceduralPlanet
  #   3. fallback → legacy GLTF model, so unknown server bodies still render
  var biome: String = str(orbit_data.get("biome", ""))
  var body_type: String = str(orbit_data.get("type", ""))
  var s := BASE_SCALE * radius

  if body_type == "asteroid" or body_type == "belt":
    var ast_cfg := PlanetCatalog.build_asteroid_config(id, biome)
    var field_seed := hash(id + "_field")

    if body_type == "asteroid":
      # Lead rock + shell of smaller satellites around it.
      var ast := ProceduralAsteroid.new()
      ast.name = "Asteroid"
      ast.scale = Vector3(s, s, s)
      add_child(ast)
      PlanetCatalog.apply_to_asteroid(ast, id, ast_cfg)

      var field := AsteroidField.new()
      field.name = "AsteroidField"
      add_child(field)
      field.setup(ast_cfg, field_seed, {
        "count": 14,
        # Positions in world units, scaled off the lead's rendered radius.
        "spread_world": s * 6.0,
        "inner_world": s * 1.8,    # clear of the lead silhouette
        "size_min_world": s * 0.12,
        "size_max_world": s * 0.30,
        "layout": "shell",
      })
    else:
      # Belt: no dominant lead, just a disc of similar-sized rocks.
      var field := AsteroidField.new()
      field.name = "AsteroidField"
      add_child(field)
      field.setup(ast_cfg, field_seed, {
        "count": 55,
        "spread_world": s * 22.0,
        "inner_world": 0.0,
        "size_min_world": s * 0.35,
        "size_max_world": s * 0.75,
        "layout": "disc",
        "disc_thickness_world": s * 1.2,
      })
  else:
    var cfg: Dictionary = PlanetCatalog.build_config(id, biome)
    if not cfg.is_empty():
      var planet := ProceduralPlanet.new()
      planet.name = "Planet"
      planet.scale = Vector3(s, s, s)
      add_child(planet)  # _ready runs here → shader + ring slots ready
      PlanetCatalog.apply_to(planet, id, cfg)
    else:
      var scene: PackedScene = load(DEFAULT_MODEL)
      if scene:
        var model := scene.instantiate()
        model.scale = Vector3(s, s, s)
        model.rotation_degrees.x = -90.0
        add_child(model)

  label.position = Vector3(0, s + 1.0, 0)

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


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
  # Body labels visible at SYSTEM and closer
  label.visible = (tier <= GameState.ZoomTier.SYSTEM)
