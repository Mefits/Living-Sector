//! Procedural planet material — WGSL port of Godot's
//! `procedural_planet.gdshader`. One uniform block keys terrain
//! palette + sea + polar caps + FBM frequency knobs; biome string
//! from `BodyBiome` picks a preset at spawn.
//!
//! Why a custom Material rather than `StandardMaterial` + texture?
//!  - Per-body procedural detail with zero textures (no asset bytes,
//!    no GPU memory per planet beyond the uniform block).
//!  - Deterministic from a seed, so the same world layout reads the
//!    same across restarts.
//!  - Mirrors the Godot client visually so the two ports share the
//!    same biome vocabulary (the server already tags biomes per body).

use bevy::{
    pbr::{Material, MaterialPlugin},
    prelude::*,
    render::render_resource::{AsBindGroup, ShaderRef, ShaderType},
};

pub struct PlanetMaterialPlugin;

impl Plugin for PlanetMaterialPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(MaterialPlugin::<PlanetMaterial>::default());
    }
}

#[derive(Asset, AsBindGroup, TypePath, Debug, Clone)]
pub struct PlanetMaterial {
    #[uniform(0)]
    pub params: PlanetParams,
}

/// Uniform block. Field order chosen so std140-ish padding lines up
/// with the WGSL struct exactly (vec4 aligned to 16, vec3 padded to
/// 16 by trailing `_pad`). If you reorder these, mirror the change
/// in `assets/shaders/planet.wgsl`.
#[derive(ShaderType, Debug, Clone, Copy)]
pub struct PlanetParams {
    pub color_low: Vec4,
    pub color_mid: Vec4,
    pub color_high: Vec4,
    pub sea_color: Vec4,
    pub pole_color: Vec4,
    pub emission_color: Vec4,
    pub seed_offset: Vec3,
    pub sea_level: f32,
    pub pole_threshold: f32,
    pub pole_softness: f32,
    pub noise_frequency: f32,
    pub noise_lacunarity: f32,
    pub noise_gain: f32,
    pub noise_warp: f32,
    pub band_strength: f32,
    pub emission_strength: f32,
    pub emission_cutoff: f32,
    pub sea_enabled: u32,
    pub noise_octaves: i32,
    pub _pad: Vec2,
}

impl Material for PlanetMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/planet.wgsl".into()
    }
}

/// Biome name (from `BodyBiome.biome`) → preset. Mapping mirrors
/// `BodyBiome::food_multiplier_for` so visual class follows the
/// same vocabulary the sim already groups by.
pub fn preset_for_biome(biome: &str) -> Preset {
    match biome {
        "terrestrial" | "temperate" | "earthlike" | "forest" | "jungle" => Preset::Earthlike,
        "ocean" | "aquatic" => Preset::Ocean,
        "tundra" | "arctic" | "ice" | "frozen" => Preset::Ice,
        "desert" | "arid" => Preset::Desert,
        "volcanic" | "molten" => Preset::Lava,
        "gas" | "gas_giant" => Preset::GasGiant,
        "industrial" => Preset::Barren,
        "lifeless" | "barren" | "rock" | "moon" | "asteroid" | "belt" => Preset::Barren,
        _ => Preset::Earthlike,
    }
}

/// Build full PlanetParams for a body, applying per-body color
/// overrides on top of the biome-based preset. Mirrors Godot's
/// `PlanetCatalog.PLANET_OVERRIDES`. Named bodies (Earth, Mars,
/// Luna, …) get curated palettes so they read as themselves rather
/// than generic terrestrial / barren planets.
///
/// This intentionally skips the Godot catalog's cloud + ring data —
/// those need separate meshes/shaders. Add them back when we port
/// procedural_clouds and the ring annulus geometry.
pub fn params_for_body(body_id: &str, biome: &str) -> PlanetParams {
    let seed = seed_offset_from_id(body_id);
    let base_preset = body_preset_override(body_id).unwrap_or_else(|| preset_for_biome(biome));
    let mut p = base_preset.params(seed);
    apply_body_overrides(body_id, &mut p);
    p
}

/// Some bodies override their biome's preset (e.g. Venus is `molten`
/// in the sim but should read as a hazy yellow Barren planet, not a
/// glowing lava world). Returning `None` keeps the biome-default.
fn body_preset_override(body_id: &str) -> Option<Preset> {
    match body_id {
        "venus" => Some(Preset::Barren),
        "jupiter" | "saturn" => Some(Preset::GasGiant),
        "haven" => Some(Preset::Earthlike),
        "proxima" => Some(Preset::Desert),
        "refuge" | "frostheim" => Some(Preset::Ice),
        "forge" => Some(Preset::Lava),
        _ => None,
    }
}

