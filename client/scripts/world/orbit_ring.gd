extends MeshInstance3D

## Draws a thin circle representing an orbital path around a system center.

const RING_COLOR := Color(0.3, 0.3, 0.5, 0.25)
const SEGMENTS := 64


func setup(orbit_radius: float) -> void:
	var scaled_radius: float = orbit_radius * GameState.SCALE_FACTOR
	var im := ImmediateMesh.new()
	mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RING_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	material_override = mat

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(SEGMENTS + 1):
		var angle := (float(i) / SEGMENTS) * TAU
		var x := cos(angle) * scaled_radius
		var z := sin(angle) * scaled_radius
		im.surface_add_vertex(Vector3(x, 0.02, z))
	im.surface_end()
