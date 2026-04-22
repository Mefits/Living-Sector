extends Node3D

## Renders a ship with a 3D model based on ship class.
## Uses GPS-style displacement window for stable heading and speed.

var ship_id: String
var ship_class: String

var _prev_pos: Vector3
var _next_pos: Vector3
var _lerp_t: float = 1.0
var _model: Node3D
var _particles: GPUParticles3D
var _label: Label3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh

# Gate-warp streak: separate mesh so the warp segment can render with
# its own colour / blending and fade out on its own timeline without
# interfering with the regular flight trail.
var _warp: MeshInstance3D
var _warp_mesh: ImmediateMesh
var _warp_from: Vector3
var _warp_to: Vector3
var _warp_elapsed: float = 0.0
var _warp_active: bool = false
const WARP_LIFETIME := 1.6        # seconds to fully fade
const WARP_SEGMENTS := 24         # sub-divisions so the streak can curve + pulse
const WARP_COLOR_CORE := Color(0.55, 0.35, 1.0, 1.0)   # violet core
const WARP_COLOR_EDGE := Color(0.35, 0.75, 1.0, 1.0)   # cyan edges

# GPS-style heading from position history
const HEADING_WINDOW := 20  # ticks for heading calculation
const TRAIL_LENGTH := 60    # ticks of trail (~7.5 sec at 8 tps)
var _pos_history: Array[Vector3] = []
var _trail_history: Array[Vector3] = []
var _target_heading: float = 0.0
var _speed: float = 0.0
var _is_moving := false

# World-space size multiplier applied to every ProceduralShip. A
# medium-tier freighter (hull ≈ 3 raw units × SIZE_MEDIUM 1.0 × this) lands
# at ~0.075 world units — comfortably smaller than Earth at 0.32 — and a
# massive-tier hauler lands around ~0.25 world units. Tune here if ships
# start reading too small or too large against the planets.
const SHIP_RENDER_SCALE := 0.025

# Engine burn particle settings
const PARTICLE_BASE_LIFETIME := 0.6
const PARTICLE_MAX_LIFETIME := 4.0
const SPEED_FOR_MAX_BURN := 15.0


func setup(data: Dictionary) -> void:
	ship_id = data.get("id", "")
	ship_class = data.get("class", "")

	var pos_data = data.get("position", {})
	var x: float = pos_data.get("x", 0.0) if pos_data is Dictionary else 0.0
	var y: float = pos_data.get("y", 0.0) if pos_data is Dictionary else 0.0
	_next_pos = GameState.server_to_world(x, y)
	_prev_pos = _next_pos
	position = _next_pos

	# Build a ProceduralShip from the server's class/size/faction. Wrapped
	# in a pivot so (a) the heading math on `self` stays clean and
	# (b) the pivot applies the world-render scale without fighting the
	# ProceduralShip's own SIZE_SCALES → internal scale chain. Pivot is
	# rotated 180° around Y because ProceduralShip's forward is -Z while
	# the atan2-driven heading here assumes +Z forward.
	var proc_class := ProceduralShip.class_from_name(ship_class)
	var size_str: String = str(data.get("size", ""))
	var proc_size: int
	if size_str != "":
		proc_size = ProceduralShip.size_from_name(size_str)
	else:
		# Dictionary.get() returns Variant; int() it so strict typing on
		# proc_size sticks and the subsequent setter doesn't complain.
		proc_size = int(ProceduralShip.CLASS_DEFAULT_SIZE.get(
			proc_class, ProceduralShip.ShipSize.MEDIUM
		))
	var faction: String = str(data.get("faction_id", ""))
	# Stable seed per ship so re-spawn / reconnect keeps the same ship
	# silhouette. Mask the sign bit because hash() can return negatives
	# and ProceduralShip stores seed as a positive int.
	var ship_seed_int: int = int(hash(ship_id)) & 0x7FFFFFFF

	var pivot := Node3D.new()
	pivot.name = "ShipPivot"
	pivot.rotation = Vector3(0, PI, 0)
	pivot.scale = Vector3.ONE * SHIP_RENDER_SCALE
	add_child(pivot)

	var proc_ship := ProceduralShip.new()
	proc_ship.name = "ProceduralShip"
	# Set properties BEFORE add_child so _ready's initial _rebuild runs
	# with the final class/size — avoids one extra throwaway rebuild when
	# each setter would otherwise trigger it in sequence.
	proc_ship.ship_class = proc_class
	proc_ship.ship_size = proc_size
	proc_ship.faction_id = faction
	proc_ship.ship_seed = ship_seed_int
	pivot.add_child(proc_ship)
	_model = pivot

	# Ship name label
	_label = $Label3D
	_label.text = data.get("name", ship_id)
	_label.visible = false  # Shown only at close zoom

	# Faction marker: small orange star above the-doughtys ships.
	# Billboarded + no-depth so it floats above the ship no matter the
	# camera angle. Scales with distance like everything else — fixed_size
	# at a 64pt font turned the whole viewport orange.
	if str(data.get("faction_id", "")) == "the-doughtys":
		var star := Label3D.new()
		star.text = "\u2605"  # ★
		star.modulate = Color(1.0, 0.6, 0.15)
		star.font_size = 16
		star.pixel_size = 0.003
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.no_depth_test = true
		star.position = Vector3(0.0, 0.5, 0.0)
		add_child(star)

	GameState.zoom_changed.connect(_on_zoom_changed)
	_on_zoom_changed(GameState.zoom_tier, GameState.zoom_raw)

	_setup_trail()
	_setup_warp()
	_setup_particles()


