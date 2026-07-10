extends Node
## Registry of every placeable object (autoload / singleton). The Arena spawns level
## content through here by `type_id`, and the editor builds its palette from it.
##
## To add a new element to the game: make its scene, then add one _def(...) line
## below. That single seam is what keeps growing the content library cheap.

const _LOG_SCENE := preload("res://scenes/interactables/Carriable.tscn")
const _SAWMILL_SCENE := preload("res://scenes/interactables/Sawmill.tscn")
const _BOAT_SCENE := preload("res://scenes/interactables/BoatStation.tscn")
const _PALM_SCENE := preload("res://scenes/props/Palm.tscn")
const _ROCK_SCENE := preload("res://scenes/props/Rock.tscn")

var _defs: Dictionary = {}
var _order: Array[String] = []

func _ready() -> void:
	_register(_def("log", "Tora", "gameplay", _LOG_SCENE))
	_register(_def("sawmill", "Serraria", "gameplay", _SAWMILL_SCENE, [
		{"name": "process_time", "type": "float", "default": 2.0},
	]))
	_register(_def("boat", "Barco", "gameplay", _BOAT_SCENE, [
		{"name": "required", "type": "int", "default": 4},
	]))
	_register(_def("palm", "Palmeira", "scenery", _PALM_SCENE))
	_register(_def("rock", "Pedra", "scenery", _ROCK_SCENE))

func _def(id: String, display_name: String, category: String, scene: PackedScene,
		editable_props: Array = []) -> ObjectDef:
	var d := ObjectDef.new()
	d.id = id
	d.display_name = display_name
	d.category = category
	d.scene = scene
	var typed: Array[Dictionary] = []
	for p in editable_props:
		typed.append(p)
	d.editable_props = typed
	return d

func _register(d: ObjectDef) -> void:
	_defs[d.id] = d
	_order.append(d.id)

func get_def(id: String) -> ObjectDef:
	return _defs.get(id, null)

func has(id: String) -> bool:
	return _defs.has(id)

## All defs in registration order, optionally filtered by category
## ("gameplay"/"scenery"). Used to build the editor palette.
func defs(category: String = "") -> Array[ObjectDef]:
	var out: Array[ObjectDef] = []
	for id in _order:
		var d: ObjectDef = _defs[id]
		if category == "" or d.category == category:
			out.append(d)
	return out
