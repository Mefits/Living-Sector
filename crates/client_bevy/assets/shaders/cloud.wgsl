// Cloud shell — WGSL port of client/shaders/procedural_clouds.gdshader.
// FBM noise on a slightly oversized sphere shell, smoothstep-thresholded
// against `coverage` to make cloud / clear-sky bands. Below threshold
// fragments discard so the planet beneath shows through cleanly.

#import bevy_pbr::forward_io::VertexOutput

struct CloudParams {
    cloud_color: vec4<f32>,
    seed_offset: vec3<f32>,
    cloud_opacity: f32,
    cloud_coverage: f32,
    cloud_softness: f32,
    cloud_frequency: f32,
    cloud_lacunarity: f32,
    cloud_gain: f32,
    cloud_octaves: i32,
    _pad: vec3<f32>,
};

@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> params: CloudParams;

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
    let oct = max(params.cloud_octaves, 1);
    for (var i: i32 = 0; i < 6; i = i + 1) {
        if (i >= oct) { break; }
        sum = sum + amp * value_noise(q);
        norm = norm + amp;
        q = q * params.cloud_lacunarity;
        amp = amp * params.cloud_gain;
    }
    return sum / max(norm, 0.0001);
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let n = normalize(in.world_normal);
    let p = n + params.seed_offset;
    let h = fbm(p * params.cloud_frequency);

    let a = smoothstep(
        params.cloud_coverage,
        params.cloud_coverage + params.cloud_softness,
        h,
    );
    if (a < 0.01) {
        discard;
    }

    // Soft Lambert from a fixed sun direction so day-side clouds are
    // bright and night-side fades; matches the planet shader's lighting
    // pose so the terminator lines up.
    let sun_dir = normalize(vec3<f32>(0.5, 0.7, 0.3));
    let lambert = max(dot(n, sun_dir), 0.0) * 0.7 + 0.3;
    let col = params.cloud_color.rgb * lambert;

    return vec4<f32>(col, a * params.cloud_opacity);
}
