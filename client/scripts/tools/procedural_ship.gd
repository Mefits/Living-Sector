@tool
extends Node3D
class_name ProceduralShip

## Kitbashed low-poly ship. A class template defines which parts to use
## and their parameter ranges; the seed picks within those ranges; the
## faction supplies a 3-colour palette (hull / trim / accent). Same
## (class, seed, faction) always renders the same ship.
##
## Parts are just primitives (BoxMesh, PrismMesh, CylinderMesh) — each
## on its own MeshInstance3D with a ShaderMaterial from
## `res://shaders/procedural_ship.gdshader`. Flat shading via fragment
## derivatives gives the blocky low-poly read.
##
## Orientation: -Z is forward (Godot camera convention). Cockpit sits
## toward −Z, engines at +Z. If the integrator uses a different
## convention, rotate 180° at the parent.

const SHADER_PATH := "res://shaders/procedural_ship.gdshader"

# Nose tip width/height as fractions of hull — sharper for faster-reading
# ships, blunter for haulers. Multiplied into hull_width/height to get
# the frustum's forward face dimensions; 0 = needle point.
const NOSE_TIP_COURIER := 0.10
const NOSE_TIP_FREIGHTER := 0.45
const NOSE_TIP_HAULER := 0.70

# Running-light emission — bright enough to bloom against the glow env.
const RUNNING_LIGHT_EMISSION := 4.0

enum ShipClass { COURIER, FREIGHTER, HAULER, TANKER, MINER }

## Six-tier size scale matching the Rust sim's `ShipSize` enum. We apply
## it as a uniform scale on the root Node3D so external code (eventually
## `ship.gd`) can still apply its own rendering scale on top by wrapping
## the ProceduralShip in a parent pivot.
enum ShipSize { TINY, SMALL, MEDIUM, LARGE, HUGE, MASSIVE }

const SIZE_SCALES := {
  ShipSize.TINY:    0.50,
  ShipSize.SMALL:   0.75,
  ShipSize.MEDIUM:  1.00,
  ShipSize.LARGE:   1.40,
  ShipSize.HUGE:    1.90,
  ShipSize.MASSIVE: 2.50,
}

## At-home size per class — matches `default_size` in the Rust config.
## Used by the playground to reset size when the user changes class so
## each class shows at its intended scale by default.
const CLASS_DEFAULT_SIZE := {
  ShipClass.COURIER:   ShipSize.SMALL,
  ShipClass.FREIGHTER: ShipSize.MEDIUM,
  ShipClass.HAULER:    ShipSize.HUGE,
  ShipClass.TANKER:    ShipSize.LARGE,
  ShipClass.MINER:     ShipSize.SMALL,
}

# ---- Faction palettes -----------------------------------------------------
# hull = dominant color; trim = cockpit + accents; accent = engine glow.
const FACTION_PALETTES := {
  "terran-authority": {
    "hull":   Color(0.85, 0.90, 0.92),
    "trim":   Color(0.08, 0.40, 0.58),
    "accent": Color(1.0, 0.82, 0.35),
  },
  "mars-syndicate": {
    "hull":   Color(0.55, 0.24, 0.16),
    "trim":   Color(0.22, 0.10, 0.08),
    "accent": Color(1.0, 0.50, 0.15),
  },
  "belt-coalition": {
    "hull":   Color(0.72, 0.64, 0.34),
    "trim":   Color(0.30, 0.24, 0.16),
    "accent": Color(1.0, 0.88, 0.45),
  },
  "frontier-ventures": {
    "hull":   Color(0.50, 0.60, 0.42),
    "trim":   Color(0.28, 0.38, 0.22),
    "accent": Color(0.95, 0.82, 0.40),
  },
  "crucible-mining": {
    "hull":   Color(0.26, 0.30, 0.34),
    "trim":   Color(0.45, 0.20, 0.10),
    "accent": Color(1.0, 0.40, 0.15),
  },
  "the-doughtys": {
    "hull":   Color(0.70, 0.50, 0.80),
    "trim":   Color(0.35, 0.20, 0.50),
    "accent": Color(1.0, 0.80, 0.30),
  },
  "independent": {
    "hull":   Color(0.58, 0.58, 0.60),
    "trim":   Color(0.28, 0.28, 0.30),
    "accent": Color(0.90, 0.90, 0.95),
  },
}

