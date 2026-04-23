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
const FIELD_Y := -35.0
const FIELD_Y_JITTER := 12.0

## Horizontal spread in world units (universe_units × SCALE_FACTOR=10).
## The three default systems span roughly 0..400; 800 radius frames
## them comfortably and gives parallax room as the camera pans.
const FIELD_RADIUS_WORLD := 800.0

## Inset from the camera's near-field so a nebula doesn't pop right
## over a ship. Nebulas dropped inside this ring get pushed outward.
const INSET_RADIUS_WORLD := 40.0

const NEBULA_COUNT := 10
const RADIUS_MIN := 35.0
const RADIUS_MAX := 90.0

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

  for i in NEBULA_COUNT:
    var neb := ProceduralNebulaScript.new()
    neb.position = _pick_position(rng)
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
    neb.radial_falloff = rng.randf_range(2.2, 3.4)
    neb.density_threshold = rng.randf_range(0.05, 0.18)
    neb.color_mix_shift = rng.randf_range(0.35, 0.65)

    # Each nebula gets its own sub-seed so shader noise fields don't
    # line up — otherwise clones of the same cloud appear at each
    # position.
    neb.nebula_seed = rng.randi()

    # Tiny tumble so the field feels alive. Slow enough that zoomed-
    # out views still read as "static backdrop".
    neb.tumble = Vector3(
      rng.randf_range(-0.015, 0.015),
      rng.randf_range(-0.015, 0.015),
      rng.randf_range(-0.015, 0.015),
    )

    add_child(neb)


func _pick_position(rng: RandomNumberGenerator) -> Vector3:
  ## Uniform disc sample over the field radius, rejecting points inside
  ## `INSET_RADIUS_WORLD` so nothing spawns right under origin.
  var x := 0.0
  var z := 0.0
  for attempt in 8:
    x = rng.randf_range(-FIELD_RADIUS_WORLD, FIELD_RADIUS_WORLD)
    z = rng.randf_range(-FIELD_RADIUS_WORLD, FIELD_RADIUS_WORLD)
    if (x * x + z * z) >= (INSET_RADIUS_WORLD * INSET_RADIUS_WORLD):
      break
  var y := FIELD_Y + rng.randf_range(-FIELD_Y_JITTER, FIELD_Y_JITTER)
  return Vector3(x, y, z)
