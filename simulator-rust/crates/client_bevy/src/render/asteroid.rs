//! Procedural asteroid mesh + per-body palette catalog.
//!
//! Port of Godot's `procedural_asteroid.gd` + the asteroid half of
//! `planet_catalog.gd`. UV sphere with per-vertex displacement along
//! the radial direction, deterministic from a seed, flat-shaded so
//! triangle facets read as the rough rock-surface look. Reuses
//! `PlanetMaterial` for surface colour — same shader the planet
//! shader runs, with sea/poles/bands/emission knobs zeroed out.

use bevy::{
    prelude::*,
    render::{
        mesh::{Indices, PrimitiveTopology},
        render_asset::RenderAssetUsages,
    },
};

use super::planet::{PlanetMaterial, PlanetParams};

/// Catalog config for one rock. Mirrors
/// `PlanetCatalog::ASTEROID_DEFAULTS` keys plus per-body overrides
/// by id (squash for elongation, tweaked deformation, etc.).
#[derive(Clone, Debug)]
pub struct AsteroidConfig {
    pub color_low: Vec4,
    pub color_mid: Vec4,
    pub color_high: Vec4,
    pub deformation: f32,
    pub deform_frequency: f32,
    pub deform_octaves: i32,
    pub noise_frequency: f32,
    pub noise_warp: f32,
    pub noise_octaves: i32,
    pub squash: Vec3,
    pub radial_segments: u32,
    pub rings: u32,
    pub tumble: Vec3,
}

impl AsteroidConfig {
    fn defaults() -> Self {
        Self {
            color_low: Vec4::new(0.22, 0.19, 0.16, 1.0),
            color_mid: Vec4::new(0.45, 0.38, 0.32, 1.0),
            color_high: Vec4::new(0.65, 0.58, 0.50, 1.0),
            deformation: 0.38,
            deform_frequency: 1.6,
            deform_octaves: 3,
            noise_frequency: 3.8,
            noise_warp: 0.6,
            noise_octaves: 4,
            squash: Vec3::ONE,
            radial_segments: 16,
            rings: 10,
            // Per-axis angular velocity (rad/s) so rocks tumble on all
            // three axes rather than spinning on one. Defaults pick
            // distinct primes so individual rocks don't sync.
            tumble: Vec3::new(0.05, 0.10, 0.03),
        }
    }
}

/// Build a config for a body. Layered: defaults → biome tweaks →
/// per-body overrides. Mirrors
/// `PlanetCatalog.build_asteroid_config`.
pub fn config_for_body(body_id: &str, biome: &str) -> AsteroidConfig {
    let mut cfg = AsteroidConfig::defaults();
    apply_biome_tweaks(biome, &mut cfg);
    apply_body_overrides(body_id, &mut cfg);
    cfg
}

fn apply_biome_tweaks(biome: &str, cfg: &mut AsteroidConfig) {
    match biome {
        "asteroid" => {} // already the default
        "ice" | "frozen" => {
            cfg.color_low = Vec4::new(0.50, 0.65, 0.78, 1.0);
            cfg.color_mid = Vec4::new(0.72, 0.82, 0.90, 1.0);
            cfg.color_high = Vec4::new(0.90, 0.95, 1.00, 1.0);
            cfg.deformation = 0.30;
        }
        "industrial" => {
            cfg.color_low = Vec4::new(0.24, 0.16, 0.12, 1.0);
            cfg.color_mid = Vec4::new(0.52, 0.30, 0.16, 1.0);
            cfg.color_high = Vec4::new(0.78, 0.50, 0.24, 1.0);
        }
        "molten" | "volcanic" => {
            cfg.color_low = Vec4::new(0.22, 0.10, 0.06, 1.0);
            cfg.color_mid = Vec4::new(0.52, 0.18, 0.08, 1.0);
            cfg.color_high = Vec4::new(0.82, 0.34, 0.14, 1.0);
        }
        "lifeless" | "barren" | "rock" => {
            cfg.color_low = Vec4::new(0.25, 0.24, 0.23, 1.0);
            cfg.color_mid = Vec4::new(0.48, 0.46, 0.44, 1.0);
            cfg.color_high = Vec4::new(0.70, 0.68, 0.65, 1.0);
        }
        _ => {}
    }
}