# ---- Class templates ------------------------------------------------------
# Value ranges are [min, max]; scalars are sampled per-seed. Positions /
# sizes are in local world units. All -Z is forward.
const CLASS_TEMPLATES := {
  ShipClass.COURIER: {
    "hull_length":     [1.8, 2.2],
    "hull_width":      [0.38, 0.50],
    "hull_height":     [0.28, 0.38],
    "nose_length":     [0.45, 0.65],     # out past the hull front
    "nose_tip_frac":   NOSE_TIP_COURIER,
    "cockpit_length":  [0.35, 0.50],
    "cockpit_width":   [0.30, 0.40],
    "cockpit_height":  [0.18, 0.26],
    "cockpit_z_frac":  [-0.35, -0.15],   # along hull (−=front)
    "engine_count":    2,
    "engine_radius":   [0.10, 0.16],
    "engine_length":   [0.40, 0.55],
    "engine_x_offset": [0.18, 0.28],
    "engine_pylon":    true,
    "nozzle_radius":   [0.06, 0.09],
    "nozzle_length":   [0.15, 0.22],
    "wing_count":      2,
    "wing_length":     [0.40, 0.60],     # along Z
    "wing_span":       [0.35, 0.65],     # outward from hull
    "wing_thickness":  [0.05, 0.07],
    "wing_z_frac":     [-0.10, 0.20],
    "wing_dihedral":   [-6.0, 6.0],      # degrees
    "wingtip_nacelle": true,
    "cargo_pod_count": 0,
    "hull_trim":       true,
    "hull_trim_width": [0.20, 0.30],     # fraction of hull_length
    "running_lights":  true,
  },
  ShipClass.FREIGHTER: {
    "hull_length":     [2.6, 3.2],
    "hull_width":      [0.70, 0.90],
    "hull_height":     [0.55, 0.70],
    "nose_length":     [0.35, 0.55],
    "nose_tip_frac":   NOSE_TIP_FREIGHTER,
    "cockpit_length":  [0.55, 0.75],
    "cockpit_width":   [0.45, 0.60],
    "cockpit_height":  [0.28, 0.36],
    "cockpit_z_frac":  [-0.30, -0.15],
    "engine_count":    2,
    "engine_radius":   [0.16, 0.24],
    "engine_length":   [0.50, 0.70],
    "engine_x_offset": [0.28, 0.38],
    "engine_pylon":    true,
    "nozzle_radius":   [0.10, 0.14],
    "nozzle_length":   [0.20, 0.28],
    "wing_count":      0,
    "wingtip_nacelle": false,
    "cargo_pod_count": 2,
    "cargo_pod_size":  [0.50, 0.75],     # along Z — cylinder length
    "cargo_pod_width": [0.14, 0.20],     # cylinder radius for pods
    "cargo_pod_x_offset": [0.42, 0.52],
    "cargo_pod_z_frac":[0.00, 0.20],
    "hull_trim":       true,
    "hull_trim_width": [0.25, 0.35],
    "running_lights":  true,
  },
  ShipClass.HAULER: {
    "hull_length":     [3.2, 4.0],
    "hull_width":      [0.95, 1.20],
    "hull_height":     [0.75, 0.95],
    "nose_length":     [0.30, 0.50],
    "nose_tip_frac":   NOSE_TIP_HAULER,
    "cockpit_length":  [0.55, 0.75],
    "cockpit_width":   [0.50, 0.70],
    "cockpit_height":  [0.28, 0.36],
    "cockpit_z_frac":  [-0.40, -0.25],
    "engine_count":    4,                 # 2×2 grid at rear
    "engine_radius":   [0.18, 0.26],
    "engine_length":   [0.55, 0.75],
    "engine_x_offset": [0.32, 0.42],
    "engine_y_offset": [0.18, 0.28],
    "engine_pylon":    true,
    "nozzle_radius":   [0.12, 0.17],
    "nozzle_length":   [0.22, 0.32],
    "wing_count":      0,
    "wingtip_nacelle": false,
    "cargo_pod_count": 4,
    "cargo_pod_size":  [0.70, 1.00],
    "cargo_pod_width": [0.16, 0.22],
    "cargo_pod_x_offset": [0.60, 0.72],
    "cargo_pod_z_frac":[-0.15, 0.25],
    "hull_trim":       true,
    "hull_trim_width": [0.30, 0.40],
    "running_lights":  true,
  },
  ShipClass.TANKER: {
    # Narrow hull overshadowed by two big cylindrical tanks. Reads as
    # "fuel hauler" more than "cargo ship".
    "hull_length":     [2.4, 3.0],
    "hull_width":      [0.55, 0.70],
    "hull_height":     [0.50, 0.65],
    "nose_length":     [0.25, 0.40],
    "nose_tip_frac":   0.55,
    "cockpit_length":  [0.45, 0.60],
    "cockpit_width":   [0.38, 0.48],
    "cockpit_height":  [0.22, 0.30],
    "cockpit_z_frac":  [-0.35, -0.25],
    "engine_count":    2,
    "engine_radius":   [0.20, 0.28],
    "engine_length":   [0.55, 0.70],
    "engine_x_offset": [0.32, 0.42],
    "engine_pylon":    true,
    "nozzle_radius":   [0.13, 0.17],
    "nozzle_length":   [0.25, 0.32],
    "wing_count":      0,
    "wingtip_nacelle": false,
    "cargo_pod_count": 2,                 # the dominant silhouette
    "cargo_pod_size":  [1.20, 1.60],      # very long
    "cargo_pod_width": [0.25, 0.32],      # fat radius
    "cargo_pod_x_offset": [0.52, 0.62],
    "cargo_pod_z_frac":[-0.05, 0.10],
    "hull_trim":       true,
    "hull_trim_width": [0.25, 0.35],
    "running_lights":  true,
  },
  ShipClass.MINER: {
    # Chunky industrial silhouette. Front cutter replaces the prism nose;
    # small side ore pods read as the haul.
    "hull_length":     [1.8, 2.3],
    "hull_width":      [0.55, 0.70],
    "hull_height":     [0.50, 0.65],
    "mining_tool":     true,              # swap nose prism for cutter head
    "cutter_length":   [0.55, 0.80],
    "cutter_radius":   [0.20, 0.28],
    "cockpit_length":  [0.40, 0.55],
    "cockpit_width":   [0.35, 0.48],
    "cockpit_height":  [0.24, 0.32],
    "cockpit_z_frac":  [-0.30, -0.15],
    "engine_count":    2,
    "engine_radius":   [0.14, 0.20],
    "engine_length":   [0.40, 0.55],
    "engine_x_offset": [0.24, 0.33],
    "engine_pylon":    true,
    "nozzle_radius":   [0.09, 0.13],
    "nozzle_length":   [0.18, 0.25],
    "wing_count":      0,
    "wingtip_nacelle": false,
    "cargo_pod_count": 2,
    "cargo_pod_size":  [0.35, 0.55],
    "cargo_pod_width": [0.11, 0.15],
    "cargo_pod_x_offset": [0.42, 0.50],
    "cargo_pod_z_frac":[-0.05, 0.15],
    "hull_trim":       true,
    "hull_trim_width": [0.20, 0.30],
    "running_lights":  true,
  },
}

