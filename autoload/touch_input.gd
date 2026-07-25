extends Node
## Global state written by the on-screen touch controls (scripts/ui/touch_controls.gd)
## and read by PlayerInput for DEVICE_TOUCH -- same role the raw Input singleton
## plays for keyboard/gamepad, kept here since touch has no such built-in polling API.

var move: Vector2 = Vector2.ZERO
var interact_down: bool = false