func _setup_trail() -> void:
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = -2
	_trail.material_override = mat
	# Trail is a sibling, not a child — so it doesn't rotate with the ship
	# We add it to the parent in _ready or after being added to tree
	_trail.top_level = true
	add_child(_trail)


func _setup_warp() -> void:
	_warp_mesh = ImmediateMesh.new()
	_warp = MeshInstance3D.new()
	_warp.mesh = _warp_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# Additive blending makes the streak read as "light" instead of a
	# painted line — key to it looking like an FTL jump rather than a
	# trail.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = true
	mat.render_priority = -1
	_warp.material_override = mat
	_warp.top_level = true
	add_child(_warp)


## Kick off a warp-streak render between two world positions. Called when
## a gate jump is detected (position discontinuity in `update_position`).
func _begin_warp(from_pos: Vector3, to_pos: Vector3) -> void:
	_warp_from = from_pos
	_warp_to = to_pos
	_warp_elapsed = 0.0
	_warp_active = true


## Redraws the warp streak each frame while it's active. Two overlapping
## line strips — a bright violet core plus a thicker cyan halo — with a
## sinusoidal pulse along the length so it reads as "energy" rather than
## a static line. Whole thing fades out over `WARP_LIFETIME`.
func _update_warp(delta: float) -> void:
	_warp_mesh.clear_surfaces()
	if not _warp_active:
		return
	_warp_elapsed += delta
	if _warp_elapsed >= WARP_LIFETIME:
		_warp_active = false
		return
	var life_t := _warp_elapsed / WARP_LIFETIME  # 0 → 1
	# Ease-out fade: bright for most of it, fast falloff at end.
	var fade := 1.0 - pow(life_t, 2.5)
	var dir := _warp_to - _warp_from
	# Draw two passes — halo first (cyan, wider effect via additive), then
	# core (violet). Both use the same vertex trail but different colours
	# and alphas so additive blending stacks into white-hot midline.
	for pass_i in range(2):
		var base_col: Color = WARP_COLOR_EDGE if pass_i == 0 else WARP_COLOR_CORE
		var pass_alpha: float = (0.55 if pass_i == 0 else 0.9) * fade
		_warp_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in range(WARP_SEGMENTS + 1):
			var t: float = float(i) / float(WARP_SEGMENTS)
			var p: Vector3 = _warp_from + dir * t
			# Subtle brightness pulse along the streak so it doesn't look
			# dead-flat. Fastest at the middle, calm at the ends.
			var pulse: float = 1.0 + 0.35 * sin(t * PI * 4.0 - life_t * 8.0)
			# Ends of the streak fade slightly faster than the middle so
			# the jump looks "launched" rather than a hard-cut stripe.
			var end_fade: float = sin(t * PI)
			var col := Color(
				base_col.r * pulse,
				base_col.g * pulse,
				base_col.b * pulse,
				pass_alpha * end_fade,
			)
			_warp_mesh.surface_set_color(col)
			_warp_mesh.surface_add_vertex(Vector3(p.x, 0.04, p.z))
		_warp_mesh.surface_end()


func _update_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_history.size() < 3 or not _is_moving:
		return

	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var count := _trail_history.size()
	for i in range(count):
		# t goes 0 (oldest) to 1 (newest)
		var t := float(i) / float(count - 1)
		var alpha := t * t * 0.35
		# Color shifts from red (old) to orange/yellow (new)
		var col := Color(
			1.0,
			0.3 + t * 0.4,
			0.1,
			alpha
		)
		_trail_mesh.surface_set_color(col)
		var pos: Vector3 = _trail_history[i]
		_trail_mesh.surface_add_vertex(Vector3(pos.x, 0.03, pos.z))
	_trail_mesh.surface_end()


