shader_type spatial;
// Unshaded so the star isn't darkened by its own omnilight, and emission
// goes way above 1.0 to feed glow/bloom. No culling of the back face
// needed — cull_back default is fine because we only ever see the front.
render_mode unshaded, cull_back;

uniform vec3 star_color_core : source_color = vec3(1.0, 1.0, 0.92);
uniform vec3 star_color_mid  : source_color = vec3(1.0, 0.80, 0.32);
uniform vec3 star_color_edge : source_color = vec3(1.0, 0.45, 0.12);
uniform float emission_strength : hint_range(1.0, 10.0) = 4.5;
uniform float noise_frequency   : hint_range(0.5, 8.0)  = 2.5;
uniform int   noise_octaves     : hint_range(1, 6)      = 4;
uniform float flow_speed        : hint_range(0.0, 2.0)  = 0.35;
uniform float limb_darkening    : hint_range(0.0, 1.0)  = 0.35;
uniform vec3  seed_offset       = vec3(0.0);

varying vec3 v_obj_normal;
varying vec3 v_view_dir;

// Noise — same value-noise/fbm as the planet shader. Kept self-contained
// because gdshader has no includes.
float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i);
    float n100 = hash13(i + vec3(1, 0, 0));
    float n010 = hash13(i + vec3(0, 1, 0));
    float n110 = hash13(i + vec3(1, 1, 0));
    float n001 = hash13(i + vec3(0, 0, 1));
    float n101 = hash13(i + vec3(1, 0, 1));
    float n011 = hash13(i + vec3(0, 1, 1));
    float n111 = hash13(i + vec3(1, 1, 1));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
    float amp = 0.5;
    float sum = 0.0;
    float norm = 0.0;
    vec3 q = p;
    for (int i = 0; i < 6; i++) {
        if (i >= noise_octaves) { break; }
        sum += amp * value_noise(q);
        norm += amp;
        q *= 2.05;
        amp *= 0.55;
    }
    return sum / max(norm, 0.0001);
}

void vertex() {
    v_obj_normal = normalize(NORMAL);
}

void fragment() {
    // Flowing plasma: sample fbm at the sphere normal, advect with TIME.
    // Two samples at slightly different frequencies + offsets give the
    // "convection cells drifting" look without extra uniforms.
    vec3 p = v_obj_normal + seed_offset;
    float t = TIME * flow_speed * 0.1;
    float a = fbm(p * noise_frequency + vec3(t, -t * 0.6, t * 0.3));
    float b = fbm(p * noise_frequency * 1.7 + vec3(-t * 0.4, t, -t * 0.8));
    float n = clamp(a * 0.6 + b * 0.4, 0.0, 1.0);

    // Gradient: edge → mid → core as n rises. Quiet regions read dim,
    // bright cells read near-white.
    vec3 c = mix(star_color_edge, star_color_mid, smoothstep(0.0, 0.5, n));
    c = mix(c, star_color_core, smoothstep(0.55, 0.9, n));

    // Slight limb darkening — fragments near the silhouette read a touch
    // dimmer, which sells the sphere shape against the halo behind it.
    // NORMAL + VIEW are both in view space here; v_obj_normal stays in
    // object space for stable noise sampling as the scene moves.
    float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
    float limb = 1.0 - (1.0 - ndv) * limb_darkening;

    ALBEDO = c;
    EMISSION = c * emission_strength * limb;
}
