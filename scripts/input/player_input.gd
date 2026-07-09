class_name PlayerInput
extends RefCounted
## Reads input for a SINGLE player, isolated to one device -- the core of local
## couch co-op, since Godot's global Input mixes every controller together.
##
##   device >= 0             -> that specific gamepad
##   device == -1 (KEYBOARD) -> keyboard (WASD / arrows)
##   device == -99 (NONE)    -> reads nothing (stationary / not-yet-assigned)
##
## A future online layer would feed remote input through this same seam.

const DEVICE_KEYBOARD: int = -1
const DEVICE_NONE: int = -99
const DEADZONE: float = 0.2

var device: int = DEVICE_NONE

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
		_:
			return _pad_vector(device)

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
