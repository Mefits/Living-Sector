// Procedural nebula — WGSL port of client/shaders/procedural_nebula.gdshader.
//
// Additive emissive cloud: domain-warped FBM gives filamentary
// structure, a wisp layer adds bright streaks, and a view-angle
// silhouette fade carved by low-freq noise sells the broken edge.
// Surface shader on a sphere shell rather than a true ray-march —
// cheap enough that 14 of them stack on the backdrop without
// touching frame budget at galactic zoom.

#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::mesh_view_bindings::view

struct NebulaParams {
    primary_color: vec4<f32>,
    secondary_color: vec4<f32>,
    seed_offset: vec3<f32>,
    density: f32,
    brightness: f32,
    noise_frequency: f32,
    noise_warp: f32,
    wisp_strength: f32,
    radial_falloff: f32,
    color_mix_shift: f32,
    color_mix_band: f32,
    density_threshold: f32,
    noise_octaves: i32,
    _pad: vec3<f32>,
};

@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> params: NebulaParams;

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
        q = q * 2.05;
        amp = amp * 0.55;
    }
    return sum / max(norm, 0.0001);
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // Local-ish space — we use the world-space position here, scaled
    // down so noise frequency matches the Godot version. The Godot
    // shader sampled VERTEX (object-local), but at our scales the
    // spheres are huge so we re-normalise into ~[-1,1] using the
    // sphere's nominal radius (encoded into noise_frequency).
    let n_world = normalize(in.world_normal);
    var p = n_world + params.seed_offset;

    // Domain warp — displaces the sampling position by fbm of
    // itself. Gives the cloud filamentary streaks rather than a
    // uniform blob.
    if (params.noise_warp > 0.0) {
        let warp = vec3<f32>(
            fbm(p * params.noise_frequency * 0.5),
            fbm(p * params.noise_frequency * 0.5 + vec3<f32>(100.0)),
            fbm(p * params.noise_frequency * 0.5 + vec3<f32>(200.0)),
        );
        p = p + (warp - 0.5) * params.noise_warp;
    }

    var n = fbm(p * params.noise_frequency);

    // Wisp layer — higher-freq noise modulates density into bright
    // filaments within the broader cloud.
    if (params.wisp_strength > 0.0) {
        let wisps = fbm(p * params.noise_frequency * 2.5);
        n = mix(n, n * wisps * 1.8, params.wisp_strength);
    }

    // Silhouette fade by view angle. Surface fragments at the rim
    // fade out; fragments facing the camera stay opaque.
    let view_dir = normalize(view.world_position.xyz - in.world_position.xyz);
    let view_face = clamp(abs(dot(n_world, view_dir)), 0.0, 1.0);
    // Break up the disc with a low-freq noise so the silhouette
    // reads as tendrils + holes, not a clean circle.
    let edge_carve = fbm((n_world + params.seed_offset + vec3<f32>(37.0)) * params.noise_frequency * 0.7);
    let silhouette = clamp(view_face + (edge_carve - 0.5) * 0.55, 0.0, 1.0);
    let radial = pow(silhouette, params.radial_falloff);

    // Density threshold — drop low-noise regions to zero so the
    // cloud has gaps. Remap the rest to 0..1.
    n = max(n - params.density_threshold, 0.0) /
        max(1.0 - params.density_threshold, 0.0001);

    // n*n sharpens the alpha curve so sparse noise drops fast to
    // transparent, reading as patchy tendrils not uniform haze.
    var a = n * n * 2.0 * radial * params.density;
    a = clamp(a, 0.0, 1.0);

    // Two-colour blend driven by noise.
    let mix_t = smoothstep(
        params.color_mix_shift - params.color_mix_band,
        params.color_mix_shift + params.color_mix_band,
        n,
    );
    let col = mix(params.primary_color.rgb, params.secondary_color.rgb, mix_t);

    // Additive: ALBEDO * a * brightness. Premultiplied so the
    // AlphaMode::Add blend stage just sums colours.
    let emission = col * a * params.brightness;
    return vec4<f32>(emission, a);
}
