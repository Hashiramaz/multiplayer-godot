@tool
class_name LevelManifest
extends Resource
## Curates which levels ship in the build and in what ORDER. Authored in the dev-only
## "Fases na Build" screen, saved to res://levels/manifest.tres and committed so the
## build reads it. Paths are res:// level paths; "" means the built-in default island.

const PATH: String = "res://levels/manifest.tres"

## All known level paths in display/build order ("" = the built-in default island).
@export var order: PackedStringArray = PackedStringArray()
## Paths excluded from the build (still listed in the editor so they can be re-enabled).
@export var disabled: PackedStringArray = PackedStringArray()

static func load_or_create() -> LevelManifest:
	if ResourceLoader.exists(PATH):
		var res := load(PATH)
		if res is LevelManifest:
			return res as LevelManifest
	return LevelManifest.new()

func is_enabled(path: String) -> bool:
	return not disabled.has(path)

## Writes the manifest back to disk (dev-only -- res:// is read-only in a build).
func save() -> Error:
	if not DirAccess.dir_exists_absolute("res://levels"):
		DirAccess.make_dir_recursive_absolute("res://levels")
	return ResourceSaver.save(self, PATH)