fn apply_body_overrides(body_id: &str, cfg: &mut AsteroidConfig) {
    match body_id {
        "slag-field" => {
            cfg.color_mid = Vec4::new(0.50, 0.22, 0.12, 1.0);
            cfg.color_high = Vec4::new(0.72, 0.42, 0.18, 1.0);
            cfg.deformation = 0.45;
        }
        "kuiper" | "kuiper-object" => {
            cfg.squash = Vec3::new(1.0, 0.78, 0.92);
            cfg.deformation = 0.32;
        }
        "near-earth" => {
            cfg.squash = Vec3::new(1.15, 0.70, 0.88);
            cfg.deformation = 0.42;
        }
        "trojan-cluster" => {
            cfg.squash = Vec3::new(1.05, 0.85, 0.95);
        }
        "hilda-group" => {
            cfg.squash = Vec3::new(0.95, 0.92, 1.05);
        }
        "ac-belt" => {
            cfg.deformation = 0.35;
        }
        "outer-rocks" => {
            cfg.squash = Vec3::new(1.1, 0.8, 0.9);
            cfg.deformation = 0.45;
        }
        "crucible" => {
            cfg.deformation = 0.42;
        }
        _ => {}
    }
}

/// Build the rock mesh: UV sphere displaced per-vertex by 3D FBM,
/// flat-shaded (per-triangle normals via duplicated vertices). Same
/// algorithm as the Godot `build_mesh` static. Deterministic from
/// `seed_int` — same seed in = same vertex buffer out.
pub fn build_asteroid_mesh(seed_int: u64, base_radius: f32, cfg: &AsteroidConfig) -> Mesh {
    // Hash seed → deform_offset so the FBM domain shifts deterministically
    // per body. Two different rocks with the same params still look
    // distinct because their noise lookups are offset.
    let deform_offset = seed_offset(seed_int);

    let seg = cfg.radial_segments.max(6) as usize;
    let rc = cfg.rings.max(4) as usize;
    let cols = seg + 1;
    let rows = rc + 1;

    // Generate displaced vertices on the sphere grid. Only the
    // grid-corner positions; we duplicate them per triangle below
    // so flat shading works.
    let mut grid: Vec<Vec3> = Vec::with_capacity(rows * cols);
    for r in 0..rows {
        let theta = std::f32::consts::PI * (r as f32) / (rc as f32);
        let (sin_t, cos_t) = theta.sin_cos();
        for s in 0..cols {
            let phi = std::f32::consts::TAU * (s as f32) / (seg as f32);
            let (sin_p, cos_p) = phi.sin_cos();
            let dir = Vec3::new(sin_t * cos_p, cos_t, sin_t * sin_p);
            let disp = fbm3(
                (dir + deform_offset) * cfg.deform_frequency,
                cfg.deform_octaves,
            );
            let r_local = base_radius * (1.0 + disp * cfg.deformation);
            let pt = Vec3::new(
                dir.x * r_local * cfg.squash.x,
                dir.y * r_local * cfg.squash.y,
                dir.z * r_local * cfg.squash.z,
            );
            grid.push(pt);
        }
    }

    // Build flat-shaded triangle list: per-face normal, duplicated
    // verts. UV stays default (we don't sample textures). 6 verts per
    // quad * rc * seg quads.
    let face_count = rc * seg * 2;
    let mut positions: Vec<[f32; 3]> = Vec::with_capacity(face_count * 3);
    let mut normals: Vec<[f32; 3]> = Vec::with_capacity(face_count * 3);
    let mut uvs: Vec<[f32; 2]> = Vec::with_capacity(face_count * 3);
    let mut indices: Vec<u32> = Vec::with_capacity(face_count * 3);
    let mut next_idx: u32 = 0;

    let push_tri = |positions: &mut Vec<[f32; 3]>,
                    normals: &mut Vec<[f32; 3]>,
                    uvs: &mut Vec<[f32; 2]>,
                    indices: &mut Vec<u32>,
                    next_idx: &mut u32,
                    a: Vec3,
                    b: Vec3,
                    c: Vec3| {
        let n = (b - a).cross(c - a).normalize_or_zero();
        for v in [a, b, c] {
            positions.push(v.to_array());
            normals.push(n.to_array());
            uvs.push([0.0, 0.0]);
            indices.push(*next_idx);
            *next_idx += 1;
        }
    };

    // Triangle winding: Bevy's default face culling treats CCW
    // (viewed from outside) as front-facing. The Godot port had
    // (v00, v10, v11) which gave inward normals in our coordinate
    // basis — rocks rendered inside-out (back-face culling killed
    // the outside, leaving the inside visible). Swapping to
    // (v00, v11, v10) flips winding so normals point outward.
    for r in 0..rc {
        for s in 0..seg {
            let i00 = r * cols + s;
            let i01 = r * cols + s + 1;
            let i10 = (r + 1) * cols + s;
            let i11 = (r + 1) * cols + s + 1;
            let v00 = grid[i00];
            let v01 = grid[i01];
            let v10 = grid[i10];
            let v11 = grid[i11];
            push_tri(
                &mut positions,
                &mut normals,
                &mut uvs,
                &mut indices,
                &mut next_idx,
                v00,
                v11,
                v10,
            );
            push_tri(
                &mut positions,
                &mut normals,
                &mut uvs,
                &mut indices,
                &mut next_idx,
                v00,
                v01,
                v11,
            );
        }
    }

    let mut mesh = Mesh::new(
        PrimitiveTopology::TriangleList,
        RenderAssetUsages::default(),
    );
    mesh.insert_attribute(Mesh::ATTRIBUTE_POSITION, positions);
    mesh.insert_attribute(Mesh::ATTRIBUTE_NORMAL, normals);
    mesh.insert_attribute(Mesh::ATTRIBUTE_UV_0, uvs);
    mesh.insert_indices(Indices::U32(indices));
    mesh
}

