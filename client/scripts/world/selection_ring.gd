extends MeshInstance3D

## Pulsing selection ring drawn around the selected entity.

const RING_COLOR := Color(1.0, 0.9, 0.2, 0.7)
const SEGMENTS := 32
const RING_RADIUS := 0.6

var _time := 0.0


func _ready() -> void:
	var im := ImmediateMesh.new()
	mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RING_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 1
	material_override = mat

	_build_ring(im, RING_RADIUS)


func _build_ring(im: ImmediateMesh, radius: float) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(SEGMENTS + 1):
		var angle := (float(i) / SEGMENTS) * TAU
		im.surface_add_vertex(Vector3(
			cos(angle) * radius, 0.1, sin(angle) * radius
		))
	im.surface_end()


func _process(delta: float) -> void:
	_time += delta
	# Gentle pulse
	var alpha := 0.5 + 0.3 * sin(_time * 4.0)
	var mat: StandardMaterial3D = material_override
	mat.albedo_color.a = alpha
