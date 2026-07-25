class_name PlayerInput
extends RefCounted
## Reads input for a SINGLE player, isolated to one device -- the core of local
## couch co-op, since Godot's global Input mixes every controller together.
##
##   device >= 0             -> that specific gamepad
##   device == -1 (KEYBOARD) -> keyboard (WASD / arrows)
##   device == -2 (LOCAL)    -> keyboard + gamepad 0 merged (online: 1 player/machine)
##   device == -3 (TOUCH)    -> on-screen virtual joystick/button (mobile)
##   device == -99 (NONE)    -> reads nothing (stationary / not-yet-assigned)
##
## Online layer: each machine's own player uses DEVICE_LOCAL; remote players are
## driven by synced state, not by reading input here.

const DEVICE_KEYBOARD: int = -1
const DEVICE_LOCAL: int = -2
const DEVICE_TOUCH: int = -3
const DEVICE_NONE: int = -99
const DEADZONE: float = 0.2

var device: int = DEVICE_NONE

var _interact_prev: bool = false

func _init(p_device: int = DEVICE_NONE) -> void:
	device = p_device

## Movement intent. x = right, y = "down" on screen (up is negative), so keyboard
## and stick agree: pushing up yields y = -1.
func get_move() -> Vector2:
	match device:
		DEVICE_NONE:
			return Vector2.ZERO
		DEVICE_KEYBOARD:
			return _keyboard_vector()
		DEVICE_LOCAL:
			return _local_vector()
		DEVICE_TOUCH:
			return TouchInput.move
		_:
			return _pad_vector(device)

## Online single-player-per-machine: keyboard wins if touched, else gamepad 0.
func _local_vector() -> Vector2:
	var k := _keyboard_vector()
	if k != Vector2.ZERO:
		return k
	return _pad_vector(0)

func _keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v.limit_length(1.0)

func _pad_vector(dev: int) -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	)
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v.limit_length(1.0)

## Rising edge of the "interact" button for this device (gamepad A, keyboard E/Space).
## Call once per frame; it tracks its own previous state.
func interact_just_pressed() -> bool:
	var now := _interact_down()
	var just := now and not _interact_prev
	_interact_prev = now
	return just

## Estado bruto do botão de interação (sem edge). Usado por ações de SEGURAR --
## cavar com a pá. Pode ser chamado no mesmo frame que interact_just_pressed().
func interact_down() -> bool:
	return _interact_down()

func _interact_down() -> bool:
	match device:
		DEVICE_NONE:
			return false
		DEVICE_KEYBOARD:
			return Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE)
		DEVICE_LOCAL:
			return Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE) \
				or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
		DEVICE_TOUCH:
			return TouchInput.interact_down
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_A)
