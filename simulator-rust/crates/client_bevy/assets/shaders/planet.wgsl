// Procedural planet — WGSL port of client/shaders/procedural_planet.gdshader.
//
// FBM value-noise on the sphere normal → height field → palette + sea +
// polar caps + optional gas-giant banding. Lit with a fixed sun direction
// (Lambert + ambient floor) — we don't go through Bevy's PBR pipeline
// because the shader is unlit-style: we own ALBEDO + EMISSION ourselves.
// This keeps the bind-group layout simple (one uniform block, no PBR
// inputs / shadow plumbing) and matches the look of the Godot original
// which also bypasses PBR specular.

#import bevy_pbr::forward_io::VertexOutput

struct PlanetParams {
    color_low: vec4<f32>,
    color_mid: vec4<f32>,
    color_high: vec4<f32>,
    sea_color: vec4<f32>,
    pole_color: vec4<f32>,
    emission_color: vec4<f32>,
    seed_offset: vec3<f32>,
    sea_level: f32,
    pole_threshold: f32,
    pole_softness: f32,
    noise_frequency: f32,
    noise_lacunarity: f32,
    noise_gain: f32,
    noise_warp: f32,
    band_strength: f32,
    emission_strength: f32,
    emission_cutoff: f32,
    sea_enabled: u32,
    noise_octaves: i32,
    _pad: vec2<f32>,
};

@group(2) @binding(0) var<uniform> params: PlanetParams;

fn hash13(p_in: vec3<f32>) -> f32 {
    var p = fract(p_in * 0.1031);
    p = p + dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

fn value_noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    let n000 = hash13(i);
    let n100 = hash13(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash13(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash13(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash13(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash13(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash13(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash13(i + vec3<f32>(1.0, 1.0, 1.0));

    let nx00 = mix(n000, n100, f.x);
    let nx10 = mix(n010, n110, f.x);
    let nx01 = mix(n001, n101, f.x);
    let nx11 = mix(n011, n111, f.x);

    let nxy0 = mix(nx00, nx10, f.y);
    let nxy1 = mix(nx01, nx11, f.y);

    return mix(nxy0, nxy1, f.z);
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var amp: f32 = 0.5;
    var sum: f32 = 0.0;
    var norm: f32 = 0.0;
    var q = p_in;
    let oct = max(params.noise_octaves, 1);
    for (var i: i32 = 0; i < 6; i = i + 1) {
        if (i >= oct) { break; }
        sum = sum + amp * value_noise(q);
        norm = norm + amp;
        q = q * params.noise_lacunarity;
        amp = amp * params.noise_gain;
    }
    return sum / max(norm, 0.0001);
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // Object-space normal would be ideal so noise patterns don't shear
    // when the planet rotates. Bevy's VertexOutput hands us
    // `world_normal`; for a sphere centred at origin it's equivalent
    // up to rotation. Good enough for a static-pose body.
    let n = normalize(in.world_normal);
    var p = n;

    // Gas-giant banding: squish Y so noise reads as latitudinal stripes.
    p.y = p.y * (1.0 + params.band_strength * 6.0);
    p = p + params.seed_offset;

    if (params.noise_warp > 0.0) {
        let w = value_noise(p * params.noise_frequency * 0.5);
        p = p + vec3<f32>(w - 0.5) * params.noise_warp;
    }

    let h = fbm(p * params.noise_frequency);

    var col: vec3<f32>;
    let sea_on = params.sea_enabled != 0u;
    if (sea_on && h < params.sea_level) {
        let d = select(1.0, h / params.sea_level, params.sea_level > 0.0);
        col = params.sea_color.rgb * mix(0.55, 1.0, d);
    } else {
        let denom = max(1.0 - params.sea_level, 0.0001);
        var t: f32;
        if (sea_on) {
            t = (h - params.sea_level) / denom;
        } else {
            t = h;
        }
        t = clamp(t, 0.0, 1.0);
        col = mix(params.color_low.rgb, params.color_mid.rgb, smoothstep(0.0, 0.5, t));
        col = mix(col, params.color_high.rgb, smoothstep(0.5, 1.0, t));
    }

    // Polar caps along world-Y; matches Godot which keys off the
    // sphere normal's y component.
    let lat = abs(n.y);
    let polar = smoothstep(
        params.pole_threshold,
        params.pole_threshold + params.pole_softness,
        lat,
    );
    col = mix(col, params.pole_color.rgb, polar);

    // Lambert + ambient floor against a fixed sun direction. No real
    // shadow pipeline — bodies don't cast shadows on each other and
    // ships don't shadow planets, so this is fine.
    let sun_dir = normalize(vec3<f32>(0.5, 0.7, 0.3));
    let lambert = max(dot(n, sun_dir), 0.0) * 0.7 + 0.3;
    col = col * lambert;

    var emission = vec3<f32>(0.0);
    if (params.emission_strength > 0.0) {
        let e = smoothstep(params.emission_cutoff, 1.0, h);
        emission = params.emission_color.rgb * e * params.emission_strength;
    }

    return vec4<f32>(col + emission, 1.0);
}
