shader_type spatial;
// Additive emissive cloud. blend_add lets it stack against stars
// without darkening anything; depth_draw_never means it never
// occludes geometry behind it; cull_disabled so the cloud renders
// whether the camera is inside or outside the volume. Unshaded
// because the cloud is its own light source (emission only).
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3  primary_color    : source_color = vec3(0.80, 0.35, 0.95);
uniform vec3  secondary_color  : source_color = vec3(0.25, 0.60, 1.00);
uniform float density          : hint_range(0.0, 3.0) = 1.0;
uniform float brightness       : hint_range(0.0, 6.0) = 1.8;
uniform float noise_frequency  : hint_range(0.1, 8.0) = 1.6;
uniform int   noise_octaves    : hint_range(1, 6)    = 4;
uniform float noise_warp       : hint_range(0.0, 2.0) = 0.75;
uniform float wisp_strength    : hint_range(0.0, 2.0) = 0.9;
uniform float radial_falloff   : hint_range(4.9, 8.0) = 5.2;
uniform float color_mix_shift  : hint_range(0.0, 1.0) = 0.5;
uniform float color_mix_band   : hint_range(0.05, 0.5) = 0.22;
uniform float density_threshold : hint_range(0.62, 0.8) = 0.66;
uniform vec3  seed_offset      = vec3(0.0);

varying vec3 v_local_pos;

// Noise — same self-contained fbm / value-noise pattern as the rest
// of the procedural shaders in this project. gdshader has no
// #include; keeping it inline also lets each nebula shader be tuned
// independently if we ever want different fbm variants.
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
    // VERTEX is in model-local space — for a unit-ish sphere this
    // gives us coordinates in roughly [-1, +1] which the radial
    // falloff below uses directly.
    v_local_pos = VERTEX;
}

void fragment() {
    vec3 p = v_local_pos + seed_offset;

    // Domain warp — displaces the sampling position by fbm of itself.
    // This is what gives a nebula its filamentary, streaky structure
    // rather than a uniform noise blob.
    if (noise_warp > 0.0) {
        vec3 warp = vec3(
            fbm(p * noise_frequency * 0.5),
            fbm(p * noise_frequency * 0.5 + vec3(100.0)),
            fbm(p * noise_frequency * 0.5 + vec3(200.0))
        );
        p += (warp - 0.5) * noise_warp;
    }

    // Core density field.
    float n = fbm(p * noise_frequency);

    // Wisp layer — modulates the core density by a higher-frequency
    // noise so we get bright filaments within the broader cloud.
    if (wisp_strength > 0.0) {
        float wisps = fbm(p * noise_frequency * 2.5);
        n = mix(n, n * wisps * 1.8, wisp_strength);
    }

    // Silhouette fade. This is a surface shader, not a ray-march, so
    // every fragment sits at length(v_local_pos) ≈ 1.0 — a pure-radial
    // `1.0 - dist` falloff would zero out everywhere the fragment
    // actually runs and the sphere would render fully transparent.
    // Instead we fade by view angle: fragments whose normal points at
    // the camera (disc center) stay opaque; fragments at the silhouette
    // rim fade to zero.
    float view_face = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
    // Break up the silhouette with a second, low-frequency noise so
    // the cloud doesn't read as a perfect disc. Positive displacement
    // pushes the disc outward (tendrils), negative carves into it
    // (holes). Scale chosen so mid-cloud stays solid while the rim
    // turns into wisps.
    float edge_carve = fbm(
        (v_local_pos + seed_offset + vec3(37.0)) * noise_frequency * 0.7
    );
    float silhouette = clamp(
        view_face + (edge_carve - 0.5) * 0.55,
        0.0, 1.0
    );
    float radial = pow(silhouette, radial_falloff);

    // Density threshold: clip noise values below `threshold` so the
    // cloud has gaps rather than being a uniform glow. Remap what's
    // left to 0..1 so threshold doesn't crush overall brightness.
    n = max(n - density_threshold, 0.0) / max(1.0 - density_threshold, 0.0001);

    // `n * n` sharpens the alpha curve: sparse noise regions drop
    // rapidly toward transparent rather than rendering as a dim haze,
    // so the cloud reads as patchy tendrils and holes instead of a
    // uniform glow. 2.0 multiplier keeps peak brightness roughly
    // where it was before the square.
    float a = n * n * 2.0 * radial * density;
    a = clamp(a, 0.0, 1.0);

    // Two-color blend driven by the noise value. `color_mix_shift`
    // picks the crossover threshold; `color_mix_band` controls how
    // soft the blend is. Inside the band the colors mix; outside,
    // you get a near-pure primary or secondary.
    float mix_t = smoothstep(
        color_mix_shift - color_mix_band,
        color_mix_shift + color_mix_band,
        n
    );
    vec3 col = mix(primary_color, secondary_color, mix_t);

    ALBEDO = col;
    EMISSION = col * a * brightness;
    ALPHA = a;
}
