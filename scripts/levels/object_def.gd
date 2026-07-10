@tool
class_name ObjectDef
extends Resource
## Catalog entry describing one kind of placeable object (see level_catalog.gd).
## Adding a new scenery/gameplay element to the editor is: make its scene, then
## register one ObjectDef. `editable_props` is the schema the editor's inspector
## reads to expose per-instance overrides (written into PlacedObject.props).

@export var id: String = ""
@export var display_name: String = ""
@export_enum("gameplay", "scenery") var category: String = "gameplay"
@export var scene: PackedScene

## Each entry: { "name": String, "type": "float"|"int"|"bool", "default": Variant }.
@export var editable_props: Array[Dictionary] = []
