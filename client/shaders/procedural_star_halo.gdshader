shader_type spatial;
// Additive blend so the halo only brightens whatever's behind it — never
// darkens space. depth_draw_never keeps the halo from occluding other
// stars behind it. cull_back lets us skip the back hemisphere; from the
// camera's POV the front hemisphere is what forms the soft glow.
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec3  halo_color     : source_color = vec3(1.0, 0.75, 0.35);
uniform float halo_intensity : hint_range(0.0, 8.0) = 2.0;
uniform float halo_power     : hint_range(0.5, 8.0) = 2.5;
uniform float halo_floor     : hint_range(0.0, 1.0) = 0.05;

void fragment() {
    // Limb fresnel: fragments whose normal is perpendicular to the view
    // direction (i.e. the silhouette of the shell) get full weight; the
    // fragment directly facing the camera gets near zero. On a shell
    // around a star this draws the classic soft corona ring.
    vec3 n = normalize(NORMAL);
    vec3 v = normalize(VIEW);
    float fresnel = 1.0 - clamp(abs(dot(n, v)), 0.0, 1.0);
    float a = pow(fresnel, halo_power) + halo_floor;

    ALBEDO = halo_color;
    EMISSION = halo_color * halo_intensity * a;
    ALPHA = a;
}
