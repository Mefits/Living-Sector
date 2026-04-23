extends Node3D
class_name NebulaField

## Cosmetic nebula backdrop sitting below the Y=0 play plane.
##
## The sim doesn't know or care about these — they're pure client
## decoration. Layout is deterministic from a single seed derived
## from the current save file's DB path (see `main.gd::_nebula_seed`),
## so each save keeps a consistent starscape across restarts without
## needing anything persisted server-side.
##
## Rendering is cheap: each nebula is one SphereMesh + additive shader.
## Default count is small (8) because the shader does FBM + domain-warp
## in the fragment stage, so fill rate matters more than draw calls.


const ProceduralNebulaScript := preload(
  "res://scripts/tools/procedural_nebula.gd"
)

## Depth below the play plane. The isometric camera (−70° tilt) still
## sees nebulas at this Y because the view ray angles down past Y=0.
## Pushed deep so nebulas read as genuinely distant backdrop rather
## than floating just under the ships; the per-nebula jitter keeps
## them from landing on a single flat layer.
const FIELD_Y := -200.0
const FIELD_Y_JITTER := 60.0

## Horizontal spread in world units (universe_units × SCALE_FACTOR=10).
## The three default systems span roughly 0..400; 1400 radius frames
## them generously and gives parallax room as the camera pans.
const FIELD_RADIUS_WORLD := 1400.0

## Inset from the camera's near-field so a nebula doesn't pop right
## over a ship. Nebulas dropped inside this ring get pushed outward.
const INSET_RADIUS_WORLD := 120.0

## Bigger than a close-up playground nebula because these live far
## behind the action. Sizes scale with FIELD_Y — a distant cloud
## needs to be physically bigger to subtend the same visual angle.
const NEBULA_COUNT := 10
const RADIUS_MIN := 90.0
const RADIUS_MAX := 220.0

## Layout grid. Jittered-grid placement beats pure uniform RNG for
## coverage: uniform samples cluster often enough that you'll see 3
## neighbours in one quadrant and empty gaps elsewhere. Splitting the
## disc into a 4×3 grid and shuffling cells guarantees spread; the
## in-cell jitter keeps it from reading as a literal grid.
const GRID_COLS := 4
const GRID_ROWS := 3

## A handful of sci-fi palettes the seed rolls through. Each is a
## (primary, secondary) pair feeding the shader's two-colour mix.
const PALETTES: Array = [
  {"primary": Color(0.80, 0.35, 0.95), "secondary": Color(0.25, 0.60, 1.00)},
  {"primary": Color(0.95, 0.45, 0.30), "secondary": Color(0.90, 0.80, 0.35)},
  {"primary": Color(0.30, 0.90, 0.80), "secondary": Color(0.20, 0.50, 0.90)},
  {"primary": Color(0.95, 0.35, 0.55), "secondary": Color(0.50, 0.25, 0.85)},
  {"primary": Color(0.35, 0.80, 0.50), "secondary": Color(0.85, 0.90, 0.40)},
  {"primary": Color(0.25, 0.55, 1.00), "secondary": Color(0.75, 0.30, 0.85)},
]