/// Build a PlanetMaterial tuned for an asteroid: planet shader with
/// sea/poles/bands/emission disabled, only the FBM colour noise
/// active. Same idea as Godot's
/// `ProceduralAsteroid::build_material_from_cfg`.
pub fn material_for_asteroid(cfg: &AsteroidConfig, body_id: &str) -> PlanetMaterial {
    let seed = colour_seed_offset(body_id);
    let mut p = PlanetParams {
        color_low: cfg.color_low,
        color_mid: cfg.color_mid,
        color_high: cfg.color_high,
        sea_color: Vec4::ZERO,
        pole_color: Vec4::new(1.0, 1.0, 1.0, 1.0),
        emission_color: Vec4::ZERO,
        seed_offset: seed,
        sea_level: 0.0,
        pole_threshold: 2.0, // > 1 disables polar caps
        pole_softness: 0.01,
        noise_frequency: cfg.noise_frequency,
        noise_lacunarity: 2.0,
        noise_gain: 0.5,
        noise_warp: cfg.noise_warp,
        band_strength: 0.0,
        emission_strength: 0.0,
        emission_cutoff: 1.0,
        sea_enabled: 0,
        noise_octaves: cfg.noise_octaves,
        _pad: Vec2::ZERO,
    };
    // Defensive: noise_octaves must be ≥ 1 or fbm divides by zero.
    if p.noise_octaves < 1 {
        p.noise_octaves = 1;
    }
    PlanetMaterial { params: p }
}

/// Field-scatter layout: shell = 3D halo around a lead body
/// (asteroid type), disc = flat orbital ring (belt type). Mirrors
/// `AsteroidField._scatter_position` from the Godot side.
#[derive(Copy, Clone, Debug)]
pub enum FieldLayout {
    Shell,
    Disc,
}

