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
        "lifeless" | "barren" | "rock" | "moon" | "asteroid" | "belt" => Preset::Barren,
        _ => Preset::Earthlike,
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
