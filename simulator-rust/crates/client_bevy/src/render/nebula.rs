//! Procedural nebula shader material — port of
//! `client/shaders/procedural_nebula.gdshader`. Additive emissive
//! cloud rendered on a sphere shell. Drives the `spawn_nebulae`
//! backdrop in render/mod.rs.

use bevy::{
    pbr::{Material, MaterialPlugin},
    prelude::*,
    render::{
        alpha::AlphaMode,
        render_resource::{AsBindGroup, ShaderRef, ShaderType},
    },
};

pub struct NebulaMaterialPlugin;

impl Plugin for NebulaMaterialPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(MaterialPlugin::<NebulaMaterial>::default());
    }
}

#[derive(Asset, AsBindGroup, TypePath, Debug, Clone)]
pub struct NebulaMaterial {
    #[uniform(0)]
    pub params: NebulaParams,
}

#[derive(ShaderType, Debug, Clone, Copy)]
pub struct NebulaParams {
    pub primary_color: Vec4,
    pub secondary_color: Vec4,
    pub seed_offset: Vec3,
    pub density: f32,
    pub brightness: f32,
    pub noise_frequency: f32,
    pub noise_warp: f32,
    pub wisp_strength: f32,
    pub radial_falloff: f32,
    pub color_mix_shift: f32,
    pub color_mix_band: f32,
    pub density_threshold: f32,
    pub noise_octaves: i32,
    pub _pad: Vec3,
}

impl Material for NebulaMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/nebula.wgsl".into()
    }
    /// Additive blend so the cloud stacks against stars without
    /// darkening anything. Matches Godot's `blend_add`.
    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Add
    }
}

/// Pick a deterministic primary/secondary colour pair for a cloud
/// keyed off its slot index + the world seed. Palette mirrors the
/// Godot nebula playground's defaults — purples, teals, dusty
/// oranges, deep blues — biased toward "deep space" rather than
/// neon.
pub fn nebula_palette(slot: u32, world_seed: u64) -> (Vec4, Vec4) {
    let mut h = world_seed
        ^ 0xa1b2_c3d4_e5f6_0789_u64
        ^ ((slot as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15));
    h = h.wrapping_mul(0x100000001b3);
    let pick = (h >> 32) as u32 % PALETTES.len() as u32;
    PALETTES[pick as usize]
}

const PALETTES: &[(Vec4, Vec4)] = &[
    // (primary, secondary) — pairs picked to read at low brightness
    // against a near-black sky. Each pair has a distinct hue
    // gradient so neighbouring clouds don't blend together.
    (
        Vec4::new(0.80, 0.35, 0.95, 1.0), // magenta
        Vec4::new(0.25, 0.60, 1.00, 1.0), // ice blue
    ),
    (
        Vec4::new(0.20, 0.70, 0.85, 1.0), // teal
        Vec4::new(0.70, 0.30, 0.55, 1.0), // dusty rose
    ),
    (
        Vec4::new(0.95, 0.55, 0.25, 1.0), // dusty orange
        Vec4::new(0.35, 0.20, 0.55, 1.0), // deep purple
    ),
    (
        Vec4::new(0.30, 0.45, 0.95, 1.0), // royal blue
        Vec4::new(0.85, 0.85, 1.00, 1.0), // pale white-blue
    ),
    (
        Vec4::new(0.55, 0.95, 0.65, 1.0), // jade
        Vec4::new(0.25, 0.40, 0.85, 1.0), // cobalt
    ),
    (
        Vec4::new(0.95, 0.70, 0.40, 1.0), // amber
        Vec4::new(0.60, 0.20, 0.30, 1.0), // crimson
    ),
];

/// Build a NebulaParams for a given cloud slot. Defaults mirror
/// `procedural_nebula.gdshader` baseline knobs; per-slot variation
/// comes from the seed offset and palette pick.
pub fn nebula_params(slot: u32, world_seed: u64) -> NebulaParams {
    let (primary, secondary) = nebula_palette(slot, world_seed);
    let mut h = world_seed
        ^ 0xdeed_beef_5eed_face_u64
        ^ ((slot as u64).wrapping_mul(0xC2B2_AE3D_27D4_EB4F));
    let mut next = || {
        h = h.wrapping_mul(0x100000001b3) ^ (h >> 27);
        (h as f32 / u64::MAX as f32) * 1000.0 - 500.0
    };
    NebulaParams {
        primary_color: primary,
        secondary_color: secondary,
        seed_offset: Vec3::new(next(), next(), next()),
        density: 1.1,
        brightness: 0.55, // tame — these stack additively, full strength blooms out
        noise_frequency: 1.6,
        noise_warp: 0.75,
        wisp_strength: 0.9,
        radial_falloff: 5.2,
        color_mix_shift: 0.5,
        color_mix_band: 0.22,
        density_threshold: 0.66,
        noise_octaves: 4,
        _pad: Vec3::ZERO,
    }
}
