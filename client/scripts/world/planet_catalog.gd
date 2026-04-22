class_name PlanetCatalog
extends RefCounted

## Look-up table that turns a server body (id + biome) into a
## ProceduralPlanet config. Two-layer:
##
##   1. BIOME_DEFAULTS  — one entry per biome string the sim emits. Any
##      body with that biome lands on this look if nothing overrides.
##   2. PLANET_OVERRIDES — per-body-id patch dict, shallow-merged on top
##      of the biome defaults. Use for "Earth is blue with lots of land",
##      "Saturn has two rings", etc.
##
## Adding content:
##   - New biome?     Drop an entry in BIOME_DEFAULTS keyed by the exact
##                    string the sim writes to `body.biome`.
##   - New named body? Drop an entry in PLANET_OVERRIDES keyed by the
##                    body.id from the world JSON (e.g. "saturn").
##
## All values are plain data: keys are ProceduralPlanet property names,
## plus the two ring keys (`ring_count`, `ring_configs`). `apply_to` is
## the sink — any key the node doesn't know about is silently ignored.

const BIOME_DEFAULTS := {
  "terrestrial": {
    "preset": ProceduralPlanet.Preset.EARTHLIKE,
    "cloud_enabled": true,
    "cloud_color": Color(1.0, 1.0, 1.0),
    "cloud_coverage": 0.55,
    "cloud_softness": 0.08,
    "cloud_frequency": 2.8,
    "cloud_height": 1.035,
    "cloud_spin_speed": 0.04,
  },
  "desert": {
    "preset": ProceduralPlanet.Preset.DESERT,
    "cloud_enabled": true,
    "cloud_color": Color(0.95, 0.85, 0.70),
    "cloud_opacity": 0.55,
    "cloud_coverage": 0.80,  # mostly clear — dust storms only
    "cloud_softness": 0.12,
    "cloud_frequency": 3.2,
    "cloud_height": 1.03,
    "cloud_spin_speed": 0.05,
  },
  "molten": {
    "preset": ProceduralPlanet.Preset.LAVA,
  },
  "lifeless": {
    "preset": ProceduralPlanet.Preset.BARREN,
    # Lifeless = no atmosphere → no clouds. Explicit so overrides that
    # forget to clear clouds still produce a clean silhouette.
    "cloud_enabled": false,
    # No polar ice caps on airless rocks.
    "pole_threshold": 2.0,
  },
  "asteroid": {
    "preset": ProceduralPlanet.Preset.ROCKY,
    "noise_frequency": 4.2,
    "noise_warp": 0.6,
    "flat_shading": true,
  },
  "gas_giant": {
    "preset": ProceduralPlanet.Preset.GAS_GIANT,
    # Baseline gas giant gets a thin, warm ring. Overridden per-body
    # (Saturn explicitly, Jupiter to a narrow band).
    "ring_count": 1,
    "ring_configs": [
      {
        "inner": 1.45, "outer": 1.95,
        "tilt_x": 20.0, "tilt_z": 0.0,
        "color": Color(0.85, 0.78, 0.62, 0.55),
        "emission": 0.0, "spin_speed": 0.07, "segments": 72,
      },
    ],
  },
  "ice": {
    "preset": ProceduralPlanet.Preset.ICE,
    "cloud_enabled": true,
    "cloud_color": Color(0.88, 0.93, 1.0),
    "cloud_opacity": 0.75,
    "cloud_coverage": 0.65,
    "cloud_softness": 0.10,
    "cloud_frequency": 2.4,
    "cloud_height": 1.035,
    "cloud_spin_speed": 0.03,
  },
  "industrial": {
    # No dedicated preset — build the palette directly. Rocky base, hot
    # smelter glows peeking through. Metallic so stars catch the terrain.
    "preset": ProceduralPlanet.Preset.BARREN,
    "color_low": Color(0.20, 0.18, 0.16),
    "color_mid": Color(0.55, 0.42, 0.22),
    "color_high": Color(0.78, 0.55, 0.30),
    "emission_color": Color(1.0, 0.55, 0.18),
    "emission_strength": 0.9,
    "emission_cutoff": 0.72,
    "noise_frequency": 3.5,
    "noise_warp": 0.4,
    "metallic": 0.4,
    "roughness": 0.75,
    "flat_shading": true,
    "cloud_enabled": true,
    "cloud_color": Color(0.65, 0.50, 0.28),
    "cloud_opacity": 0.70,
    "cloud_coverage": 0.45,
    "cloud_softness": 0.18,
    "cloud_frequency": 2.6,
    "cloud_height": 1.05,
    "cloud_spin_speed": 0.03,
  },
}

