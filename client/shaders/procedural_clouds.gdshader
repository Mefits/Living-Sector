shader_type spatial;
// blend_mix + depth_draw_opaque is Godot's default; spelling it out so
// the shell blends correctly over the planet below and discards holes
// cleanly. cull_back keeps it one-sided (we only ever see the outer
// hemisphere). No specular — clouds shouldn't glint.
render_mode blend_mix, depth_draw_opaque, cull_back,
            diffuse_lambert, specular_disabled;

uniform vec3  cloud_color      : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_opacity    : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_coverage   : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_softness   : hint_range(0.001, 0.5) = 0.08;
uniform float cloud_frequency  : hint_range(0.1, 12.0) = 2.8;
uniform int   cloud_octaves    : hint_range(1, 6)     = 4;
uniform float cloud_lacunarity : hint_range(1.5, 3.5) = 2.1;
uniform float cloud_gain       : hint_range(0.2, 0.8) = 0.55;
uniform vec3  cloud_seed_offset = vec3(0.0);

varying vec3 v_obj_normal;

// Duplicated from procedural_planet.gdshader — GDShader has no #include,
// and keeping clouds self-contained lets us iterate without touching the
// planet shader.
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
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
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
        if (i >= cloud_octaves) { break; }
        sum += amp * value_noise(q);
        norm += amp;
        q *= cloud_lacunarity;
        amp *= cloud_gain;
    }
    return sum / max(norm, 0.0001);
}

void vertex() {
    v_obj_normal = normalize(NORMAL);
}

void fragment() {
    vec3 p = v_obj_normal + cloud_seed_offset;
    float h = fbm(p * cloud_frequency);

    // Above coverage threshold = cloud. `softness` feathers the edge so
    // clouds don't look like cookie-cutter stamps.
    float a = smoothstep(cloud_coverage,
                         cloud_coverage + cloud_softness,
                         h);

    // Drop fully-transparent fragments so the planet underneath shows
    // through cleanly without alpha-blend artifacts at the cloud edges.
    if (a < 0.01) {
        discard;
    }

    ALBEDO = cloud_color;
    ALPHA = a * cloud_opacity;
    ROUGHNESS = 0.9;
}
