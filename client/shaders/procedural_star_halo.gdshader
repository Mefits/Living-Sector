shader_type spatial;
// Billboard glow quad: always faces the camera, so the radial gradient
// never shows polygon banding the way a fresnel-on-sphere does. Additive
// blend so the glow only ever brightens whatever's behind it. No depth
// write (glow shouldn't occlude anything), but we keep default depth
// *test* so planets in front of the star properly occlude the halo.
// cull_disabled to survive any weird billboard-matrix edge cases.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec3  glow_color     : source_color = vec3(1.0, 0.75, 0.35);
uniform float glow_intensity : hint_range(0.0, 8.0) = 2.0;
uniform float glow_falloff   : hint_range(0.5, 12.0) = 2.5;

void vertex() {
    // Standard Godot billboard-that-keeps-scale snippet. Copies the
    // inverse view's basis into MODELVIEW so the quad's local axes lock
    // to the camera, then reapplies the node's original scale.
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
        vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)
    );
}

void fragment() {
    // UV [0,1] → centered [-1,1]; distance from center is the radial
    // parameter. Clip the corners so the quad reads as a perfect disc
    // even at steep camera angles.
    vec2 centered = UV * 2.0 - 1.0;
    float d = length(centered);
    if (d > 1.0) { discard; }

    // `(1 - d)^falloff` gives a classic soft radial fall-off. Low
    // falloff = wide soft blob, high falloff = tight core with quick
    // fade. We stack two of these quads (different size / falloff) to
    // get a bright hot inner glow plus a wide cool corona.
    float a = pow(1.0 - d, glow_falloff);

    ALBEDO = glow_color;
    EMISSION = glow_color * glow_intensity * a;
    ALPHA = a;
}