/// One scattered baby rock in a field. Position is local to the
/// parent body's transform; per-rock rotation + scale are random
/// but seeded.
#[derive(Clone, Debug)]
pub struct FieldRock {
    pub position: Vec3,
    pub rotation: Quat,
    pub scale: f32,
    pub tumble: Vec3,
}

/// Build a deterministic scatter of baby rocks around a body.
/// Mirrors `AsteroidField.setup` from the Godot client:
///   - asteroid bodies: 14 rocks in a spherical shell, sized
///     0.12..0.30 of the lead radius, kept clear of `inner` so
///     they don't clip the lead silhouette.
///   - belt bodies: 55 rocks in a disc with small Y jitter,
///     sized 0.35..0.75 of the body radius. No `inner` clearance
///     since belts have no lead.
///
/// Counts + size ranges + spread come from the Godot side at the
/// orbital_body.gd call sites. Seeded from `body_id + "_field"`
/// so layout is stable across runs.
pub fn build_field(body_id: &str, body_type: &str, body_radius: f32) -> Vec<FieldRock> {
    let (count, layout, spread, inner, size_range, thick) =
        if matches!(body_type, "belt") {
            (
                55,
                FieldLayout::Disc,
                body_radius * 22.0,
                0.0,
                (body_radius * 0.35, body_radius * 0.75),
                body_radius * 1.2,
            )
        } else {
            (
                14,
                FieldLayout::Shell,
                body_radius * 6.0,
                body_radius * 1.8,
                (body_radius * 0.12, body_radius * 0.30),
                0.0,
            )
        };
    let mut rng = LcgRng::new(field_seed(body_id));
    (0..count)
        .map(|_| {
            let position = scatter_position(layout, inner, spread, thick, &mut rng);
            let rotation = Quat::from_euler(
                EulerRot::XYZ,
                rng.next_f32() * std::f32::consts::TAU,
                rng.next_f32() * std::f32::consts::TAU,
                rng.next_f32() * std::f32::consts::TAU,
            );
            let scale = lerpf(size_range.0, size_range.1, rng.next_f32());
            // Per-rock tumble axis-velocities so babies don't all
            // spin together. Bias toward small rates — these are
            // far away most of the time and big spins look weird.
            let tumble = Vec3::new(
                (rng.next_f32() - 0.5) * 0.3,
                (rng.next_f32() - 0.5) * 0.3,
                (rng.next_f32() - 0.5) * 0.3,
            );
            FieldRock {
                position,
                rotation,
                scale,
                tumble,
            }
        })
        .collect()
}

