@tool
extends MeshInstance3D
## Procedurally builds a gently-irregular island: a flat-ish sand/grass plateau in
## the middle that slopes down to beaches and dips below the water line at the
## edges, so the surrounding water plane laps the shore.
##
## The visual mesh regenerates in-editor (@tool) so props can be placed against it;
## collision is only built at runtime. Tick "Rebuild" in the Inspector to refresh.

@export var rebuild: bool = false:
	set(value):
		rebuild = false
		_generate_mesh()

@export_group("Shape")
@export var world_size: float = 48.0
@export var resolution: int = 64
@export var plateau_radius: float = 13.0
@export var shore_radius: float = 21.0
@export var bump_height: float = 0.35
@export var seabed_depth: float = 3.0
@export var noise_seed: int = 1
@export var noise_frequency: float = 0.06

@export_group("Colors")
@export var grass_color: Color = Color(0.45, 0.68, 0.38)
@export var sand_color: Color = Color(0.85, 0.79, 0.56)
@export var seabed_color: Color = Color(0.52, 0.58, 0.5)

func _ready() -> void:
	_generate_mesh()
	if not Engine.is_editor_hint():
		_generate_collision()

func _generate_mesh() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = noise_frequency

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := world_size / float(resolution)
	var half := world_size * 0.5
	for iz in range(resolution + 1):
		for ix in range(resolution + 1):
			var px := ix * step - half
			var pz := iz * step - half
			var h := _height(px, pz, noise)
			st.set_color(_color_for(h, px, pz))
			st.set_uv(Vector2(float(ix) / resolution, float(iz) / resolution))
			st.add_vertex(Vector3(px, h, pz))

	var row := resolution + 1
	for iz in range(resolution):
		for ix in range(resolution):
			var i := iz * row + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + row)
			st.add_index(i + 1)
			st.add_index(i + row + 1)
			st.add_index(i + row)

	st.generate_normals()
	mesh = st.commit()

	if material_override == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		material_override = mat

func _height(x: float, z: float, noise: FastNoiseLite) -> float:
	var r := sqrt(x * x + z * z)
	# 1 inside the plateau, easing to 0 at the shore and beyond.
	var t_land := 1.0 - smoothstep(plateau_radius, shore_radius, r)
	# plateau near 0, dropping to -seabed_depth past the shore, plus gentle bumps.
	var base := lerpf(-seabed_depth, 0.0, t_land)
	var bump := noise.get_noise_2d(x, z) * bump_height * t_land
	return base + bump

func _color_for(h: float, x: float, z: float) -> Color:
	if h < -0.1:
		return seabed_color
	var r := sqrt(x * x + z * z)
	var t_land := 1.0 - smoothstep(plateau_radius, shore_radius, r)
	var grass_amount := smoothstep(0.5, 0.85, t_land)
	return sand_color.lerp(grass_color, grass_amount)

func _generate_collision() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	create_trimesh_collision()
