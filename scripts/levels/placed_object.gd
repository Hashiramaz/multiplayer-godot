@tool
class_name PlacedObject
extends Resource
## One placed instance inside a level: which catalog type it is, where it sits, and
## per-instance property overrides. The Arena (arena.gd) spawns `type_id` via
## LevelCatalog, applies `transform`, then writes each `props` entry onto the node
## (e.g. {"process_time": 2.0} on a sawmill, {"required": 4} on the boat).
##
## This is the Godot analog of serialized data on a Unity prefab instance.

@export var type_id: String = ""
@export var transform: Transform3D = Transform3D.IDENTITY
@export var props: Dictionary = {}
