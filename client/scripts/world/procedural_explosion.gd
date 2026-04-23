class_name ProceduralExplosion
extends Node3D

## One-shot explosion VFX, plays at `global_position` then self-frees.
## Four layers composed: flash light (brief illumination), fireball
## sphere (additive emissive expanding ball), shockwave ring (flat torus
## sweeping outward), debris sparks (GPU particles bursting out).
##
## Usage:
##   var boom := ProceduralExplosion.new()
##   parent.add_child(boom)
##   boom.global_position = target_pos
##   boom.play(size_hint)   # size_hint ≈ target's rendered radius
##
## Size autoscaling: `play(size)` clamps to [0.25, 2.0] world units so a
## tiny courier explosion is still readable while a facility explosion
## doesn't dwarf the host planet.

const LIFETIME         := 1.6     # total time before queue_free
const FLASH_DURATION   := 0.35
const FIREBALL_DURATION := 0.9
const SHOCKWAVE_DURATION := 0.8
const SPARK_LIFETIME   := 0.9

var _elapsed: float = 0.0
var _scale_mult: float = 1.0

var _flash_light: OmniLight3D
var _fireball: MeshInstance3D
var _fireball_mat: StandardMaterial3D
var _shockwave: MeshInstance3D
var _shockwave_mat: StandardMaterial3D


func play(entity_size: float = 0.1) -> void:
	## entity_size is the target's rendered half-extent in world units.
	## We scale the whole effect so it's ~4× the target silhouette.
	_scale_mult = clampf(entity_size * 4.0, 0.25, 2.0)
	_build_flash()
	_build_fireball()
	_build_shockwave()
	_build_sparks()
	# Procedural audio: bigger entities get a deeper, longer boom. Pass
	# our already-clamped scale so the sound mirrors the visual size.
	# Safe-call through /root/ProceduralAudio so that if the autoload
	# registration hasn't been picked up yet (e.g., Godot editor not
	# restarted after the project.godot change), the visuals still
	# fire and we just miss the sound.
	var audio: Node = get_node_or_null(^"/root/ProceduralAudio")
	if audio and audio.has_method(&"play_explosion"):
		audio.call(&"play_explosion", global_position, _scale_mult)


func _process(delta: float) -> void:
	_elapsed += delta

	# Flash: bright cone that snaps in and fades linearly. Stops
	# contributing light ~1/3 into the effect — after that the fireball
	# + bloom carry the glow.
	if _flash_light:
		var ft := clampf(_elapsed / FLASH_DURATION, 0.0, 1.0)
		_flash_light.light_energy = (1.0 - ft) * 10.0
		if ft >= 1.0:
			_flash_light.queue_free()
			_flash_light = null

	# Fireball: rapid expand to full size in the first ~20%, then
	# alpha-fade over the remainder. Scale-in curve is cube-root'd so
	# growth feels punchy up-front rather than linear.
	if _fireball and _fireball_mat:
		var bt := clampf(_elapsed / FIREBALL_DURATION, 0.0, 1.0)
		var grow_t := clampf(bt * 5.0, 0.0, 1.0)
		var grow := pow(grow_t, 0.35)    # easeOut-ish
		var size := lerpf(0.1, 1.0, grow) * _scale_mult
		_fireball.scale = Vector3(size, size, size)
		var a := 1.0 - bt
		var c := _fireball_mat.albedo_color
		_fireball_mat.albedo_color = Color(c.r, c.g, c.b, a)
		_fireball_mat.emission_energy_multiplier = lerpf(4.0, 0.0, bt)

	# Shockwave: a thin ring that keeps expanding past the fireball's
	# final size, fading alpha as it spreads. Slight Y-scale so it
	# always reads as a flat disc from above.
	if _shockwave and _shockwave_mat:
		var st := clampf(_elapsed / SHOCKWAVE_DURATION, 0.0, 1.0)
		var size := lerpf(0.1, 2.4, st) * _scale_mult
		_shockwave.scale = Vector3(size, 0.25 * size, size)
		var a := (1.0 - st) * 0.8
		var c := _shockwave_mat.albedo_color
		_shockwave_mat.albedo_color = Color(c.r, c.g, c.b, a)

	if _elapsed >= LIFETIME:
		queue_free()