# ---- Exported state -------------------------------------------------------
@export var ship_class: ShipClass = ShipClass.COURIER:
  set(v): ship_class = v; _rebuild()

@export var ship_size: ShipSize = ShipSize.MEDIUM:
  set(v): ship_size = v; _apply_size()

@export var ship_seed: int = 42:
  set(v): ship_seed = v; _rebuild()

@export var faction_id: String = "terran-authority":
  set(v): faction_id = v; _rebuild()

@export_range(6, 32, 1) var engine_segments: int = 10:
  set(v): engine_segments = v; _rebuild()


func _ready() -> void:
  _rebuild()
  _apply_size()


func _apply_size() -> void:
  ## Uniform scale on the root. Anything that wraps a ProceduralShip in
  ## a parent Node3D can apply its own scale on top without fighting us.
  var mult: float = float(SIZE_SCALES.get(ship_size, 1.0))
  scale = Vector3(mult, mult, mult)


func _rebuild() -> void:
  # Wipe and redo. Ship rebuilds are cheap — a handful of primitive meshes.
  for c in get_children():
    c.queue_free()
  # When the setter fires during @export-default init, we might be
  # pre-tree. Nothing to build yet; _ready will run us again.
  if not is_inside_tree():
    return

  var tpl: Dictionary = CLASS_TEMPLATES[ship_class]
  var pal: Dictionary = FACTION_PALETTES.get(
    faction_id, FACTION_PALETTES["independent"]
  )
  var rng := RandomNumberGenerator.new()
  rng.seed = ship_seed

  # Sample all the per-seed values up-front so downstream builders don't
  # have to know the template structure.
  var params := _sample_template(tpl, rng)

  _build_hull(params, pal)
  if bool(tpl.get("mining_tool", false)):
    _build_mining_cutter(params, pal, tpl)
  else:
    _build_nose(params, pal, tpl)
  if bool(tpl.get("hull_trim", false)):
    _build_hull_trim(params, pal, tpl)
  _build_cockpit(params, pal)
  _build_engines(params, pal, tpl)
  if int(tpl.get("wing_count", 0)) > 0:
    _build_wings(params, pal, tpl)
  if int(tpl.get("cargo_pod_count", 0)) > 0:
    _build_cargo_pods(params, pal, tpl, rng)
  if bool(tpl.get("running_lights", false)):
    _build_running_lights(params, pal, tpl)


