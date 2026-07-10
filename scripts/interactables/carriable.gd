extends Area3D
## A carriable resource. Players pick it up into their hold point and hand it to a
## station. It's an Area3D so players detect it by proximity; while held it stops
## being detectable so it isn't picked up again mid-carry.
##
## `kind` drives the resource chain: a "log" is only accepted by the sawmill, which
## outputs a "plank", which is the only thing the boat accepts.

@export var kind: String = "log"

func _ready() -> void:
	add_to_group("carriable")

func get_kind() -> String:
	return kind

func set_held(held: bool) -> void:
	monitoring = not held
	monitorable = not held
