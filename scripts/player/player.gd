extends CharacterBody3D
## Local player. Camera-relative movement (pushing "up" always goes into the
## screen) and the visual mesh turns to face the move direction. Input comes from
## a PlayerInput bound to one device. Can pick up carriables, deliver them to a
## station, or drop them.

@export var speed: float = 6.0
@export var acceleration: float = 40.0
@export var turn_speed: float = 12.0

const GRAVITY: float = 20.0
const DROP_HEIGHT: float = 0.25 ## Rest height of a dropped item on the floor.

var device: int = PlayerInput.DEVICE_NONE
var _input: PlayerInput
var _carried: Node3D = null

@onready var pivot: Node3D = $Pivot
@onready var hold_point: Node3D = $Pivot/HoldPoint
@onready var interaction_area: Area3D = $InteractionArea

func _ready() -> void:
	add_to_group("players")
	_input = PlayerInput.new(device)

func set_device(new_device: int) -> void:
	device = new_device
	if _input:
		_input.device = new_device

func set_color(color: Color) -> void:
	var body := pivot.get_node("Body") as MeshInstance3D
	var mat := body.get_active_material(0)
	if mat:
		mat = mat.duplicate()
		mat.albedo_color = color
		body.material_override = mat

func _physics_process(delta: float) -> void:
	var move := _input.get_move()
	var dir := _world_direction(move)

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_face_direction(dir, delta)

	if _input.interact_just_pressed():
		_interact()

# --- Movement -------------------------------------------------------------

## Turns 2D input into a world-space direction relative to the active camera.
func _world_direction(move: Vector2) -> Vector3:
	if move == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(move.x, 0.0, move.y)
	var b := cam.global_transform.basis
	# Camera's back-vector flattened to the ground. Pushing up (move.y=-1) sends
	# the player along -back, i.e. away from the camera / into the screen.
	var cam_back := Vector3(b.z.x, 0.0, b.z.z).normalized()
	var cam_right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var dir := cam_right * move.x + cam_back * move.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir

func _face_direction(dir: Vector3, delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.05:
		return
	var target := pivot.global_transform.looking_at(pivot.global_position + flat, Vector3.UP)
	var gt := pivot.global_transform
	gt.basis = gt.basis.slerp(target.basis, clampf(turn_speed * delta, 0.0, 1.0))
	pivot.global_transform = gt

# --- Interaction ----------------------------------------------------------

func _interact() -> void:
	if _carried == null:
		_try_pickup()
	else:
		_deliver_or_drop()

func _try_pickup() -> void:
	var item := _nearest_in_group("carriable")
	if item == null:
		return
	_carried = item
	item.set_held(true)
	item.get_parent().remove_child(item)
	hold_point.add_child(item)
	item.transform = Transform3D.IDENTITY

func _deliver_or_drop() -> void:
	var station := _nearest_in_group("station")
	if station != null and station.has_method("deliver") and station.can_deliver():
		if station.deliver():
			_carried.queue_free()
			_carried = null
			return
	_drop()

func _drop() -> void:
	var item := _carried
	_carried = null
	hold_point.remove_child(item)
	get_tree().current_scene.add_child(item)
	var forward := -pivot.global_transform.basis.z
	var drop_pos := global_position + forward * 0.9
	drop_pos.y = DROP_HEIGHT
	item.global_transform = Transform3D(Basis.IDENTITY, drop_pos)
	if item.has_method("set_held"):
		item.set_held(false)

## Nearest overlapping Area3D that belongs to `group` (carriables/stations are areas).
func _nearest_in_group(group: String) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for area in interaction_area.get_overlapping_areas():
		if not area.is_in_group(group):
			continue
		var d := global_position.distance_to((area as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = area
	return best