func _setup_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 16
	_particles.lifetime = PARTICLE_BASE_LIFETIME
	_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.3
	mat.scale_max = 0.6
	mat.color = Color(0.8, 0.5, 0.2, 0.9)

	var color_ramp := GradientTexture1D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.9, 0.6, 0.2, 1.0))
	gradient.set_color(1, Color(0.3, 0.1, 0.05, 0.0))
	color_ramp.gradient = gradient
	mat.color_ramp = color_ramp

	_particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	_particles.draw_pass_1 = quad

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	quad.material = draw_mat

	add_child(_particles)


## Position jump big enough to be a gate teleport — clear the trail/history
## so we don't draw a phantom line across the universe between the pre-jump
## and post-jump positions. Tuned larger than any realistic single-tick
## velocity step but smaller than inter-system distances.
const TELEPORT_JUMP_THRESHOLD := 3.0

func update_position(x: float, y: float) -> void:
	_prev_pos = _next_pos
	_next_pos = GameState.server_to_world(x, y)
	_lerp_t = 0.0

	# Detect discontinuity (gate jump) — if the ship teleported, wipe the
	# regular trail so prior positions from the other side of the
	# universe don't connect to where the ship is now, and kick off a
	# warp-streak render between the two endpoints (violet/cyan, fades
	# over ~1.5s) so the player sees that a jump happened instead of the
	# ship silently reappearing somewhere else.
	if _prev_pos.distance_to(_next_pos) > TELEPORT_JUMP_THRESHOLD:
		_begin_warp(_prev_pos, _next_pos)
		_pos_history.clear()
		_trail_history.clear()
		_prev_pos = _next_pos  # skip the lerp through the void

	# Add to position history ring buffers
	_pos_history.append(_next_pos)
	if _pos_history.size() > HEADING_WINDOW:
		_pos_history.remove_at(0)

	_trail_history.append(_next_pos)
	if _trail_history.size() > TRAIL_LENGTH:
		_trail_history.remove_at(0)

	# Compute heading and speed from displacement window
	_update_heading_from_history()
	_update_trail()


func _update_heading_from_history() -> void:
	if _pos_history.size() < 2:
		_is_moving = false
		return

	var oldest: Vector3 = _pos_history[0]
	var newest: Vector3 = _pos_history[-1]
	var displacement := newest - oldest
	var dist := displacement.length()

	if dist > 0.1:
		# Clear movement — update heading and speed
		_target_heading = atan2(displacement.x, displacement.z)
		_is_moving = true
		var window_secs: float = (
			_pos_history.size() * GameState.get_effective_interval_seconds()
		)
		_speed = dist / window_secs if window_secs > 0.0 else 0.0
	elif dist < 0.01:
		# Truly stationary
		_is_moving = false
		_speed = 0.0
	# else: in dead zone — keep last heading and moving state


func _process(delta: float) -> void:
	# Position interpolation
	if _lerp_t < 1.0:
		var interval := GameState.get_effective_interval_seconds()
		_lerp_t = minf(_lerp_t + delta / interval, 1.0)
		var t := _lerp_t * _lerp_t * (3.0 - 2.0 * _lerp_t)
		position = _prev_pos.lerp(_next_pos, t)

	# Warp streak fade — advances on wall-clock, independent of sim speed.
	if _warp_active:
		_update_warp(delta)

	# Smooth rotation toward window-derived heading
	if _is_moving:
		var diff := wrapf(_target_heading - rotation.y, -PI, PI)
		rotation.y += diff * minf(delta * 3.0, 1.0)

	# Engine burn particles — scale with speed, off when docked
	var ship_data: Dictionary = GameState.ships.get(ship_id, {})
	var loc: Variant = ship_data.get("location")
	var is_docked: bool = (
		loc != null and str(loc) != "null" and str(loc) != ""
	)
	if _is_moving and _speed > 0.05 and not is_docked:
		_particles.emitting = true
		var burn_t := clampf(_speed / SPEED_FOR_MAX_BURN, 0.0, 1.0)
		_particles.lifetime = lerpf(
			PARTICLE_BASE_LIFETIME, PARTICLE_MAX_LIFETIME, burn_t
		)
		_particles.amount = int(lerpf(8, 24, burn_t))
	else:
		_particles.emitting = false


func _on_zoom_changed(tier: GameState.ZoomTier, _raw: float) -> void:
	# Ship names only visible at CLOSE zoom
	if _label:
		_label.visible = (tier == GameState.ZoomTier.CLOSE)