const PLANET_OVERRIDES := {
  # --- Sol ---
  "earth": {
    "color_low": Color(0.12, 0.42, 0.15),
    "color_mid": Color(0.50, 0.45, 0.22),
    "color_high": Color(0.95, 0.95, 0.92),
    "sea_color": Color(0.04, 0.18, 0.48),
    "sea_level": 0.52,
    "pole_threshold": 0.80,
    "noise_frequency": 2.4,
    "noise_warp": 0.4,
    "cloud_coverage": 0.48,   # bluer planet, thicker swirls
    "cloud_frequency": 2.6,
    "cloud_softness": 0.10,
  },
  "mars": {
    "color_low": Color(0.52, 0.28, 0.18),
    "color_mid": Color(0.78, 0.40, 0.22),
    "color_high": Color(0.92, 0.66, 0.45),
    # No snow caps — Mars should read as a rust-red ball. Threshold > 1
    # drops the pole mask entirely; pole_color becomes irrelevant.
    "pole_threshold": 2.0,
    "noise_frequency": 2.8,
    "noise_warp": 0.5,
    "cloud_enabled": true,
    "cloud_color": Color(0.95, 0.82, 0.68),
    "cloud_opacity": 0.40,
    "cloud_coverage": 0.85,  # very sparse — occasional dust
    "cloud_frequency": 3.6,
  },
  "luna": {
    "color_low": Color(0.26, 0.26, 0.28),
    "color_mid": Color(0.52, 0.50, 0.52),
    "color_high": Color(0.78, 0.76, 0.78),
    # No atmosphere → no clouds, no polar caps. Both are redundant with
    # the lifeless biome default now but set explicitly so Luna can't
    # inherit atmosphere from a future preset change.
    "cloud_enabled": false,
    "pole_threshold": 2.0,
    "noise_frequency": 4.2,
    "noise_octaves": 5,
  },
  "mercury": {
    "color_low": Color(0.18, 0.14, 0.12),
    "color_mid": Color(0.45, 0.32, 0.22),
    "color_high": Color(0.72, 0.58, 0.42),
    "emission_color": Color(1.0, 0.55, 0.18),
    "emission_strength": 0.35,
    "emission_cutoff": 0.80,
  },
  "venus": {
    # Molten biome, but Venus reads as a hazy yellow ball, not lava.
    # Heavy sulfur-yellow cloud cover is most of what you see from space.
    "preset": ProceduralPlanet.Preset.BARREN,
    "color_low": Color(0.72, 0.58, 0.30),
    "color_mid": Color(0.88, 0.72, 0.40),
    "color_high": Color(0.98, 0.88, 0.60),
    "emission_color": Color(1.0, 0.60, 0.20),
    "emission_strength": 0.45,
    "emission_cutoff": 0.75,
    "sea_enabled": false,
    "noise_frequency": 1.8,
    "noise_warp": 0.7,
    "band_strength": 0.2,
    "cloud_enabled": true,
    "cloud_color": Color(0.98, 0.85, 0.52),
    "cloud_opacity": 0.95,
    "cloud_coverage": 0.18,   # near-total cover
    "cloud_softness": 0.15,
    "cloud_frequency": 2.0,
    "cloud_height": 1.06,
    "cloud_spin_speed": 0.02,
  },
  "jupiter": {
    "preset": ProceduralPlanet.Preset.GAS_GIANT,
    "color_low": Color(0.68, 0.55, 0.42),
    "color_mid": Color(0.92, 0.80, 0.58),
    "color_high": Color(0.48, 0.30, 0.22),
    "band_strength": 0.92,
    "noise_frequency": 1.3,
    "noise_warp": 0.8,
    "ring_count": 1,
    "ring_configs": [
      {
        "inner": 1.42, "outer": 1.52,
        "tilt_x": 3.0, "tilt_z": 0.0,
        "color": Color(0.55, 0.45, 0.30, 0.30),
        "emission": 0.0, "spin_speed": 0.04, "segments": 72,
      },
    ],
  },
  "saturn": {
    "preset": ProceduralPlanet.Preset.GAS_GIANT,
    "color_low": Color(0.80, 0.72, 0.52),
    "color_mid": Color(0.95, 0.88, 0.68),
    "color_high": Color(0.55, 0.42, 0.32),
    "band_strength": 0.80,
    "noise_frequency": 1.4,
    "noise_warp": 0.7,
    "ring_count": 2,
    "ring_configs": [
      {
        "inner": 1.45, "outer": 2.10,
        "tilt_x": 26.0, "tilt_z": 0.0,
        "color": Color(0.92, 0.84, 0.65, 0.70),
        "emission": 0.0, "spin_speed": 0.06, "segments": 96,
      },
      {
        "inner": 2.15, "outer": 2.45,
        "tilt_x": 26.0, "tilt_z": 0.0,
        "color": Color(0.78, 0.70, 0.52, 0.40),
        "emission": 0.0, "spin_speed": 0.06, "segments": 96,
      },
    ],
  },

  # --- Alpha Centauri ---
  "haven": {
    "preset": ProceduralPlanet.Preset.EARTHLIKE,
    "color_low": Color(0.12, 0.48, 0.22),
    "color_mid": Color(0.52, 0.45, 0.20),
    "sea_color": Color(0.10, 0.28, 0.55),
    "sea_level": 0.55,
    "cloud_coverage": 0.60,   # slightly clearer than Earth
  },
  "proxima": {
    "preset": ProceduralPlanet.Preset.DESERT,
    "color_low": Color(0.45, 0.24, 0.16),
    "color_mid": Color(0.70, 0.36, 0.22),
    "color_high": Color(0.88, 0.58, 0.38),
    "emission_color": Color(1.0, 0.30, 0.10),
    "emission_strength": 0.25,
    "emission_cutoff": 0.80,
  },
  "refuge": {
    "preset": ProceduralPlanet.Preset.ICE,
    "color_low": Color(0.45, 0.60, 0.78),
    "color_mid": Color(0.75, 0.85, 0.92),
    "sea_color": Color(0.10, 0.25, 0.48),
    "sea_level": 0.38,
  },

  # --- Tau Ceti ---
  "forge": {
    "preset": ProceduralPlanet.Preset.LAVA,
    "emission_strength": 2.6,
    "emission_color": Color(1.0, 0.50, 0.12),
  },
  "anvil": {
    # Industrial biome; amber glow + metallic terrain reads "factory world".
    # Heavy rust-coloured smog blanketing the surface.
    "color_low": Color(0.18, 0.16, 0.14),
    "color_mid": Color(0.58, 0.42, 0.20),
    "color_high": Color(0.80, 0.58, 0.30),
    "emission_color": Color(1.0, 0.60, 0.22),
    "emission_strength": 1.10,
    "emission_cutoff": 0.70,
    "metallic": 0.5,
    "roughness": 0.70,
    "cloud_color": Color(0.55, 0.35, 0.22),
    "cloud_opacity": 0.80,
    "cloud_coverage": 0.30,
    "cloud_frequency": 2.2,
  },
  "frostheim": {
    "preset": ProceduralPlanet.Preset.ICE,
    "color_low": Color(0.40, 0.60, 0.80),
    "color_mid": Color(0.70, 0.85, 0.95),
    "pole_threshold": 0.40,
    "pole_softness": 0.25,
  },
}