# ---------------------------------------------------------------------------
# Parameter sampling
# ---------------------------------------------------------------------------

func _sample_template(tpl: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
  ## Resolve every [min,max] range in the template into a scalar sampled
  ## from `rng`. Non-range values (ints, scalars) pass through.
  var out: Dictionary = {}
  for key in tpl.keys():
    var v = tpl[key]
    if v is Array and v.size() == 2 and (v[0] is float or v[0] is int):
      out[key] = rng.randf_range(float(v[0]), float(v[1]))
    else:
      out[key] = v
  return out


# ---------------------------------------------------------------------------
# Part builders
# ---------------------------------------------------------------------------

static func _build_frustum_mesh(
  base_w: float, base_h: float,
  tip_w: float, tip_h: float,
  length: float,
) -> ArrayMesh:
  ## Rectangular frustum (truncated pyramid). Base face at +Z (full size);
  ## tip face at −Z (scaled to tip_w × tip_h). When tip_w and tip_h are
  ## near zero you get a pointed pyramid; at ~0.7 you get a blunt nose
  ## block. Flat-shaded per-face so it matches the rest of the ship.
  var st := SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)

  var bw := base_w * 0.5
  var bh := base_h * 0.5
  var tw := tip_w * 0.5
  var th := tip_h * 0.5
  var hl := length * 0.5

  # 8 corners: B* = base (+Z), T* = tip (−Z). Naming: X/Y axis ± suffix.
  var B_nn := Vector3(-bw, -bh,  hl)
  var B_pn := Vector3( bw, -bh,  hl)
  var B_pp := Vector3( bw,  bh,  hl)
  var B_np := Vector3(-bw,  bh,  hl)
  var T_nn := Vector3(-tw, -th, -hl)
  var T_pn := Vector3( tw, -th, -hl)
  var T_pp := Vector3( tw,  th, -hl)
  var T_np := Vector3(-tw,  th, -hl)

  # Six faces, wound CCW from outside so the derived normal points out.
  _emit_flat_quad(st, B_nn, B_pn, B_pp, B_np)  # back face (+Z)
  _emit_flat_quad(st, T_pn, T_nn, T_np, T_pp)  # front face (−Z)
  _emit_flat_quad(st, B_np, B_pp, T_pp, T_np)  # top face (+Y)
  _emit_flat_quad(st, B_pn, B_nn, T_nn, T_pn)  # bottom face (−Y)
  _emit_flat_quad(st, B_pp, B_pn, T_pn, T_pp)  # right face (+X)
  _emit_flat_quad(st, B_nn, B_np, T_np, T_nn)  # left face (−X)

  return st.commit()


static func _emit_flat_quad(
  st: SurfaceTool,
  a: Vector3, b: Vector3, c: Vector3, d: Vector3
) -> void:
  ## Emit a quad as two triangles with a single shared flat normal
  ## computed from the quad's winding. CCW order = normal points outward.
  var n := (b - a).cross(c - a).normalized()
  st.set_normal(n)
  st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
  st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


func _build_hull(p: Dictionary, pal: Dictionary) -> void:
  var hull := BoxMesh.new()
  hull.size = Vector3(
    float(p["hull_width"]),
    float(p["hull_height"]),
    float(p["hull_length"]),
  )
  var mi := _make_part("Hull", hull, pal["hull"], 0.0)
  # Hull centered on origin — every other part references this center.
  add_child(mi)


func _build_cockpit(p: Dictionary, pal: Dictionary) -> void:
  # PrismMesh gives the triangular canopy silhouette. Its triangle is in
  # XY, extruded along Z — which matches our hull (length along Z), so
  # the peaked edge runs fore-aft down the top of the ship.
  var prism := PrismMesh.new()
  prism.size = Vector3(
    float(p["cockpit_width"]),
    float(p["cockpit_height"]),
    float(p["cockpit_length"]),
  )
  prism.left_to_right = 0.5  # symmetric peak
  var mi := _make_part("Cockpit", prism, pal["trim"], 0.0)
  # Prism's flat bottom at y=-height/2 sits on the hull top at y=+height/2.
  # Explicit float types — dict access returns Variant, so `:=` can't
  # infer. Same story for every dict-derived position in this file.
  var y: float = float(p["hull_height"]) * 0.5 + float(p["cockpit_height"]) * 0.5
  var z: float = float(p["hull_length"]) * float(p["cockpit_z_frac"])
  mi.position = Vector3(0, y, z)
  add_child(mi)