# ---------------------------------------------------------------------------
# Layer builders
# ---------------------------------------------------------------------------

func _build_flash() -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.35)
	_flash_light.light_energy = 10.0
	_flash_light.omni_range = 5.0 * _scale_mult
	_flash_light.omni_attenuation = 1.5
	add_child(_flash_light)


func _build_fireball() -> void:
	var sphere := SphereMesh.new()
	# Unit sphere; we drive size via Node3D.scale in _process. Low poly
	# is fine — the additive blend hides facets.
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6

	_fireball_mat = StandardMaterial3D.new()
	_fireball_mat.albedo_color = Color(1.0, 0.65, 0.25, 0.9)
	_fireball_mat.emission_enabled = true
	_fireball_mat.emission = Color(1.0, 0.65, 0.25)
	_fireball_mat.emission_energy_multiplier = 4.0
	# Additive so the fireball only ever brightens what's behind it.
	_fireball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fireball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fireball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Don't occlude — shockwave + sparks should still blend through it.
	_fireball_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	_fireball = MeshInstance3D.new()
	_fireball.name = "Fireball"
	_fireball.mesh = sphere
	_fireball.material_override = _fireball_mat
	_fireball.scale = Vector3.ONE * 0.1 * _scale_mult
	add_child(_fireball)


func _build_shockwave() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.50
	torus.rings = 48
	torus.ring_segments = 6

	_shockwave_mat = StandardMaterial3D.new()
	_shockwave_mat.albedo_color = Color(1.0, 0.95, 0.55, 0.8)
	_shockwave_mat.emission_enabled = true
	_shockwave_mat.emission = Color(1.0, 0.95, 0.55)
	_shockwave_mat.emission_energy_multiplier = 3.0
	_shockwave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shockwave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shockwave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_shockwave = MeshInstance3D.new()
	_shockwave.name = "Shockwave"
	_shockwave.mesh = torus
	_shockwave.material_override = _shockwave_mat
	_shockwave.scale = Vector3.ONE * 0.1 * _scale_mult
	add_child(_shockwave)


func _build_sparks() -> void:
	## Burst of debris specks in a sphere pattern. one_shot + explosiveness
	## = 1.0 means all `amount` particles spawn simultaneously on the
	## first frame, then die off naturally over `lifetime`.
	var particles := GPUParticles3D.new()
	particles.name = "Sparks"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 40
	particles.lifetime = SPARK_LIFETIME
	particles.emitting = true
	particles.visibility_aabb = AABB(
		Vector3.ONE * -4.0 * _scale_mult,
		Vector3.ONE * 8.0 * _scale_mult,
	)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.02 * _scale_mult
	mat.direction = Vector3(0, 1, 0)       # spread 180° makes direction moot
	mat.spread = 180.0                     # full sphere
	mat.initial_velocity_min = 1.5 * _scale_mult
	mat.initial_velocity_max = 4.5 * _scale_mult
	mat.gravity = Vector3.ZERO
	mat.damping_min = 1.5
	mat.damping_max = 3.5
	mat.scale_min = 0.008 * _scale_mult
	mat.scale_max = 0.020 * _scale_mult
	mat.color = Color(1.0, 0.8, 0.3, 1.0)

	var color_ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.55, 1.0))
	gradient.set_color(1, Color(0.40, 0.10, 0.03, 0.0))
	color_ramp.gradient = gradient
	mat.color_ramp = color_ramp

	particles.process_material = mat

	var quad := QuadMesh.new()
	particles.draw_pass_1 = quad

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Same trick we use on ship exhaust — without this, billboard mode
	# ignores per-particle scale and renders everything at a fixed size.
	draw_mat.billboard_keep_scale = true
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = draw_mat

	add_child(particles)
