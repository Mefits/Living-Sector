// Sun halo / corona — Fresnel-falloff alpha on a slightly oversized
// shell sphere. Glancing angles (silhouette) glow brightly; head-on
// (centre of the disc) fades to zero so the sun's surface shows
// through. AlphaMode::Blend on the Rust side handles compositing.

#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::mesh_view_bindings::view

struct HaloParams {
    color: vec4<f32>,
    intensity: f32,
    falloff: f32,
    _pad: vec2<f32>,
};

@group(2) @binding(0) var<uniform> params: HaloParams;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let view_dir = normalize(view.world_position.xyz - in.world_position.xyz);
    let n = normalize(in.world_normal);
    let fresnel = 1.0 - max(dot(n, view_dir), 0.0);
    let alpha = pow(fresnel, params.falloff) * params.intensity;
    return vec4<f32>(params.color.rgb * alpha, alpha);
}