func generate(seed_val: int) -> void:
  ## Rebuild the field deterministically from `seed_val`. Safe to call
  ## more than once — any existing nebulas are freed first.
  for c in get_children():
    c.queue_free()

  var rng := RandomNumberGenerator.new()
  # abs() because RNG seed is interpreted as unsigned; signed int.hash()
  # can return a negative. We just want deterministic bits.
  rng.seed = absi(seed_val)

  var cells := _shuffled_cells(rng)
  var placed := 0
  for cell in cells:
    if placed >= NEBULA_COUNT:
      break
    var pos := _pick_cell_position(cell, rng)
    if pos == Vector3.INF:
      continue  # cell center fell inside the inset ring, skip it
    var neb := ProceduralNebulaScript.new()
    neb.position = pos
    placed += 1
    neb.radius = rng.randf_range(RADIUS_MIN, RADIUS_MAX)
    neb.shape_scale = Vector3(
      rng.randf_range(0.8, 1.6),
      rng.randf_range(0.25, 0.7),  # flattened — reads as sheet-like
      rng.randf_range(0.8, 1.6),
    )

    var palette: Dictionary = PALETTES[rng.randi() % PALETTES.size()]
    neb.primary_color = palette["primary"]
    neb.secondary_color = palette["secondary"]

    neb.density = rng.randf_range(0.7, 1.3)
    neb.brightness = rng.randf_range(1.3, 2.2)
    neb.noise_frequency = rng.randf_range(1.0, 2.0)
    neb.noise_warp = rng.randf_range(0.5, 1.1)
    neb.wisp_strength = rng.randf_range(0.5, 1.1)
    # Keep radial_falloff ≥ 4.9 and density_threshold ≥ 0.62 or the
    # cloud reads as a solid disc instead of volumetric. Upper bounds
    # are where the shader starts over-carving — beyond those you get
    # sparse fragments instead of a cohesive cloud.
    neb.radial_falloff = rng.randf_range(5.0, 6.5)
    neb.density_threshold = rng.randf_range(0.63, 0.72)
    neb.color_mix_shift = rng.randf_range(0.35, 0.65)

    # Each nebula gets its own sub-seed so shader noise fields don't
    # line up — otherwise clones of the same cloud appear at each
    # position.
    neb.nebula_seed = rng.randi()

    # Glacial tumble. These are light-year-scale clouds — anything
    # visually rotating during a play session breaks the illusion.
    # Values here are per-second rotation in radians; at ~0.002 a
    # full turn takes over 50 minutes.
    neb.tumble = Vector3(
      rng.randf_range(-0.002, 0.002),
      rng.randf_range(-0.002, 0.002),
      rng.randf_range(-0.002, 0.002),
    )

    add_child(neb)


func _shuffled_cells(rng: RandomNumberGenerator) -> Array:
  ## Build every grid cell as a (center_x, center_z) pair, then
  ## shuffle deterministically. Caller iterates until NEBULA_COUNT
  ## placements succeed — extra cells cover the case where a cell
  ## center happens to land inside INSET_RADIUS_WORLD and gets
  ## skipped.
  var cell_w := (2.0 * FIELD_RADIUS_WORLD) / float(GRID_COLS)
  var cell_h := (2.0 * FIELD_RADIUS_WORLD) / float(GRID_ROWS)
  var cells: Array = []
  for row in GRID_ROWS:
    for col in GRID_COLS:
      var cx := -FIELD_RADIUS_WORLD + cell_w * (float(col) + 0.5)
      var cz := -FIELD_RADIUS_WORLD + cell_h * (float(row) + 0.5)
      cells.append(Vector4(cx, cz, cell_w, cell_h))
  # Fisher-Yates with the seeded RNG so each save keeps a stable
  # shuffle but different saves get different distributions.
  for i in range(cells.size() - 1, 0, -1):
    var j := rng.randi_range(0, i)
    var tmp: Variant = cells[i]
    cells[i] = cells[j]
    cells[j] = tmp
  return cells


func _pick_cell_position(
  cell: Vector4, rng: RandomNumberGenerator
) -> Vector3:
  ## Place within a single cell with bounded jitter. Jitter is 0.35×
  ## cell half-size — enough to hide the grid, small enough that cells
  ## don't overlap and re-cluster. Rejects if the result falls inside
  ## INSET_RADIUS_WORLD (returns INF so caller skips the cell).
  var cx: float = cell.x
  var cz: float = cell.y
  var cw: float = cell.z
  var ch: float = cell.w
  var jx := rng.randf_range(-cw * 0.35, cw * 0.35)
  var jz := rng.randf_range(-ch * 0.35, ch * 0.35)
  var x := cx + jx
  var z := cz + jz
  if (x * x + z * z) < (INSET_RADIUS_WORLD * INSET_RADIUS_WORLD):
    return Vector3.INF
  var y := FIELD_Y + rng.randf_range(-FIELD_Y_JITTER, FIELD_Y_JITTER)
  return Vector3(x, y, z)
