extends CharacterBody3D
## Local player. Camera-relative movement (pushing "up" always goes into the
## screen, no matter the world orientation) and the visual mesh turns to face
## the move direction. Input comes from a PlayerInput bound to one device.

@export var speed: float = 6.0
@export var acceleration: float = 40.0
@export var turn_speed: float = 12.0

const GRAVITY: float = 20.0

var device: int = PlayerInput.DEVICE_NONE
var _input: PlayerInput

@onready var pivot: Node3D = $Pivot

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

## Turns 2D input into a world-space direction relative to the active camera.
func _world_direction(move: Vector2) -> Vector3:
	if move == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(move.x, 0.0, move.y)
	var b := cam.global_transform.basis
	# Camera's back-vector flattened to the ground plane. Pushing up (move.y=-1)
	# sends the player along -back, i.e. away from the camera / into the screen.
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
	# The pivot's -Z (where the "nose" mesh sits) should point along movement.
	var target := pivot.global_transform.looking_at(pivot.global_position + flat, Vector3.UP)
	var gt := pivot.global_transform
	gt.basis = gt.basis.slerp(target.basis, clampf(turn_speed * delta, 0.0, 1.0))
	pivot.global_transform = gt
