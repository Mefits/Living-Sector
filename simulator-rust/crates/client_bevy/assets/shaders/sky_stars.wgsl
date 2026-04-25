// Procedural star sky — WGSL port of `starfield.gd::SKY_SHADER_CODE`.
//
// Rendered on a giant sphere centred on the camera with cull_mode
// flipped so the inside renders. Three FBM-grid star layers stacked:
// bright named stars (warm/cool tinted, twinkling), mid white band,
// fine dust. Same per-cell hash → cell-local position math the Godot
// sky shader uses; one direction sample per fragment.
//
// We sample by world-space normal (== outward direction on the
// shell). With the shell centred on the camera each frame, that's
// equivalent to Godot's EYEDIR.

#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::globals::Globals

@group(0) @binding(1) var<uniform> globals: Globals;

fn hash31(p_in: vec3<f32>) -> f32 {
    var p = fract(p_in * 0.1031);
    p = p + dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

fn star_layer(
    dir: vec3<f32>,
    scale: f32,
    threshold: f32,
    size_mul: f32,
    brightness: f32,
    tint: vec3<f32>,
    seed: f32,
) -> vec3<f32> {
    let cell = floor(dir * scale);
    let f = fract(dir * scale);
    let rnd = hash31(cell + seed);
    if (rnd <= threshold) {
        return vec3<f32>(0.0);
    }
    let center = vec3<f32>(
        hash31(cell + seed + 0.31),
        hash31(cell + seed + 0.62),
        hash31(cell + seed + 0.93),
    );
    let d = length(f - center);
    let radius = (rnd - threshold) * size_mul / max(1.0 - threshold, 0.0001);
    let s = 1.0 - smoothstep(0.0, radius, d);
    return tint * s * brightness;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // We're on the inside of a sphere centred on the camera, so
    // the inward-facing world normal IS the eye direction.
    let dir = -normalize(in.world_normal);

    var col = vec3<f32>(0.0);

    // Bright named stars — sparse, warm/cool variation, twinkle.
    let twinkle =
        sin(globals.time * 0.9 + hash31(floor(dir * 180.0)) * 30.0) * 0.3 + 0.7;
    let warm = vec3<f32>(1.0, 0.92, 0.78);
    let cool = vec3<f32>(0.82, 0.9, 1.0);
    let hue_mix = hash31(floor(dir * 180.0) + 1.7);
    col = col
        + star_layer(dir, 180.0, 0.97, 0.18, 1.6 * twinkle, mix(cool, warm, hue_mix), 0.0);

    // Mid band — smaller, neutral white.
    col = col + star_layer(dir, 380.0, 0.985, 0.12, 0.9, vec3<f32>(0.95), 5.1);

    // Fine dust — tiny points, very sparse.
    col = col + star_layer(dir, 760.0, 0.995, 0.08, 0.5, vec3<f32>(0.9), 11.3);

    return vec4<f32>(col, 1.0);
}