func _build_engines(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Mirrored pair (count=2) or 2×2 grid (count=4). Engines sit at the
  ## rear of the hull and their nozzles extend further back with emission.
  var count: int = int(tpl.get("engine_count", 2))
  var r: float = float(p["engine_radius"])
  var elen: float = float(p["engine_length"])
  var x_off: float = float(p["engine_x_offset"])
  var rear_z: float = float(p["hull_length"]) * 0.5
  # Engine center sits half-inside / half-outside the hull tail, so the
  # thrust tube visibly protrudes without floating in space.
  var engine_z: float = rear_z + elen * 0.25

  # Typed arrays so loop variables resolve to float, not Variant — the
  # parser can't infer float through dict/array-literal chains.
  var y_positions: Array[float] = [0.0]
  if count >= 4:
    var y_off: float = float(p.get("engine_y_offset", 0.22))
    y_positions = [-y_off, y_off]
  var x_positions: Array[float] = [-x_off, x_off]

  var pylon: bool = bool(tpl.get("engine_pylon", false))
  for y: float in y_positions:
    for x: float in x_positions:
      _spawn_engine(Vector3(x, y, engine_z), r, elen, p, pal, pylon)


func _spawn_engine(
  pos: Vector3, radius: float, length: float,
  p: Dictionary, pal: Dictionary, with_pylon: bool = true,
) -> void:
  var cyl := CylinderMesh.new()
  cyl.top_radius = radius
  cyl.bottom_radius = radius
  cyl.height = length
  cyl.radial_segments = engine_segments
  cyl.rings = 1
  var mi := _make_part("Engine", cyl, pal["hull"], 0.0)
  # CylinderMesh axis is +Y by default; rotate so the cylinder lies along Z.
  mi.rotation = Vector3(PI * 0.5, 0, 0)
  mi.position = pos
  add_child(mi)

  # Nozzle: bell-shaped cone poking out the back, emission for glow.
  # bottom_radius slightly larger than top gives a classic outward flare.
  var nozzle := CylinderMesh.new()
  var nr: float = float(p["nozzle_radius"])
  var nl: float = float(p["nozzle_length"])
  nozzle.top_radius = nr * 0.55          # tapers outward
  nozzle.bottom_radius = nr
  nozzle.height = nl
  nozzle.radial_segments = engine_segments
  nozzle.rings = 1
  var nm := _make_part("Nozzle", nozzle, pal["accent"], 2.5)
  nm.rotation = Vector3(PI * 0.5, 0, 0)
  nm.position = pos + Vector3(0, 0, length * 0.5 + nl * 0.5)
  add_child(nm)

  if with_pylon:
    # Short box bridging the hull flank and the engine's inner face.
    # Only draw when there's a visible gap — haulers' 2×2 engines are
    # mounted inside the hull width, so their "pylon" would just z-fight
    # the hull. 0.04 minimum gap keeps tiny cosmetic pylons suppressed.
    var hull_edge_x: float = float(p["hull_width"]) * 0.5
    var engine_inner_x: float = abs(pos.x) - radius
    var gap: float = engine_inner_x - hull_edge_x
    if gap > 0.04:
      var sign_x: float = signf(pos.x)
      var pylon := BoxMesh.new()
      pylon.size = Vector3(gap, radius * 0.85, length * 0.55)
      var pm := _make_part("EnginePylon", pylon, pal["hull"], 0.0)
      pm.position = Vector3(
        sign_x * (hull_edge_x + gap * 0.5),
        pos.y,
        pos.z - length * 0.10,   # offset forward so the engine nozzle
                                 # reads as protruding past the pylon
      )
      add_child(pm)


func _build_wings(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Flat mirrored pair. Dihedral rotates each wing around +Z so the tips
  ## angle up (positive) or down (negative). Keeps the ship readable as a
  ## small craft rather than a flying brick.
  var wlen: float = float(p["wing_length"])
  var wspan: float = float(p["wing_span"])
  var wthick: float = float(p["wing_thickness"])
  var z: float = float(p["hull_length"]) * float(p["wing_z_frac"])
  var dihedral: float = deg_to_rad(float(p.get("wing_dihedral", 0.0)))
  var half_hull: float = float(p["hull_width"]) * 0.5
  var wing_x_center: float = half_hull + wspan * 0.5

  var nacelles: bool = bool(tpl.get("wingtip_nacelle", false))
  var sides: Array[float] = [-1.0, 1.0]
  for side: float in sides:
    var wing := BoxMesh.new()
    wing.size = Vector3(wspan, wthick, wlen)
    var mi := _make_part("Wing", wing, pal["hull"], 0.0)
    mi.position = Vector3(side * wing_x_center, 0, z)
    # Positive dihedral = tips up. Right wing (side=+1) rotates +X toward
    # +Y on +Z; left wing (side=-1) rotates -X toward +Y on -Z. Multiply
    # `side` through so both behave the same way.
    mi.rotation = Vector3(0, 0, side * dihedral)
    add_child(mi)

    if nacelles:
      # Small cylinder along Z at the wingtip — reads as a sensor pod or
      # weapon housing. Radius scales with wing thickness so it never
      # overwhelms the wing silhouette. We take the dihedral into account
      # so the nacelle sits flush with the wing tip rather than floating.
      var nac_r: float = wthick * 1.3
      var nac_len: float = wlen * 1.15
      var nac := CylinderMesh.new()
      nac.top_radius = nac_r
      nac.bottom_radius = nac_r
      nac.height = nac_len
      nac.radial_segments = 10
      nac.rings = 1
      var nm := _make_part("WingtipNacelle", nac, pal["trim"], 0.0)
      # Place at outer end of wing. Both wings tilt their outer tips up
      # by +dihedral × half-span (dihedral is absolute; each wing's own
      # rotation takes care of direction). Nacelle itself stays Z-aligned
      # — wingtip tanks/pods in real craft stay parallel to the fuselage.
      var tip_x: float = side * (wing_x_center + wspan * 0.5)
      var tip_y: float = (wspan * 0.5) * sin(dihedral)
      nm.rotation = Vector3(PI * 0.5, 0, 0)
      nm.position = Vector3(tip_x, tip_y, z)
      add_child(nm)


func _build_cargo_pods(
  p: Dictionary, pal: Dictionary, tpl: Dictionary,
  rng: RandomNumberGenerator
) -> void:
  ## Attached to the hull sides. For count=2, one pod per side. For
  ## count=4, two pods per side spaced along Z. Always mirrored; pods
  ## use trim colour to break up the hull silhouette visually.
  var count: int = int(tpl.get("cargo_pod_count", 0))
  var per_side: int = max(1, count / 2)
  var psize: float = float(p["cargo_pod_size"])
  var pwidth: float = float(p["cargo_pod_width"])
  var px_off: float = float(p["cargo_pod_x_offset"])
  var base_z: float = float(p["hull_length"]) * float(p["cargo_pod_z_frac"])

  var sides: Array[float] = [-1.0, 1.0]
  for side: float in sides:
    for i in range(per_side):
      # Distribute pods along Z within ±0.4 × hull_length from base_z
      var spacing: float = 0.0
      if per_side > 1:
        spacing = (float(i) - (float(per_side) - 1.0) * 0.5) \
                  * psize * 1.3
      # Cylinder tanks read as fuel/cargo tanks far better than boxes.
      # `cargo_pod_width` is now the cylinder radius. Rotate 90° around
      # X so the tank's long axis lies along Z (fore-aft, parallel hull).
      var pod := CylinderMesh.new()
      pod.top_radius = pwidth
      pod.bottom_radius = pwidth
      pod.height = psize
      pod.radial_segments = 12
      pod.rings = 1
      var mi := _make_part("CargoPod", pod, pal["trim"], 0.0)
      mi.rotation = Vector3(PI * 0.5, 0, 0)
      mi.position = Vector3(side * px_off, 0, base_z + spacing)
      add_child(mi)
      # End caps: small disks in accent color, flush against each end of
      # the tank. Sells the tank shape at low detail.
      _spawn_pod_cap(mi.position, pwidth, psize, pal, +1.0)
      _spawn_pod_cap(mi.position, pwidth, psize, pal, -1.0)


func _spawn_pod_cap(
  pod_pos: Vector3, pod_radius: float, pod_length: float,
  pal: Dictionary, sign_z: float
) -> void:
  # Thin disc-like cylinder (height = small fraction of radius) at one
  # end of the pod. Accent color reads as a port / coupling / sensor.
  var cap := CylinderMesh.new()
  cap.top_radius = pod_radius * 0.95
  cap.bottom_radius = pod_radius * 0.95
  cap.height = pod_radius * 0.25
  cap.radial_segments = 12
  cap.rings = 1
  var mi := _make_part("PodCap", cap, pal["accent"], 0.8)
  mi.rotation = Vector3(PI * 0.5, 0, 0)
  mi.position = pod_pos + Vector3(
    0, 0, sign_z * (pod_length * 0.5 + cap.height * 0.5)
  )
  add_child(mi)


func _build_nose(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Tapered frustum attached at the hull front. `nose_tip_frac` controls
  ## how sharp the point is: ~0.1 = fighter-like needle, ~0.7 = blunt
  ## hauler nose. Centered on the hull's cross-section so the frustum's
  ## wide face lines up flush with the hull front.
  var nose_len: float = float(p.get("nose_length", 0.4))
  if nose_len <= 0.0:
    return
  var tip_frac: float = float(tpl.get("nose_tip_frac", 0.3))
  var hw: float = float(p["hull_width"])
  var hh: float = float(p["hull_height"])
  var mesh := ProceduralShip._build_frustum_mesh(
    hw, hh,              # base = full hull cross-section
    hw * tip_frac,       # tip width
    hh * tip_frac,       # tip height
    nose_len,
  )
  var mi := _make_part("Nose", mesh, pal["hull"], 0.0)
  # Frustum base at +Z in local space; hull front at -Z in ship space.
  # Nose center sits one half-length past the hull front so the base
  # lines up with the hull's front face.
  mi.position = Vector3(
    0, 0, -float(p["hull_length"]) * 0.5 - nose_len * 0.5
  )
  add_child(mi)


func _build_hull_trim(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Thin trim-color strips running along each flank of the hull at
  ## roughly mid-height. Breaks up the slab sides at zero geometry cost.
  var trim_width_frac: float = float(p.get("hull_trim_width", 0.25))
  var hlen: float = float(p["hull_length"])
  var hw: float = float(p["hull_width"])
  var hh: float = float(p["hull_height"])

  var strip_length: float = hlen * trim_width_frac
  var strip_thickness: float = hh * 0.14
  var strip_y: float = 0.0                  # mid-height
  # Poke out slightly from the hull side so we never z-fight with the
  # hull face. Very small offset — the eye reads it as a panel line.
  var strip_x_offset: float = 0.01

  var sides: Array[float] = [-1.0, 1.0]
  for side: float in sides:
    var strip := BoxMesh.new()
    strip.size = Vector3(0.02, strip_thickness, strip_length)
    var mi := _make_part("HullTrim", strip, pal["trim"], 0.0)
    mi.position = Vector3(
      side * (hw * 0.5 + strip_x_offset),
      strip_y,
      0.0,                                   # centered along Z
    )
    add_child(mi)


func _build_mining_cutter(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Big cylindrical cutter head on the hull front. Split into a
  ## shaft (trim color, structural) plus a glowing tip (accent color,
  ## emission) so it reads as a powered industrial tool rather than a
  ## plain cone. Replaces the prism nose for miner-type ships.
  var cutter_len: float = float(p.get("cutter_length", 0.6))
  var cutter_r: float = float(p.get("cutter_radius", 0.22))
  var hlen: float = float(p["hull_length"])

  # Shaft: tapering cylinder (narrower at the front) in trim color.
  var shaft := CylinderMesh.new()
  shaft.top_radius = cutter_r * 0.72         # front face smaller
  shaft.bottom_radius = cutter_r              # back face flush w/ hull
  shaft.height = cutter_len
  shaft.radial_segments = 14
  shaft.rings = 1
  var sm := _make_part("CutterShaft", shaft, pal["trim"], 0.0)
  sm.rotation = Vector3(PI * 0.5, 0, 0)
  sm.position = Vector3(0, 0, -hlen * 0.5 - cutter_len * 0.5)
  add_child(sm)

  # Glowing tip: stubby cone at the very front. Emission pushes it into
  # bloom so the cutter reads as "active".
  var tip := CylinderMesh.new()
  tip.top_radius = cutter_r * 0.25
  tip.bottom_radius = cutter_r * 0.72
  tip.height = cutter_len * 0.28
  tip.radial_segments = 14
  tip.rings = 1
  var tm := _make_part("CutterTip", tip, pal["accent"], 2.2)
  tm.rotation = Vector3(PI * 0.5, 0, 0)
  tm.position = Vector3(
    0, 0, -hlen * 0.5 - cutter_len - cutter_len * 0.14
  )
  add_child(tm)


func _build_running_lights(
  p: Dictionary, pal: Dictionary, tpl: Dictionary
) -> void:
  ## Small bright emissive spheres at key points on the ship. Accent
  ## color + high emission means they blow out into the bloom pass and
  ## read as running lights / beacon markers even at low zoom.
  var hull_len: float = float(p["hull_length"])
  var hull_w: float = float(p["hull_width"])
  var nose_len: float = float(p.get("nose_length", 0.0))
  var light_r: float = maxf(hull_w * 0.04, 0.025)

  # 1) Nose beacon — at the very tip of the pyramid. Skip for miners:
  # their glowing cutter head already serves as a bright forward marker,
  # and doubling up washes out against the cutter's emission.
  if not p.has("cutter_length"):
    _spawn_light_sphere(
      Vector3(0, 0, -hull_len * 0.5 - nose_len),
      light_r, pal,
    )

  # 2) Wingtip lights — only if the class has wings. We infer from
  #    `wing_count` / `wing_span` — both are in params for winged classes.
  if p.has("wing_span") and p.has("wing_length"):
    var wspan: float = float(p["wing_span"])
    var wz: float = hull_len * float(p["wing_z_frac"])
    var dihedral: float = deg_to_rad(float(p.get("wing_dihedral", 0.0)))
    var half_hull: float = hull_w * 0.5
    var tip_x_mag: float = half_hull + wspan
    var tip_y: float = (wspan * 0.5) * sin(dihedral)
    _spawn_light_sphere(Vector3(-tip_x_mag, tip_y, wz), light_r, pal)
    _spawn_light_sphere(Vector3(+tip_x_mag, tip_y, wz), light_r, pal)


func _spawn_light_sphere(
  pos: Vector3, radius: float, pal: Dictionary
) -> void:
  var sphere := SphereMesh.new()
  sphere.radius = radius
  sphere.height = radius * 2.0
  sphere.radial_segments = 8
  sphere.rings = 4
  var mi := _make_part(
    "RunningLight", sphere, pal["accent"], RUNNING_LIGHT_EMISSION
  )
  mi.position = pos
  add_child(mi)


# ---------------------------------------------------------------------------
# Part material + mesh wrapper
# ---------------------------------------------------------------------------

func _make_part(
  part_name: String, mesh: Mesh, color: Color, emission_strength: float
) -> MeshInstance3D:
  var mat := ShaderMaterial.new()
  mat.shader = load(SHADER_PATH)
  mat.set_shader_parameter(&"part_color", color)
  mat.set_shader_parameter(&"roughness_val", 0.65)
  mat.set_shader_parameter(&"metallic_val", 0.30)
  mat.set_shader_parameter(&"flat_shading", true)
  if emission_strength > 0.0:
    mat.set_shader_parameter(&"emission_color", color)
    mat.set_shader_parameter(&"emission_strength", emission_strength)

  var mi := MeshInstance3D.new()
  mi.name = part_name
  mi.mesh = mesh
  mi.material_override = mat
  return mi


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_config() -> Dictionary:
  return {
    # Emit as strings so "Copy config" round-trips with POST
    # /api/admin/ships (which expects `class` and `size` as snake-case
    # names matching the Rust enums).
    "ship_class": class_name_for(ship_class),
    "ship_size": size_name_for(ship_size),
    "ship_seed": ship_seed,
    "faction_id": faction_id,
    "engine_segments": engine_segments,
  }


static func class_name_for(c: ShipClass) -> String:
  ## Handy mapping from the enum to a display string. Keys match the
  ## server's `ship.class` field so callers can round-trip with the sim.
  match c:
    ShipClass.COURIER:   return "courier"
    ShipClass.FREIGHTER: return "freighter"
    ShipClass.HAULER:    return "hauler"
    ShipClass.TANKER:    return "tanker"
    ShipClass.MINER:     return "miner"
  return "courier"


static func class_from_name(name: String) -> ShipClass:
  match name:
    "courier":   return ShipClass.COURIER
    "freighter": return ShipClass.FREIGHTER
    "hauler":    return ShipClass.HAULER
    "tanker":    return ShipClass.TANKER
    "miner":     return ShipClass.MINER
  return ShipClass.COURIER


static func size_name_for(s: ShipSize) -> String:
  ## Matches `ShipSize::as_str` in the Rust sim so the playground's
  ## "Copy Config" output round-trips with `/api/admin/ships`.
  match s:
    ShipSize.TINY:    return "tiny"
    ShipSize.SMALL:   return "small"
    ShipSize.MEDIUM:  return "medium"
    ShipSize.LARGE:   return "large"
    ShipSize.HUGE:    return "huge"
    ShipSize.MASSIVE: return "massive"
  return "medium"


static func size_from_name(name: String) -> ShipSize:
  match name:
    "tiny":    return ShipSize.TINY
    "small":   return ShipSize.SMALL
    "medium":  return ShipSize.MEDIUM
    "large":   return ShipSize.LARGE
    "huge":    return ShipSize.HUGE
    "massive": return ShipSize.MASSIVE
  return ShipSize.MEDIUM
