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

## Clipes de animação embutidos no FBX do pinguim (nomes vindos dos "takes" do FBX).
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_EAT := &"eat"
## Velocidade planar (m/s) a partir da qual o pinguim troca idle -> walk.
const WALK_ANIM_SPEED: float = 0.5
## Crossfade entre clipes, em segundos.
const ANIM_BLEND: float = 0.15

var device: int = PlayerInput.DEVICE_NONE
var player_color: Color = Color.WHITE
var _input: PlayerInput
var _carried: Node3D = null
var _anim: AnimationPlayer = null
var _playing_action: bool = false ## True enquanto uma ação one-shot (ex.: eat) toca.

@onready var pivot: Node3D = $Pivot
@onready var hold_point: Node3D = $Pivot/HoldPoint
@onready var interaction_area: Area3D = $InteractionArea

func _ready() -> void:
	add_to_group("players")
	_input = PlayerInput.new(device)
	_setup_animations()

func set_device(new_device: int) -> void:
	device = new_device
	if _input:
		_input.device = new_device

func set_color(color: Color) -> void:
	# Color choice for the penguin is deferred; just remember the slot color for
	# now so a later pass (tint / team indicator / palette swap) can apply it.
	player_color = color

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
	_update_locomotion_anim()

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
	_play_action(ANIM_EAT)

func _deliver_or_drop() -> void:
	var kind := ""
	if _carried.has_method("get_kind"):
		kind = str(_carried.get_kind())
	var station := _nearest_station_for(kind)
	# The station consumes the carried item itself; we just let go of it.
	if station != null and station.submit(_carried):
		_carried = null
		return
	_drop()

## Nearest station in range that actually accepts what we're carrying.
func _nearest_station_for(kind: String) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for area in interaction_area.get_overlapping_areas():
		if not area.is_in_group("station"):
			continue
		if not (area.has_method("accepts") and area.accepts(kind)):
			continue
		var d := global_position.distance_to((area as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = area
	return best

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

# --- Animation ------------------------------------------------------------
# O FBX do pinguim traz um AnimationPlayer com os clipes (idle/walk/eat/...).
# Em vez de fixar o caminho do nó, procuramos por ele: assim nada quebra se a
# hierarquia do modelo importado mudar num reimport.

func _setup_animations() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("Player: AnimationPlayer não encontrado dentro do modelo do pinguim.")
		return
	# FBX não traz info de loop; definimos aqui. eat é one-shot (sem loop) para
	# que 'animation_finished' dispare e a locomoção retome.
	_set_loop(ANIM_IDLE, true)
	_set_loop(ANIM_WALK, true)
	_set_loop(ANIM_EAT, false)

	var missing: Array = []
	for a in [ANIM_IDLE, ANIM_WALK, ANIM_EAT]:
		if not _anim.has_animation(a):
			missing.append(a)
	if not missing.is_empty():
		push_warning("Player: clipes ausentes %s. Disponíveis: %s" % [missing, _anim.get_animation_list()])

	_anim.animation_finished.connect(_on_animation_finished)
	if _anim.has_animation(ANIM_IDLE):
		_anim.play(ANIM_IDLE)

func _set_loop(anim_name: StringName, looped: bool) -> void:
	if not _anim.has_animation(anim_name):
		return
	_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE

## Escolhe idle vs walk pela velocidade no plano; não mexe enquanto uma ação toca.
func _update_locomotion_anim() -> void:
	if _anim == null or _playing_action:
		return
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var want := ANIM_WALK if planar_speed > WALK_ANIM_SPEED else ANIM_IDLE
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want, ANIM_BLEND)

## Toca um clipe one-shot (ex.: eat) por cima da locomoção.
func _play_action(anim_name: StringName) -> void:
	if _anim == null or not _anim.has_animation(anim_name):
		return
	_playing_action = true
	_anim.play(anim_name, ANIM_BLEND)

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == ANIM_EAT:
		# Locomoção volta a decidir idle/walk no próximo _physics_process.
		_playing_action = false

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
