shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ---- Palette --------------------------------------------------------------
uniform vec3 color_low     : source_color = vec3(0.20, 0.35, 0.15);
uniform vec3 color_mid     : source_color = vec3(0.45, 0.38, 0.22);
uniform vec3 color_high    : source_color = vec3(0.80, 0.78, 0.75);
uniform vec3 sea_color     : source_color = vec3(0.05, 0.18, 0.40);
uniform vec3 pole_color    : source_color = vec3(0.95, 0.97, 1.00);
uniform vec3 emission_color: source_color = vec3(1.00, 0.35, 0.05);

// ---- Shape knobs ----------------------------------------------------------
uniform bool  sea_enabled      = true;
uniform float sea_level        : hint_range(0.0, 1.0) = 0.45;
uniform float pole_threshold   : hint_range(0.0, 1.0) = 0.78;
uniform float pole_softness    : hint_range(0.001, 0.5) = 0.08;

uniform float noise_frequency  : hint_range(0.1, 12.0) = 2.0;
uniform int   noise_octaves    : hint_range(1, 6)      = 4;
uniform float noise_lacunarity : hint_range(1.5, 3.5)  = 2.0;
uniform float noise_gain       : hint_range(0.2, 0.8)  = 0.5;
uniform float noise_warp       : hint_range(0.0, 2.0)  = 0.0;

uniform float band_strength    : hint_range(0.0, 1.0) = 0.0;

uniform float emission_strength: hint_range(0.0, 4.0) = 0.0;
uniform float emission_cutoff  : hint_range(0.0, 1.0) = 0.6;

uniform bool  flat_shading     = true;
uniform float roughness_val    : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_val     : hint_range(0.0, 1.0) = 0.0;

uniform vec3  seed_offset      = vec3(0.0);

varying vec3 v_obj_normal;

// ---- Noise ----------------------------------------------------------------
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
        if (i >= noise_octaves) { break; }
        sum += amp * value_noise(q);
        norm += amp;
        q *= noise_lacunarity;
        amp *= noise_gain;
    }
    return sum / max(norm, 0.0001);
}

// ---- Stages ---------------------------------------------------------------
void vertex() {
    v_obj_normal = normalize(NORMAL);
}

void fragment() {
    // Sample position on the unit sphere, in object space.
    vec3 p = v_obj_normal;

    // Gas-giant style latitudinal banding: squish Y so bands read as stripes.
    p.y *= 1.0 + band_strength * 6.0;

    // Seed offset jitters the noise domain deterministically per planet.
    p += seed_offset;

    // Optional domain warp for more organic shapes.
    if (noise_warp > 0.0) {
        float w = value_noise(p * noise_frequency * 0.5);
        p += vec3(w - 0.5) * noise_warp;
    }

    float h = fbm(p * noise_frequency);

    vec3 col;
    if (sea_enabled && h < sea_level) {
        // Smooth depth shading underwater
        float d = sea_level > 0.0 ? h / sea_level : 1.0;
        col = sea_color * mix(0.55, 1.0, d);
    } else {
        float denom = max(1.0 - sea_level, 0.0001);
        float t = sea_enabled ? (h - sea_level) / denom : h;
        t = clamp(t, 0.0, 1.0);
        col = mix(color_low, color_mid, smoothstep(0.0, 0.5, t));
        col = mix(col, color_high, smoothstep(0.5, 1.0, t));
    }

    // Polar caps driven by latitude (|y| on the sphere normal).
    float lat = abs(v_obj_normal.y);
    float polar = smoothstep(pole_threshold,
                             pole_threshold + pole_softness,
                             lat);
    col = mix(col, pole_color, polar);

    ALBEDO = col;
    ROUGHNESS = roughness_val;
    METALLIC = metallic_val;

    if (emission_strength > 0.0) {
        float e = smoothstep(emission_cutoff, 1.0, h);
        EMISSION = emission_color * e * emission_strength;
    }

    if (flat_shading) {
        // Derivative-based face normal — gives the low-poly faceted look
        // without needing duplicated-vertex geometry. Flip sign if it
        // disagrees with the interpolated smooth normal so lighting stays
        // on the correct side under Godot's winding.
        vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
        if (dot(fn, NORMAL) < 0.0) { fn = -fn; }
        NORMAL = fn;
    }
}