/// Apply per-body colour / shape patches on top of the preset
/// baseline. Mirrors `PlanetCatalog.PLANET_OVERRIDES` 1:1 for the
/// bodies in the current world. Cloud + ring keys from the Godot
/// catalog are not represented here yet — see params_for_body.
fn apply_body_overrides(body_id: &str, p: &mut PlanetParams) {
    match body_id {
        // ---- Sol ----
        "earth" => {
            p.color_low = Vec4::new(0.12, 0.42, 0.15, 1.0);
            p.color_mid = Vec4::new(0.50, 0.45, 0.22, 1.0);
            p.color_high = Vec4::new(0.95, 0.95, 0.92, 1.0);
            p.sea_color = Vec4::new(0.04, 0.18, 0.48, 1.0);
            p.sea_level = 0.52;
            p.pole_threshold = 0.80;
            p.noise_frequency = 2.4;
            p.noise_warp = 0.4;
        }
        "mars" => {
            p.color_low = Vec4::new(0.52, 0.28, 0.18, 1.0);
            p.color_mid = Vec4::new(0.78, 0.40, 0.22, 1.0);
            p.color_high = Vec4::new(0.92, 0.66, 0.45, 1.0);
            // Threshold > 1 disables polar caps entirely — Mars
            // shouldn't have white poles in our look.
            p.pole_threshold = 2.0;
            p.noise_frequency = 2.8;
            p.noise_warp = 0.5;
            p.sea_enabled = 0;
        }
        "luna" => {
            p.color_low = Vec4::new(0.26, 0.26, 0.28, 1.0);
            p.color_mid = Vec4::new(0.52, 0.50, 0.52, 1.0);
            p.color_high = Vec4::new(0.78, 0.76, 0.78, 1.0);
            p.pole_threshold = 2.0;
            p.noise_frequency = 4.2;
            p.noise_octaves = 5;
            p.sea_enabled = 0;
        }
        "mercury" => {
            p.color_low = Vec4::new(0.18, 0.14, 0.12, 1.0);
            p.color_mid = Vec4::new(0.45, 0.32, 0.22, 1.0);
            p.color_high = Vec4::new(0.72, 0.58, 0.42, 1.0);
            p.emission_color = Vec4::new(1.0, 0.55, 0.18, 1.0);
            p.emission_strength = 0.35;
            p.emission_cutoff = 0.80;
            p.sea_enabled = 0;
            p.pole_threshold = 2.0;
        }
        "venus" => {
            p.color_low = Vec4::new(0.72, 0.58, 0.30, 1.0);
            p.color_mid = Vec4::new(0.88, 0.72, 0.40, 1.0);
            p.color_high = Vec4::new(0.98, 0.88, 0.60, 1.0);
            p.emission_color = Vec4::new(1.0, 0.60, 0.20, 1.0);
            p.emission_strength = 0.45;
            p.emission_cutoff = 0.75;
            p.sea_enabled = 0;
            p.noise_frequency = 1.8;
            p.noise_warp = 0.7;
            p.band_strength = 0.2;
            p.pole_threshold = 2.0;
        }
        "jupiter" => {
            p.color_low = Vec4::new(0.68, 0.55, 0.42, 1.0);
            p.color_mid = Vec4::new(0.92, 0.80, 0.58, 1.0);
            p.color_high = Vec4::new(0.48, 0.30, 0.22, 1.0);
            p.band_strength = 0.92;
            p.noise_frequency = 1.3;
            p.noise_warp = 0.8;
        }
        "saturn" => {
            p.color_low = Vec4::new(0.80, 0.72, 0.52, 1.0);
            p.color_mid = Vec4::new(0.95, 0.88, 0.68, 1.0);
            p.color_high = Vec4::new(0.55, 0.42, 0.32, 1.0);
            p.band_strength = 0.80;
            p.noise_frequency = 1.4;
            p.noise_warp = 0.7;
        }

        // ---- Alpha Centauri ----
        "haven" => {
            p.color_low = Vec4::new(0.12, 0.48, 0.22, 1.0);
            p.color_mid = Vec4::new(0.52, 0.45, 0.20, 1.0);
            p.sea_color = Vec4::new(0.10, 0.28, 0.55, 1.0);
            p.sea_level = 0.55;
        }
        "proxima" => {
            p.color_low = Vec4::new(0.45, 0.24, 0.16, 1.0);
            p.color_mid = Vec4::new(0.70, 0.36, 0.22, 1.0);
            p.color_high = Vec4::new(0.88, 0.58, 0.38, 1.0);
            p.emission_color = Vec4::new(1.0, 0.30, 0.10, 1.0);
            p.emission_strength = 0.25;
            p.emission_cutoff = 0.80;
        }
        "refuge" => {
            p.color_low = Vec4::new(0.45, 0.60, 0.78, 1.0);
            p.color_mid = Vec4::new(0.75, 0.85, 0.92, 1.0);
            p.sea_color = Vec4::new(0.10, 0.25, 0.48, 1.0);
            p.sea_level = 0.38;
        }

        // ---- Tau Ceti ----
        "forge" => {
            p.emission_strength = 2.6;
            p.emission_color = Vec4::new(1.0, 0.50, 0.12, 1.0);
        }
        "anvil" => {
            p.color_low = Vec4::new(0.18, 0.16, 0.14, 1.0);
            p.color_mid = Vec4::new(0.58, 0.42, 0.20, 1.0);
            p.color_high = Vec4::new(0.80, 0.58, 0.30, 1.0);
            p.emission_color = Vec4::new(1.0, 0.60, 0.22, 1.0);
            p.emission_strength = 1.10;
            p.emission_cutoff = 0.70;
        }
        "frostheim" => {
            p.color_low = Vec4::new(0.40, 0.60, 0.80, 1.0);
            p.color_mid = Vec4::new(0.70, 0.85, 0.95, 1.0);
            p.pole_threshold = 0.40;
            p.pole_softness = 0.25;
        }

        _ => {}
    }
}

