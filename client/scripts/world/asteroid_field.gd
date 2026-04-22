class_name AsteroidField
extends Node3D

## GPU-instanced cloud of small asteroids around a central point. One
## ArrayMesh generated via `ProceduralAsteroid.build_mesh`, rendered N
## times through `MultiMeshInstance3D` with per-instance position /
## rotation / scale. Per-instance scale gives the only shape variety —
## same silhouette, rotated and resized — which is enough at field
## ranges. Instance count is tiny by GPU standards (≤ 100) so this costs
## essentially one draw call.
##
## Two scatter layouts:
##   - "shell"   : spherical shell around origin, clear of `inner_world`.
##                 Use for named asteroid bodies (near-earth, kuiper) —
##                 a halo of rubble around the lead rock.
##   - "disc"    : flat ring in the XZ plane with small Y jitter. Use
##                 for belt-type bodies — reads as orbiting cluster.
##
## Seeded from `(body_id + "_field")` hash so layout is stable across
## runs and ships orbit through the same rubble every time.

const DEFAULT_PARAMS := {
  "count": 12,
  "spread_world": 1.0,
  "inner_world": 0.0,
  "size_min_world": 0.05,
  "size_max_world": 0.12,
  "layout": "shell",        # "shell" | "disc"
  "disc_thickness_world": 0.1,
  # Simpler meshes than the lead rock — satellites don't need detail.
  "mesh_radial_segments": 10,
  "mesh_rings": 6,
  "mesh_deformation": 0.45,  # lumpier than lead
  "mesh_deform_frequency": 1.8,
  "mesh_deform_octaves": 2,
}

var _mmi: MultiMeshInstance3D


func setup(base_cfg: Dictionary, seed_int: int, params: Dictionary) -> void:
  var p: Dictionary = DEFAULT_PARAMS.duplicate(true)
  p.merge(params, true)

  var count: int = int(p["count"])
  if count <= 0:
    return

  # One shared mesh — per-instance scale + rotation keeps the silhouettes
  # from looking stamped even though the underlying shape is identical.
  var base_mesh: ArrayMesh = ProceduralAsteroid.build_mesh(
    seed_int,
    int(p["mesh_radial_segments"]),
    int(p["mesh_rings"]),
    1.0,  # unit radius; per-instance scale sizes each rock
    float(p["mesh_deformation"]),
    float(p["mesh_deform_frequency"]),
    int(p["mesh_deform_octaves"]),
    Vector3.ONE,
  )
  var mat: ShaderMaterial = ProceduralAsteroid.build_material_from_cfg(
    base_cfg, seed_int
  )

  var mm := MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.mesh = base_mesh
  mm.instance_count = count  # must happen before set_instance_transform

  var rng := RandomNumberGenerator.new()
  rng.seed = seed_int

  var layout: String = String(p["layout"])
  var inner: float = float(p["inner_world"])
  var spread: float = float(p["spread_world"])
  var s_min: float = float(p["size_min_world"])
  var s_max: float = float(p["size_max_world"])
  var thick: float = float(p["disc_thickness_world"])

  for i in range(count):
    var pos := _scatter_position(
      layout, inner, spread, thick, rng
    )
    var rot := Basis()
    rot = rot.rotated(Vector3.RIGHT, rng.randf() * TAU)
    rot = rot.rotated(Vector3.UP, rng.randf() * TAU)
    rot = rot.rotated(Vector3.FORWARD, rng.randf() * TAU)
    var size := rng.randf_range(s_min, s_max)
    var xform := Transform3D(rot.scaled(Vector3(size, size, size)), pos)
    mm.set_instance_transform(i, xform)

  _mmi = MultiMeshInstance3D.new()
  _mmi.multimesh = mm
  _mmi.material_override = mat
  add_child(_mmi)


static func _scatter_position(
  layout: String,
  inner: float, spread: float, thick: float,
  rng: RandomNumberGenerator
) -> Vector3:
  if layout == "disc":
    # Uniform area on a disc: r = spread * sqrt(u). Push rocks that land
    # inside `inner` back out past the clear zone so they don't clip the
    # lead body (belts have no lead; inner is usually 0 there anyway).
    var u := rng.randf()
    var r := sqrt(u) * spread
    if r < inner:
      r = inner + rng.randf() * maxf(spread - inner, 0.0001)
    var theta := rng.randf() * TAU
    var y := (rng.randf() - 0.5) * 2.0 * thick
    return Vector3(r * cos(theta), y, r * sin(theta))
  # Default: spherical shell. Uniform-on-sphere via acos sampling.
  var u := rng.randf()
  var v := rng.randf()
  var phi := acos(2.0 * v - 1.0)
  var theta := TAU * u
  # Uniform-in-volume for the radius would clump at the outside; use a
  # linear interp so rocks spread evenly across the shell thickness.
  var r := lerpf(maxf(inner, 0.0001), spread, rng.randf())
  return Vector3(
    r * sin(phi) * cos(theta),
    r * cos(phi),
    r * sin(phi) * sin(theta),
  )
