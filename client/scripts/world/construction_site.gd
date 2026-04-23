extends Node3D

## Renders a construction site — a half-built facility the demand
## analyzer spawned in response to chronic commodity shortage. Pairs
## with the sim's `ConstructionSite` component (Phase 19c-b/c).
##
## Visual: a thin glowing cylinder ("hull core") surrounded by a cyan
## torus ring that grows with progress. When progress hits 1.0 the
## sim replaces this entity with a real facility at the same
## position, so universe.gd will queue_free this node automatically
## on the next /api/construction_sites refresh.
##
## Position flow mirrors facility.gd / orbital_body.gd: the server
## sends authoritative positions via the tick stream and we lerp
## between them. Sites don't move — they orbit with their body — so
## position updates arrive at the same cadence other entities get.

const BASE_SCALE := 0.08
const LABEL_OFFSET := Vector3(0, 0.25, 0)

var site_id: String = ""
var site_data: Dictionary = {}
var _prev_pos: Vector3
var _next_pos: Vector3
var _lerp_t: float = 1.0
var _system_offset: Vector2 = Vector2.ZERO

var _core_mesh: MeshInstance3D
var _ring_mesh: MeshInstance3D
var _progress_label: Label3D


func setup(data: Dictionary, world_pos: Vector3) -> void:
  site_id = str(data.get("id", ""))
  site_data = data
  position = world_pos
  _prev_pos = world_pos
  _next_pos = world_pos

  # Cache the owning system's offset so `update_position` can convert
  # absolute universe coordinates into local system space (same
  # pattern as facility.gd / orbital_body.gd).
  var location_name: String = str(data.get("location", ""))
  for sys in GameState.systems.values():
    for body in sys.get("bodies", []):
      for fac in body.get("facilities", []):
        if str(fac.get("location", "")) == location_name:
          _system_offset = GameState.get_system_offset(sys["id"])
          break

  _build_visual()
  _refresh_progress_display(float(data.get("progress", 0.0)))


func update_position(abs_x: float, abs_y: float) -> void:
  var rel_x := abs_x - _system_offset.x
  var rel_y := abs_y - _system_offset.y
  if _lerp_t < 1.0:
    var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
    _prev_pos = _prev_pos.lerp(_next_pos, t)
  else:
    _prev_pos = _next_pos
  _next_pos = GameState.server_to_world(rel_x, rel_y)
  _lerp_t = 0.0


func update_state(data: Dictionary) -> void:
  ## Called when a new /api/construction_sites snapshot arrives.
  ## Refreshes progress display only; position is handled by
  ## update_position via the positions broadcast.
  site_data = data
  _refresh_progress_display(float(data.get("progress", 0.0)))


func _process(delta: float) -> void:
  if _lerp_t < 1.0:
    var interval := GameState.get_effective_interval_seconds()
    _lerp_t = minf(_lerp_t + delta / interval, 1.0)
    var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
    position = _prev_pos.lerp(_next_pos, t)

  # Rotate the ring gently so the site reads as "active work".
  if _ring_mesh:
    _ring_mesh.rotate_y(delta * 0.6)


func _build_visual() -> void:
  # Core "hull under construction": a short glowing cylinder. Small
  # so it doesn't visually dominate at system-scale zoom.
  var core_scale := BASE_SCALE
  _core_mesh = MeshInstance3D.new()
  var cyl := CylinderMesh.new()
  cyl.height = 1.0
  cyl.top_radius = 0.25
  cyl.bottom_radius = 0.35
  _core_mesh.mesh = cyl
  _core_mesh.scale = Vector3.ONE * core_scale
  var core_mat := StandardMaterial3D.new()
  core_mat.albedo_color = Color(0.3, 0.45, 0.6, 1.0)
  core_mat.emission_enabled = true
  core_mat.emission = Color(0.35, 0.6, 0.9) * 0.6
  core_mat.metallic = 0.6
  core_mat.roughness = 0.4
  _core_mesh.material_override = core_mat
  add_child(_core_mesh)

  # Progress ring: cyan torus around the core, scaled with progress.
  _ring_mesh = MeshInstance3D.new()
  var torus := TorusMesh.new()
  torus.inner_radius = 0.45
  torus.outer_radius = 0.55
  torus.rings = 24
  torus.ring_segments = 10
  _ring_mesh.mesh = torus
  _ring_mesh.rotation_degrees.x = 90.0
  _ring_mesh.scale = Vector3.ONE * core_scale
  var ring_mat := StandardMaterial3D.new()
  ring_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.8)
  ring_mat.emission_enabled = true
  ring_mat.emission = Color(0.5, 1.0, 1.0) * 1.2
  ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  _ring_mesh.material_override = ring_mat
  add_child(_ring_mesh)

  # Status label — progress + commodity. Visible at SYSTEM and
  # closer; hidden at galaxy-wide zoom so the label doesn't clutter.
  _progress_label = Label3D.new()
  _progress_label.position = LABEL_OFFSET
  _progress_label.modulate = Color(0.7, 1.0, 1.0)
  _progress_label.pixel_size = 0.005
  _progress_label.font_size = 24
  _progress_label.outline_size = 8
  _progress_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
  add_child(_progress_label)

  GameState.zoom_changed.connect(_on_zoom_changed)
  _on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)


func _refresh_progress_display(progress: float) -> void:
  var pct: int = int(progress * 100.0)
  var commodity: String = str(site_data.get("commodity", ""))
  var facility_type: String = str(site_data.get("facility_type", "?"))
  _progress_label.text = "%s\n%d%%" % [facility_type.capitalize(), pct]

  # Ring glows brighter as the site approaches completion.
  if _ring_mesh:
    var mat := _ring_mesh.material_override as StandardMaterial3D
    if mat:
      var intensity := 0.6 + progress * 0.8
      mat.emission = Color(0.5, 1.0, 1.0) * intensity
      # Also scale the ring slightly with progress so the visual
      # growth matches the semantic "this is being built up".
      var s := BASE_SCALE * (1.0 + progress * 0.3)
      _ring_mesh.scale = Vector3.ONE * s


func _on_zoom_changed(tier: int, _raw: float) -> void:
  if _progress_label:
    _progress_label.visible = (tier <= GameState.ZoomTier.SYSTEM)
