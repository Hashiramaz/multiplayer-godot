extends Node3D
## Single shared camera, Overcooked-style: one camera frames ALL players.
## It follows the centroid of everything in the "players" group and pulls back
## as they spread out, so no one leaves the screen. High-angle perspective view.

@export var camera_path: NodePath
## Direction the camera sits from the group's center (normalized internally).
## +Y is height, +Z pulls it "toward the viewer" -> high, slightly-behind angle.
@export var view_offset: Vector3 = Vector3(0.0, 1.35, 1.0)
@export var base_distance: float = 12.0
@export var spread_factor: float = 1.15
@export var min_distance: float = 11.0
@export var max_distance: float = 28.0
@export var follow_speed: float = 6.0
@export var look_height: float = 0.6

@onready var camera: Camera3D = get_node(camera_path)

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var center := Vector3.ZERO
	for p in players:
		center += (p as Node3D).global_position
	center /= players.size()

	var spread := 0.0
	for p in players:
		spread = maxf(spread, (p as Node3D).global_position.distance_to(center))

	var distance := clampf(base_distance + spread * spread_factor, min_distance, max_distance)
	var desired := center + view_offset.normalized() * distance

	var weight := clampf(follow_speed * delta, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(desired, weight)
	camera.look_at(center + Vector3.UP * look_height, Vector3.UP)