fn lerpf(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn scatter_position(
    layout: FieldLayout,
    inner: f32,
    spread: f32,
    thick: f32,
    rng: &mut LcgRng,
) -> Vec3 {
    match layout {
        FieldLayout::Disc => {
            // Uniform-area on a disc: r = spread * sqrt(u). Push
            // anything inside `inner` out past the clear zone.
            let u = rng.next_f32();
            let mut r = u.sqrt() * spread;
            if r < inner {
                r = inner + rng.next_f32() * (spread - inner).max(0.0001);
            }
            let theta = rng.next_f32() * std::f32::consts::TAU;
            let y = (rng.next_f32() - 0.5) * 2.0 * thick;
            Vec3::new(r * theta.cos(), y, r * theta.sin())
        }
        FieldLayout::Shell => {
            // Uniform-on-sphere via acos sampling. Linear-interp
            // radius across the shell so rocks spread evenly
            // rather than clumping at the outside.
            let u = rng.next_f32();
            let v = rng.next_f32();
            let phi = (2.0 * v - 1.0).acos();
            let theta = std::f32::consts::TAU * u;
            let r = lerpf(inner.max(0.0001), spread, rng.next_f32());
            let sp = phi.sin();
            Vec3::new(r * sp * theta.cos(), r * phi.cos(), r * sp * theta.sin())
        }
    }
}

/// Tiny PRNG so we don't pull in `rand` here; LCG is fine for
/// scatter positions where we don't care about cryptographic
/// quality. Same seed → same field every run.
struct LcgRng(u64);

impl LcgRng {
    fn new(seed: u64) -> Self {
        Self(seed | 1)
    }
    fn next_u32(&mut self) -> u32 {
        // Numerical Recipes constants. Step the state then take the
        // upper 32 bits which have better distribution than lower.
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (self.0 >> 32) as u32
    }
    fn next_f32(&mut self) -> f32 {
        (self.next_u32() as f32) / (u32::MAX as f32 + 1.0)
    }
}

fn field_seed(body_id: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325 ^ 0xf1e1d_u64;
    for b in body_id.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    for b in b"_field" {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// Seed → 3D offset for FBM domain. Same FNV hash pattern the rest
/// of the renderer uses so layout is stable across restarts.
fn seed_offset(seed: u64) -> Vec3 {
    let mut h = seed.wrapping_mul(0x100000001b3) ^ 0xcbf29ce484222325;
    let a = (h as f32 / u64::MAX as f32) * 200.0 - 100.0;
    h = h.wrapping_mul(0x100000001b3);
    let b = (h as f32 / u64::MAX as f32) * 200.0 - 100.0;
    h = h.wrapping_mul(0x100000001b3);
    let c = (h as f32 / u64::MAX as f32) * 200.0 - 100.0;
    Vec3::new(a, b, c)
}

/// Deterministic seed_int for a body id, FNV-1a. Same id → same
/// rock geometry across runs.
pub fn seed_for(body_id: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in body_id.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// Colour-noise seed offset, decorrelated from the deform offset
/// (Godot uses `seed + 999` for the same purpose).
fn colour_seed_offset(body_id: &str) -> Vec3 {
    let mut h: u64 = 0xcbf29ce484222325 ^ 0x999;
    for b in body_id.as_bytes() {
        h ^= *b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    let a = (h as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    let b = (((h >> 21) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    let c = (((h >> 42) ^ h) as f32 / u64::MAX as f32) * 1000.0 - 500.0;
    Vec3::new(a, b, c)
}

// ---- CPU-side noise (mesh displacement only). The shader has its own. ----

fn hash3(p: Vec3) -> f32 {
    let h = (p.x * 12.9898 + p.y * 78.233 + p.z * 37.719).sin() * 43758.5453;
    h - h.floor()
}

fn value_noise3(p: Vec3) -> f32 {
    let i = p.floor();
    let f0 = p - i;
    let f = f0 * f0 * (Vec3::splat(3.0) - f0 * 2.0);

    let n000 = hash3(i);
    let n100 = hash3(i + Vec3::new(1.0, 0.0, 0.0));
    let n010 = hash3(i + Vec3::new(0.0, 1.0, 0.0));
    let n110 = hash3(i + Vec3::new(1.0, 1.0, 0.0));
    let n001 = hash3(i + Vec3::new(0.0, 0.0, 1.0));
    let n101 = hash3(i + Vec3::new(1.0, 0.0, 1.0));
    let n011 = hash3(i + Vec3::new(0.0, 1.0, 1.0));
    let n111 = hash3(i + Vec3::new(1.0, 1.0, 1.0));

    let nx00 = n000 + (n100 - n000) * f.x;
    let nx10 = n010 + (n110 - n010) * f.x;
    let nx01 = n001 + (n101 - n001) * f.x;
    let nx11 = n011 + (n111 - n011) * f.x;
    let nxy0 = nx00 + (nx10 - nx00) * f.y;
    let nxy1 = nx01 + (nx11 - nx01) * f.y;
    (nxy0 + (nxy1 - nxy0) * f.z) * 2.0 - 1.0
}

fn fbm3(p: Vec3, octaves: i32) -> f32 {
    let mut amp: f32 = 0.5;
    let mut sum: f32 = 0.0;
    let mut norm: f32 = 0.0;
    let mut q = p;
    let oct = octaves.max(1);
    for _ in 0..oct {
        sum += amp * value_noise3(q);
        norm += amp;
        q *= 2.05;
        amp *= 0.55;
    }
    sum / norm.max(0.0001)
}
