class_name PlayerInput
extends RefCounted
## Reads input for a SINGLE player, isolated to one device. This abstraction is
## the core of local couch co-op: Godot's global Input mixes every controller
## together, so each player instead owns one of these bound to a device id.
##
##   device >= 0            -> that specific gamepad
##   device == -1 (KEYBOARD)-> keyboard (WASD / arrows)
##   device == -2 (DEBUG_ANY)-> keyboard + all gamepads at once. Prototyping-only
##                              convenience so we can test movement solo before
##                              the real join screen exists (Phase 3).

const DEVICE_KEYBOARD: int = -1
const DEVICE_DEBUG_ANY: int = -2
const DEADZONE: float = 0.2

var device: int = DEVICE_DEBUG_ANY

func _init(p_device: int = DEVICE_DEBUG_ANY) -> void:
	device = p_device

## Movement intent. x = right, y = "down" on screen (up is negative), so both
## keyboard and stick agree: pushing up yields y = -1.
func get_move() -> Vector2:
	var v := Vector2.ZERO
	match device:
		DEVICE_DEBUG_ANY:
			v = _keyboard_vector() + _all_pads_vector()
		DEVICE_KEYBOARD:
			v = _keyboard_vector()
		_:
			v = _pad_vector(device)
	if v.length() > 1.0:
		v = v.normalized()
	return v

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
	return v

func _pad_vector(dev: int) -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	)
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v

func _all_pads_vector() -> Vector2:
	var v := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		v += _pad_vector(dev)
	return v