/// Preset palette + shape knobs. Mirrors the Godot
/// `ProceduralPlanet::Preset` enum so the port produces the same
/// look across both clients. Rocky/GasGiant aren't reachable from
/// the current biome table but are kept so future biomes ("rocky",
/// "gas") can opt in without re-deriving the params.
#[allow(dead_code)]
#[derive(Copy, Clone, Debug)]
pub enum Preset {
    Earthlike,
    Rocky,
    Desert,
    Ice,
    Lava,
    GasGiant,
    Barren,
    Ocean,
}

impl Preset {
    /// Build a fully-populated `PlanetParams` for this preset, then
    /// jitter the noise domain by `seed_offset` so two planets with
    /// the same preset don't look identical.
    pub fn params(self, seed_offset: Vec3) -> PlanetParams {
        let mut p = PlanetParams {
            color_low: Vec4::new(0.20, 0.35, 0.15, 1.0),
            color_mid: Vec4::new(0.45, 0.38, 0.22, 1.0),
            color_high: Vec4::new(0.80, 0.78, 0.75, 1.0),
            sea_color: Vec4::new(0.05, 0.18, 0.40, 1.0),
            pole_color: Vec4::new(0.95, 0.97, 1.00, 1.0),
            emission_color: Vec4::new(1.0, 0.35, 0.05, 1.0),
            seed_offset,
            sea_level: 0.45,
            pole_threshold: 0.78,
            pole_softness: 0.08,
            noise_frequency: 2.0,
            noise_lacunarity: 2.0,
            noise_gain: 0.5,
            noise_warp: 0.0,
            band_strength: 0.0,
            emission_strength: 0.0,
            emission_cutoff: 0.6,
            sea_enabled: 1,
            noise_octaves: 4,
            _pad: Vec2::ZERO,
        };
        match self {
            Preset::Earthlike => {
                p.color_low = Vec4::new(0.18, 0.38, 0.18, 1.0);
                p.color_mid = Vec4::new(0.48, 0.42, 0.25, 1.0);
                p.color_high = Vec4::new(0.82, 0.80, 0.76, 1.0);
                p.sea_color = Vec4::new(0.05, 0.20, 0.42, 1.0);
                p.sea_level = 0.48;
                p.noise_frequency = 2.2;
                p.noise_octaves = 5;
                p.noise_warp = 0.3;
            }
            Preset::Rocky => {
                p.color_low = Vec4::new(0.30, 0.22, 0.18, 1.0);
                p.color_mid = Vec4::new(0.50, 0.38, 0.30, 1.0);
                p.color_high = Vec4::new(0.70, 0.62, 0.55, 1.0);
                p.pole_color = Vec4::new(0.85, 0.82, 0.78, 1.0);
                p.sea_enabled = 0;
                p.pole_threshold = 0.92;
                p.pole_softness = 0.05;
                p.noise_frequency = 3.0;
                p.noise_octaves = 5;
                p.noise_lacunarity = 2.1;
                p.noise_gain = 0.55;
                p.noise_warp = 0.4;
            }
            Preset::Desert => {
                p.color_low = Vec4::new(0.62, 0.48, 0.28, 1.0);
                p.color_mid = Vec4::new(0.78, 0.60, 0.35, 1.0);
                p.color_high = Vec4::new(0.92, 0.80, 0.55, 1.0);
                p.pole_color = Vec4::new(0.88, 0.80, 0.62, 1.0);
                p.sea_enabled = 0;
                p.pole_threshold = 0.95;
                p.noise_frequency = 2.5;
                p.noise_octaves = 4;
                p.noise_warp = 0.5;
                p.band_strength = 0.15;
            }
            Preset::Ice => {
                p.color_low = Vec4::new(0.55, 0.70, 0.85, 1.0);
                p.color_mid = Vec4::new(0.78, 0.88, 0.95, 1.0);
                p.color_high = Vec4::new(0.95, 0.97, 1.00, 1.0);
                p.sea_color = Vec4::new(0.12, 0.32, 0.55, 1.0);
                p.pole_color = Vec4::new(1.0, 1.0, 1.0, 1.0);
                p.sea_level = 0.30;
                p.pole_threshold = 0.50;
                p.pole_softness = 0.20;
                p.noise_frequency = 2.0;
                p.noise_warp = 0.2;
            }
            Preset::Lava => {
                p.color_low = Vec4::new(0.08, 0.04, 0.03, 1.0);
                p.color_mid = Vec4::new(0.30, 0.10, 0.05, 1.0);
                p.color_high = Vec4::new(0.80, 0.25, 0.08, 1.0);
                p.emission_color = Vec4::new(1.0, 0.45, 0.10, 1.0);
                p.pole_color = Vec4::new(0.25, 0.10, 0.05, 1.0);
                p.sea_enabled = 0;
                p.pole_threshold = 0.95;
                p.noise_frequency = 3.5;
                p.noise_octaves = 5;
                p.noise_warp = 0.6;
                p.emission_strength = 2.0;
                p.emission_cutoff = 0.55;
            }
            Preset::GasGiant => {
                p.color_low = Vec4::new(0.70, 0.55, 0.40, 1.0);
                p.color_mid = Vec4::new(0.85, 0.75, 0.60, 1.0);
                p.color_high = Vec4::new(0.55, 0.40, 0.32, 1.0);
                p.pole_color = Vec4::new(0.85, 0.82, 0.78, 1.0);
                p.sea_enabled = 0;
                p.pole_threshold = 0.90;
                p.pole_softness = 0.15;
                p.noise_frequency = 1.5;
                p.noise_octaves = 4;
                p.noise_lacunarity = 2.2;
                p.noise_gain = 0.55;
                p.noise_warp = 0.8;
                p.band_strength = 0.85;
            }
            Preset::Barren => {
                p.color_low = Vec4::new(0.28, 0.27, 0.26, 1.0);
                p.color_mid = Vec4::new(0.48, 0.46, 0.44, 1.0);
                p.color_high = Vec4::new(0.72, 0.70, 0.68, 1.0);
                p.pole_color = Vec4::new(0.80, 0.80, 0.82, 1.0);
                p.sea_enabled = 0;
                p.pole_threshold = 0.95;
                p.noise_frequency = 3.2;
                p.noise_octaves = 4;
                p.noise_warp = 0.2;
            }
            Preset::Ocean => {
                p.color_low = Vec4::new(0.05, 0.20, 0.45, 1.0);
                p.color_mid = Vec4::new(0.10, 0.35, 0.58, 1.0);
                p.color_high = Vec4::new(0.25, 0.55, 0.72, 1.0);
                p.sea_color = Vec4::new(0.04, 0.14, 0.32, 1.0);
                p.pole_color = Vec4::new(0.95, 0.97, 1.00, 1.0);
                p.sea_level = 0.78;
                p.pole_threshold = 0.80;
                p.noise_frequency = 2.0;
                p.noise_octaves = 4;
                p.noise_warp = 0.3;
            }
        }
        p
    }
}

/// Hash a body id string into a deterministic seed offset so two
/// bodies with the same biome don't render identically. FNV-1a so
/// the layout is stable across restarts.
pub fn seed_offset_from_id(body_id: &str) -> Vec3 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in body_id.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    let a = (h as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    let b = (((h >> 21) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    let c = (((h >> 42) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    Vec3::new(a, b, c)
}
