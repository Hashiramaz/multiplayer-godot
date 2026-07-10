extends Area3D
## A carriable resource (e.g. a log). Players pick it up into their hold point and
## deliver it to a station. It's an Area3D so players can detect it by proximity;
## while held it stops being detectable so it isn't picked up again mid-carry.

func _ready() -> void:
	add_to_group("carriable")

func set_held(held: bool) -> void:
	monitoring = not held
	monitorable = not held
