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

@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> params: HaloParams;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // Soft outward bleed: the shell sphere is much larger than the
    // sun, and we ramp alpha by how parallel the surface normal is
    // to the view direction. Glancing → bright; head-on (in front
    // of the sun's disc) → bright too. The curve is smooth enough
    // to read as a diffuse corona, not a ring around the silhouette.
    let view_dir = normalize(view.world_position.xyz - in.world_position.xyz);
    let n = normalize(in.world_normal);
    let cos_a = max(dot(n, view_dir), 0.0);
    // Bloom-style falloff: peak at glancing angles, gentle slope
    // toward centre so the disc behind shows through bright.
    let glow = pow(1.0 - cos_a, params.falloff);
    let alpha = glow * params.intensity;
    // Premultiply the colour into RGB so additive-style blending
    // reads as light, and clamp to keep alpha sane.
    return vec4<f32>(params.color.rgb * alpha, clamp(alpha, 0.0, 1.0));
}
