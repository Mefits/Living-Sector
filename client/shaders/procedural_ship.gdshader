shader_type spatial;
// Flat shading via derivatives so low-poly primitives (BoxMesh, PrismMesh,
// CylinderMesh) read as faceted slabs — lines up with the rest of our
// procedural look. PBR lit so ships catch star/halo light.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3  part_color        : source_color = vec3(0.70, 0.72, 0.75);
uniform float roughness_val     : hint_range(0.0, 1.0) = 0.65;
uniform float metallic_val      : hint_range(0.0, 1.0) = 0.30;
uniform vec3  emission_color    : source_color = vec3(1.0, 0.60, 0.20);
uniform float emission_strength : hint_range(0.0, 10.0) = 0.0;
uniform bool  flat_shading      = true;

void fragment() {
    ALBEDO = part_color;
    ROUGHNESS = roughness_val;
    METALLIC = metallic_val;
    if (emission_strength > 0.0) {
        EMISSION = emission_color * emission_strength;
    }
    if (flat_shading) {
        vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
        if (dot(fn, NORMAL) < 0.0) { fn = -fn; }
        NORMAL = fn;
    }
}
