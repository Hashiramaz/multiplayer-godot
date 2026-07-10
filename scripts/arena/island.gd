@tool
extends MeshInstance3D
## Terrain renderer for a level. The shape comes from a paintable heightmap
## (LevelData.heights) instead of the old procedural formula, so the same node
## serves both the game (built via build_from) and the in-game editor (sculpted via
## sculpt). Colors are derived per-vertex from absolute height relative to the water
## line: below water = seabed, just above = sand, higher = grass.
##
## Still @tool so it previews in the Godot editor; opened standalone it seeds a
## default island heightmap so there's something to look at. Collision is only built
## at runtime.

@export var rebuild: bool = false:
	set(value):
		rebuild = false
		_generate_mesh()

@export_group("Shape")
@export var size: float = 48.0
@export var resolution: int = 64
@export var water_level: float = -0.8

@export_group("Colors")
@export var grass_color: Color = Color(0.45, 0.68, 0.38)
@export var sand_color: Color = Color(0.85, 0.79, 0.56)
@export var seabed_color: Color = Color(0.52, 0.58, 0.5)

var heights: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if _heights_invalid():
		heights = LevelData.bake_island_heights(size, resolution)
	_generate_mesh()
	if not Engine.is_editor_hint():
		_generate_collision()

## Configures the terrain from level data and (re)builds mesh + runtime collision.
func build_from(level: LevelData) -> void:
	size = level.terrain_size
	resolution = level.terrain_resolution
	water_level = level.water_level
	grass_color = level.grass_color
	sand_color = level.sand_color
	seabed_color = level.seabed_color
	heights = level.heights
	if _heights_invalid():
		heights = LevelData.bake_island_heights(size, resolution)
	_generate_mesh()
	_update_water()
	if not Engine.is_editor_hint():
		_generate_collision()

## Updates colors + water line and regenerates the mesh WITHOUT touching heights, so
## the editor's Properties panel can restyle terrain without reverting a sculpt.
func set_appearance(grass: Color, sand: Color, seabed: Color, water: float) -> void:
	grass_color = grass
	sand_color = sand
	seabed_color = seabed
	water_level = water
	_generate_mesh()
	_update_water()

## Moves the sibling water plane (if any) to the water line.
func _update_water() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var water := parent.get_node_or_null("Water")
	if water is Node3D:
		(water as Node3D).position.y = water_level

func _row() -> int:
	return resolution + 1

func _heights_invalid() -> bool:
	return heights.size() != _row() * _row()

func _generate_mesh() -> void:
	if _heights_invalid():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var row := _row()
	var step := size / float(resolution)
	var half := size * 0.5
	for iz in range(row):
		for ix in range(row):
			var px := ix * step - half
			var pz := iz * step - half
			var h := heights[iz * row + ix]
			st.set_color(_color_for_height(h))
			st.set_uv(Vector2(float(ix) / resolution, float(iz) / resolution))
			st.add_vertex(Vector3(px, h, pz))

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

func _color_for_height(h: float) -> Color:
	if h < water_level:
		return seabed_color
	var grass_amount := smoothstep(water_level + 0.2, water_level + 1.0, h)
	return sand_color.lerp(grass_color, grass_amount)

# --- Editing API (used by the level editor) -------------------------------------

## Fractional grid coordinates for a world position (x/z ignored on y). Values run
## 0..resolution; outside the terrain they fall outside that range.
func grid_from_world(world_pos: Vector3) -> Vector2:
	var step := size / float(resolution)
	var half := size * 0.5
	return Vector2((world_pos.x + half) / step, (world_pos.z + half) / step)

## Bilinearly samples terrain height at a world XZ (for snapping props to the
## surface). Returns 0.0 if the heightmap isn't ready.
func height_at(world_pos: Vector3) -> float:
	if _heights_invalid():
		return 0.0
	var g := grid_from_world(world_pos)
	var row := _row()
	var ix := clampi(int(floor(g.x)), 0, resolution - 1)
	var iz := clampi(int(floor(g.y)), 0, resolution - 1)
	var fx := clampf(g.x - ix, 0.0, 1.0)
	var fz := clampf(g.y - iz, 0.0, 1.0)
	var h00 := heights[iz * row + ix]
	var h10 := heights[iz * row + ix + 1]
	var h01 := heights[(iz + 1) * row + ix]
	var h11 := heights[(iz + 1) * row + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

## Ray-marches a ray against the heightmap and returns { hit: bool, position:
## Vector3 }. The editor uses this to find where the mouse points on the terrain --
## no physics, so it always matches the live mesh even mid-sculpt. `dir` must be
## normalized.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 300.0, step: float = 0.25) -> Dictionary:
	if _heights_invalid():
		return {"hit": false, "position": Vector3.ZERO}
	var t := 0.0
	var prev := origin
	var prev_above := prev.y >= height_at(prev)
	while t < max_dist:
		t += step
		var p := origin + dir * t
		var above := p.y >= height_at(p)
		if above != prev_above:
			return {"hit": true, "position": (prev + p) * 0.5}
		prev = p
		prev_above = above
	return {"hit": false, "position": Vector3.ZERO}

## Sculpts the heightmap under a world-space brush and rebuilds the mesh live.
## mode: "raise" | "lower" | "smooth" | "flatten". `delta` is the per-application
## strength (already scaled by the caller for frame time). Returns nothing; call is
## cheap enough to run per mouse-move while dragging.
func sculpt(world_center: Vector3, radius: float, delta: float, mode: String) -> void:
	if _heights_invalid():
		return
	var step := size / float(resolution)
	var half := size * 0.5
	var row := _row()
	var center := grid_from_world(world_center)
	var grid_radius := radius / step
	var target := height_at(world_center) if mode == "flatten" else 0.0

	var min_ix := clampi(int(floor(center.x - grid_radius)), 0, resolution)
	var max_ix := clampi(int(ceil(center.x + grid_radius)), 0, resolution)
	var min_iz := clampi(int(floor(center.y - grid_radius)), 0, resolution)
	var max_iz := clampi(int(ceil(center.y + grid_radius)), 0, resolution)

	for iz in range(min_iz, max_iz + 1):
		for ix in range(min_ix, max_ix + 1):
			var d := Vector2(ix - center.x, iz - center.y).length()
			if d > grid_radius:
				continue
			var falloff := 1.0 - smoothstep(0.0, grid_radius, d)
			var idx := iz * row + ix
			match mode:
				"raise":
					heights[idx] += delta * falloff
				"lower":
					heights[idx] -= delta * falloff
				"flatten":
					heights[idx] = lerpf(heights[idx], target, falloff * delta)
				"smooth":
					heights[idx] = lerpf(heights[idx], _neighbor_avg(ix, iz), falloff * delta)
	_generate_mesh()

func _neighbor_avg(ix: int, iz: int) -> float:
	var row := _row()
	var sum := 0.0
	var count := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := ix + dx
			var nz := iz + dz
			if nx < 0 or nx > resolution or nz < 0 or nz > resolution:
				continue
			sum += heights[nz * row + nx]
			count += 1
	return sum / maxi(count, 1)

func _generate_collision() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	create_trimesh_collision()
