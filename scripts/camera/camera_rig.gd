extends Node3D
## Single shared camera, Overcooked-style: one camera frames ALL players in the
## "players" group. It sits at a fixed high angle (pitch/yaw) and only its
## DISTANCE changes to keep everyone on screen -- pull back as they spread out,
## zoom in as they gather.
##
## Framing is derived from the camera FOV rather than an arbitrary factor:
##   distance = (group_radius + padding) / tan(fov/2) * fit_margin
## so everyone stays framed regardless of the chosen FOV.

@export var camera_path: NodePath

@export_group("Angle")
@export_range(20.0, 89.0) var pitch_deg: float = 52.0 ## High angle; 90 = top-down.
@export_range(-180.0, 180.0) var yaw_deg: float = 0.0

@export_group("Framing")
@export var fit_margin: float = 1.4 ## Extra breathing room around the players.
@export var player_extent: float = 1.2 ## Half-size padding so bodies aren't clipped.
@export var min_distance: float = 13.0 ## Closest zoom (solo / gathered).
@export var max_distance: float = 34.0 ## Farthest zoom (fully spread out).
@export var look_height: float = 0.8 ## Aim slightly above the ground plane.

@export_group("Smoothing")
@export var follow_speed: float = 7.0 ## How fast the camera position tracks.
@export var zoom_speed: float = 4.0 ## How fast the distance (zoom) adapts.

@onready var camera: Camera3D = get_node(camera_path)

var _distance: float = 0.0
var _initialized: bool = false

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var centroid := _centroid(players)
	var radius := _spread_radius(players, centroid)

	var target_distance := _distance_for_radius(radius)
	if _initialized:
		_distance = lerpf(_distance, target_distance, clampf(zoom_speed * delta, 0.0, 1.0))
	else:
		_distance = target_distance

	var desired_pos := centroid + _offset_dir() * _distance
	if _initialized:
		camera.global_position = camera.global_position.lerp(desired_pos, clampf(follow_speed * delta, 0.0, 1.0))
	else:
		camera.global_position = desired_pos
		_initialized = true

	camera.look_at(centroid + Vector3.UP * look_height, Vector3.UP)

func _centroid(players: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in players:
		c += (p as Node3D).global_position
	return c / players.size()

## Largest horizontal (XZ) distance from the centroid to any player.
func _spread_radius(players: Array, centroid: Vector3) -> float:
	var r := 0.0
	for p in players:
		var gp := (p as Node3D).global_position
		r = maxf(r, Vector2(gp.x - centroid.x, gp.z - centroid.z).length())
	return r

func _distance_for_radius(radius: float) -> float:
	var half_fov := deg_to_rad(camera.fov) * 0.5
	var needed := (radius + player_extent) / maxf(tan(half_fov), 0.01)
	return clampf(needed * fit_margin, min_distance, max_distance)

## Unit vector from the group's center to the camera, from pitch/yaw.
func _offset_dir() -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	var horizontal := Vector3(sin(yaw), 0.0, cos(yaw)) * cos(pitch)
	return (horizontal + Vector3(0.0, sin(pitch), 0.0)).normalized()
