@tool
class_name LevelData
extends Resource
## A whole playable level as data (the Godot analog of a Unity ScriptableObject).
## The Arena builds itself from one of these instead of hard-coding content, so we
## can ship many levels and edit them in the in-game level editor.
##
## Terrain is a paintable heightmap: `heights` holds (resolution+1)^2 samples over a
## `size` x `size` square, row-major (iz outer, ix inner) matching island.gd. New
## levels seed `heights` from make_default_island() so they start as the current
## procedural island and get sculpted from there.

@export var level_name: String = "Nova Fase"
@export var match_duration: float = 90.0

@export_group("Terrain")
@export var terrain_size: float = 48.0
@export var terrain_resolution: int = 64
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var water_level: float = -0.8

@export_group("Terrain Colors")
@export var grass_color: Color = Color(0.45, 0.68, 0.38)
@export var sand_color: Color = Color(0.85, 0.79, 0.56)
@export var seabed_color: Color = Color(0.52, 0.58, 0.5)

@export_group("Content")
@export var objects: Array[PlacedObject] = []
@export var spawn_points: Array[Transform3D] = []

## Number of height samples per row/column (a full grid is this squared).
func height_row() -> int:
	return terrain_resolution + 1

## True when `heights` is missing/stale for the current size/resolution.
func heights_invalid() -> bool:
	var expected := height_row() * height_row()
	return heights.size() != expected

# --- Default level: reproduces today's hard-coded Arena as data -----------------

## Builds the level the game currently ships with: the procedural island baked into
## a heightmap, plus the boat / sawmill / 5 logs / 4 spawns at their Arena.tscn
## transforms. Used as the fallback when no level is selected and as the seed for a
## brand-new level in the editor.
static func make_default_island() -> LevelData:
	var level := LevelData.new()
	level.level_name = "Ilha"
	level.match_duration = 90.0
	level.terrain_size = 48.0
	level.terrain_resolution = 64
	level.water_level = -0.8
	level.heights = bake_island_heights(level.terrain_size, level.terrain_resolution)

	level.objects = [
		_obj("boat", Vector3(0.0, 0.0, 9.0)),
		_obj("sawmill", Vector3(0.0, 0.0, 3.0)),
		_obj("log", Vector3(-6.0, 0.25, -3.0)),
		_obj("log", Vector3(6.0, 0.25, -3.0)),
		_obj("log", Vector3(-6.0, 0.25, 3.0)),
		_obj("log", Vector3(6.0, 0.25, 3.0)),
		_obj("log", Vector3(0.0, 0.25, -6.0)),
	]
	level.spawn_points = [
		Transform3D(Basis.IDENTITY, Vector3(-2.0, 0.3, -2.0)),
		Transform3D(Basis.IDENTITY, Vector3(2.0, 0.3, -2.0)),
		Transform3D(Basis.IDENTITY, Vector3(-2.0, 0.3, 2.0)),
		Transform3D(Basis.IDENTITY, Vector3(2.0, 0.3, 2.0)),
	]
	return level

# --- Shippable levels (pickers + online sync) -----------------------------------

## Levels that ship in the build and can be picked/synced: the built-in default plus
## every .tres under res://levels. Each entry is { "name": String, "path": String },
## where an empty path means the built-in island. (user:// is intentionally excluded
## -- online peers must all resolve the same path, and only res:// ships identically.)
static func shared_levels() -> Array:
	var out: Array = [{ "name": "Ilha (padrão)", "path": "" }]
	var dir := DirAccess.open("res://levels")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".tres"):
				var path := "res://levels".path_join(f)
				var res := load(path)
				if res is LevelData:
					out.append({ "name": (res as LevelData).level_name, "path": path })
			f = dir.get_next()
		dir.list_dir_end()
	return out

## Resolve a shared-level path to data ("" -> the built-in default island).
static func from_path(path: String) -> LevelData:
	if path == "":
		return make_default_island()
	var res := load(path)
	if res is LevelData:
		return res as LevelData
	return make_default_island()

static func _obj(type_id: String, pos: Vector3) -> PlacedObject:
	var o := PlacedObject.new()
	o.type_id = type_id
	o.transform = Transform3D(Basis.IDENTITY, pos)
	return o

## The original procedural island shape, baked into a flat heightmap grid. Mirrors
## island.gd's old radial-falloff + noise so the default level looks unchanged.
static func bake_island_heights(size: float, resolution: int) -> PackedFloat32Array:
	const PLATEAU_RADIUS := 13.0
	const SHORE_RADIUS := 21.0
	const BUMP_HEIGHT := 0.35
	const SEABED_DEPTH := 3.0

	var noise := FastNoiseLite.new()
	noise.seed = 1
	noise.frequency = 0.06

	var row := resolution + 1
	var out := PackedFloat32Array()
	out.resize(row * row)

	var step := size / float(resolution)
	var half := size * 0.5
	for iz in range(row):
		for ix in range(row):
			var px := ix * step - half
			var pz := iz * step - half
			var r := sqrt(px * px + pz * pz)
			var t_land := 1.0 - smoothstep(PLATEAU_RADIUS, SHORE_RADIUS, r)
			var base := lerpf(-SEABED_DEPTH, 0.0, t_land)
			var bump := noise.get_noise_2d(px, pz) * BUMP_HEIGHT * t_land
			out[iz * row + ix] = base + bump
	return out
