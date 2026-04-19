extends Node3D

## Starfield in two parts:
##   1. A procedural sky shader on a WorldEnvironment — renders stars at
##      infinite distance in every direction, so POV / horizontal camera
##      angles always have a starry backdrop instead of empty void.
##   2. Three parallax planes BELOW the camera — add close-range depth
##      when panning in top-down mode. They ride on top of the sky via
##      alpha so the sky shows through gaps.

const LAYER_COUNT := 3
const LAYER_DEPTHS: Array[float] = [-5.0, -20.0, -50.0]
const LAYER_SIZES: Array[float] = [800.0, 1600.0, 3000.0]
const LAYER_STAR_DENSITY: Array[float] = [200.0, 120.0, 80.0]
const LAYER_BRIGHTNESS: Array[float] = [0.9, 0.6, 0.35]
const LAYER_STAR_SIZE: Array[float] = [1.2, 1.0, 0.7]

var _camera: Camera3D
var _planes: Array[MeshInstance3D] = []
var _world_env: WorldEnvironment

const SKY_SHADER_CODE := "
shader_type sky;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Render a round point star within each grid cell. `scale` controls
// cell density. `threshold` gates how many cells spawn a star.
// `size_mul` controls visual star size, `brightness` the intensity.
vec3 star_layer(
	vec3 dir,
	float scale,
	float threshold,
	float size_mul,
	float brightness,
	vec3 tint,
	float seed
) {
	vec3 cell = floor(dir * scale);
	vec3 f = fract(dir * scale);
	float rnd = hash31(cell + seed);
	if (rnd <= threshold) {
		return vec3(0.0);
	}
	// Position the star somewhere inside the cell (not always centered).
	vec3 center = vec3(
		hash31(cell + seed + 0.31),
		hash31(cell + seed + 0.62),
		hash31(cell + seed + 0.93)
	);
	float d = length(f - center);
	// Bigger / brighter for higher rnd so the field has variety.
	float radius = (rnd - threshold) * size_mul / (1.0 - threshold);
	float s = 1.0 - smoothstep(0.0, radius, d);
	return tint * s * brightness;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = vec3(0.0);

	// Bright named stars — sparse, warm/cool variation, twinkle.
	// These are the ones you actually notice.
	float tw = sin(TIME * 0.9 + hash31(floor(dir * 180.0)) * 30.0) * 0.3 + 0.7;
	vec3 warm = vec3(1.0, 0.92, 0.78);
	vec3 cool = vec3(0.82, 0.9, 1.0);
	float hue_mix = hash31(floor(dir * 180.0) + 1.7);
	col += star_layer(
		dir, 180.0, 0.97, 0.18, 1.6 * tw,
		mix(cool, warm, hue_mix), 0.0
	);

	// Mid band — smaller, neutral white so accumulated contribution
	// stays color-neutral instead of painting the sky cool.
	col += star_layer(
		dir, 380.0, 0.985, 0.12, 0.9,
		vec3(0.95, 0.95, 0.95), 5.1
	);

	// Fine dust — tiny points, white, very sparse so we don't fog
	// the whole sky with almost-star contributions.
	col += star_layer(
		dir, 760.0, 0.995, 0.08, 0.5,
		vec3(0.9, 0.9, 0.9), 11.3
	);

	COLOR = col;
}
"

const STAR_SHADER_CODE := "
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float density = 100.0;
uniform float brightness = 0.8;
uniform float star_size = 1.0;
uniform float twinkle_speed = 0.8;

// Hash functions for procedural stars
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(443.8975, 397.2973, 491.1871));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

float star(vec2 uv, float size) {
    vec2 grid = floor(uv * density);
    vec2 f = fract(uv * density);

    float rnd = hash(grid);
    if (rnd > 0.92) {
        vec2 center = vec2(hash(grid + 0.1), hash(grid + 0.2));
        float d = length(f - center);
        float radius = (rnd - 0.92) * 0.8 * size;
        float s = 1.0 - smoothstep(0.0, radius, d);
        // Twinkle
        float twinkle = sin(TIME * twinkle_speed * (rnd * 5.0 + 1.0)) * 0.3 + 0.7;
        return s * twinkle;
    }
    return 0.0;
}

void fragment() {
    vec2 uv = UV * 10.0;
    float s = star(uv, star_size);

    // Slight color variation
    float rnd = hash(floor(uv * density));
    vec3 col = mix(
        vec3(0.8, 0.85, 1.0),
        vec3(1.0, 0.9, 0.7),
        rnd
    );

    ALBEDO = col * s * brightness;
    ALPHA = s * brightness;
}
"


func setup(camera: Camera3D) -> void:
	_camera = camera
	_setup_sky()
	_setup_parallax_planes()


func _setup_sky() -> void:
	# Procedural star sky rendered at infinite distance. Gives POV /
	# horizontal camera angles a starry backdrop the parallax planes
	# can't cover (the planes are all below the camera).
	#
	# main.tscn already has a WorldEnvironment using a ProceduralSky
	# that paints the sky dark-blue and the "ground" dark-grey —
	# Godot uses one WorldEnvironment globally, so adding a second
	# here would be shadowed. Instead, patch the existing environment
	# in place with our star shader. Preserves its ambient lighting
	# settings.
	var sky_shader := Shader.new()
	sky_shader.code = SKY_SHADER_CODE
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var wenv: WorldEnvironment = _find_world_env(get_tree().root)
	if wenv != null and wenv.environment != null:
		wenv.environment.sky = sky
		wenv.environment.background_mode = Environment.BG_SKY
		_world_env = wenv
		return

	# Fallback when no WorldEnvironment exists in the scene.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	_world_env = WorldEnvironment.new()
	_world_env.environment = env
	add_child(_world_env)


func _find_world_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var found: WorldEnvironment = _find_world_env(c)
		if found != null:
			return found
	return null


func _setup_parallax_planes() -> void:
	var shader := Shader.new()
	shader.code = STAR_SHADER_CODE

	for i in range(LAYER_COUNT):
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = Vector2(LAYER_SIZES[i], LAYER_SIZES[i])

		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("density", LAYER_STAR_DENSITY[i])
		mat.set_shader_parameter("brightness", LAYER_BRIGHTNESS[i])
		mat.set_shader_parameter("star_size", LAYER_STAR_SIZE[i])
		mat.set_shader_parameter("twinkle_speed", 0.5 + i * 0.3)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = plane_mesh
		mesh_inst.material_override = mat
		mesh_inst.position.y = LAYER_DEPTHS[i]
		# Render behind everything
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		add_child(mesh_inst)
		_planes.append(mesh_inst)


func _process(_delta: float) -> void:
	if not _camera:
		return

	# Keep star planes centered under the camera so they never run out
	for plane in _planes:
		plane.position.x = _camera.position.x
		plane.position.z = _camera.position.z