## ---------------------------------------------------------------------------
## Asteroids
## ---------------------------------------------------------------------------
## Parallel to the planet catalog but for ProceduralAsteroid. Same biome
## strings key the tweaks dict — most asteroid-type bodies land on the
## default, and we specialise a few by biome (ice / industrial / molten)
## or by body id.

const ASTEROID_DEFAULTS := {
  "color_low": Color(0.22, 0.19, 0.16),
  "color_mid": Color(0.45, 0.38, 0.32),
  "color_high": Color(0.65, 0.58, 0.50),
  "deformation": 0.38,
  "deform_frequency": 1.6,
  "deform_octaves": 3,
  "noise_frequency": 3.8,
  "noise_warp": 0.6,
  "noise_octaves": 4,
  "roughness": 0.95,
  "metallic": 0.0,
  "radial_segments": 16,
  "rings": 10,
}

const ASTEROID_BIOME_TWEAKS := {
  "asteroid": {},   # already the default
  "ice": {
    "color_low": Color(0.50, 0.65, 0.78),
    "color_mid": Color(0.72, 0.82, 0.90),
    "color_high": Color(0.90, 0.95, 1.00),
    "metallic": 0.15,
    "roughness": 0.55,
    "deformation": 0.30,   # ice rocks are a touch smoother
  },
  "industrial": {
    "color_low": Color(0.24, 0.16, 0.12),
    "color_mid": Color(0.52, 0.30, 0.16),
    "color_high": Color(0.78, 0.50, 0.24),
    "metallic": 0.45,
    "roughness": 0.70,
  },
  "molten": {
    "color_low": Color(0.22, 0.10, 0.06),
    "color_mid": Color(0.52, 0.18, 0.08),
    "color_high": Color(0.82, 0.34, 0.14),
    "roughness": 0.80,
  },
  "lifeless": {
    "color_low": Color(0.25, 0.24, 0.23),
    "color_mid": Color(0.48, 0.46, 0.44),
    "color_high": Color(0.70, 0.68, 0.65),
  },
}

const ASTEROID_OVERRIDES := {
  # Per-body shape tweaks — squash gives individuality without needing a
  # unique palette. Belts + clusters stay default; named rocks get
  # elongated shapes so trader POIs read as "that one rock".
  "slag-field": {
    "color_mid": Color(0.50, 0.22, 0.12),
    "color_high": Color(0.72, 0.42, 0.18),
    "metallic": 0.55,
    "deformation": 0.45,
  },
  "deep-ice": {
    # Inherits ice biome defaults; extra sheen.
    "metallic": 0.25,
    "roughness": 0.45,
  },
  "kuiper": {
    "squash": Vector3(1.0, 0.78, 0.92),
    "deformation": 0.32,
  },
  "near-earth": {
    "squash": Vector3(1.15, 0.70, 0.88),
    "deformation": 0.42,
  },
  "trojan-cluster": {
    "squash": Vector3(1.05, 0.85, 0.95),
  },
  "hilda-group": {
    "squash": Vector3(0.95, 0.92, 1.05),
  },
  "ac-belt": {
    "deformation": 0.35,
  },
  "outer-rocks": {
    "squash": Vector3(1.1, 0.8, 0.9),
    "deformation": 0.45,
  },
  "crucible": {
    # Belt body; slightly larger deformation reads "chunky industrial belt".
    "deformation": 0.42,
  },
}


static func build_asteroid_config(body_id: String, biome: String) -> Dictionary:
  var cfg: Dictionary = ASTEROID_DEFAULTS.duplicate(true)
  if biome != "" and ASTEROID_BIOME_TWEAKS.has(biome):
    cfg.merge(ASTEROID_BIOME_TWEAKS[biome] as Dictionary, true)
  if body_id != "" and ASTEROID_OVERRIDES.has(body_id):
    cfg.merge(ASTEROID_OVERRIDES[body_id] as Dictionary, true)
  return cfg


static func apply_to_asteroid(
  ast: ProceduralAsteroid, body_id: String, cfg: Dictionary
) -> void:
  ## Push a catalog config into a ProceduralAsteroid. Seed first so any
  ## mesh rebuild triggered by a later setter uses the correct offset.
  ## `squash` accepts either a Vector3 or a 3-element Array (so config
  ## round-trips through JSON via `to_config()` still work).
  ast.asteroid_seed = seed_for(body_id)
  for key in cfg.keys():
    var value: Variant = cfg[key]
    if key == "squash":
      if value is Vector3:
        ast.squash = value
      elif value is Array and (value as Array).size() == 3:
        var a := value as Array
        ast.squash = Vector3(a[0], a[1], a[2])
      continue
    if key == "tumble":
      if value is Vector3:
        ast.tumble = value
      elif value is Array and (value as Array).size() == 3:
        var a := value as Array
        ast.tumble = Vector3(a[0], a[1], a[2])
      continue
    ast.set(key, value)


static func build_config(body_id: String, biome: String) -> Dictionary:
  ## Shallow-merge biome defaults then planet-specific overrides. Later
  ## keys win. Returns {} if neither layer has anything for this body, so
  ## callers can detect "no procedural planet for this body, fall back".
  var cfg: Dictionary = {}
  if biome != "" and BIOME_DEFAULTS.has(biome):
    cfg.merge(BIOME_DEFAULTS[biome] as Dictionary, true)
  if body_id != "" and PLANET_OVERRIDES.has(body_id):
    cfg.merge(PLANET_OVERRIDES[body_id] as Dictionary, true)
  return cfg


static func seed_for(body_id: String) -> int:
  ## Stable, positive seed derived from the body id. Same id → same noise
  ## offset across runs, so Earth looks like Earth without the server
  ## needing to ship a per-body seed field.
  return int(hash(body_id)) & 0x7FFFFFFF


static func apply_to(
  planet: ProceduralPlanet, body_id: String, cfg: Dictionary
) -> void:
  ## Push a catalog config into a planet node. Must be called AFTER the
  ## planet is in the scene tree — _ready needs to have created the
  ## material and ring slots, otherwise uniform writes no-op and ring
  ## param sets drop on the floor.
  planet.planet_seed = seed_for(body_id)
  if cfg.has("preset"):
    planet.preset = cfg["preset"]
  # Scalar/color/bool overrides — anything other than the preset marker
  # or the ring keys. Unknown keys hit Object.set() which silently ignores
  # properties that don't exist; misspellings are tolerated, not fatal.
  for key in cfg.keys():
    if key == "preset" or key == "ring_count" or key == "ring_configs":
      continue
    planet.set(key, cfg[key])
  # Rings last. ring_count resize drives ring_configs allocation, then
  # each ring's overrides go in by index via set_ring_param.
  var rc: int = int(cfg.get("ring_count", 0))
  planet.ring_count = rc
  var ring_list: Array = cfg.get("ring_configs", [])
  var ring_n: int = mini(rc, ring_list.size())
  for i in range(ring_n):
    var r_cfg: Dictionary = ring_list[i]
    for k in r_cfg.keys():
      planet.set_ring_param(i, k, r_cfg[k])
