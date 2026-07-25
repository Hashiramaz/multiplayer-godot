extends CanvasLayer
## On-screen controls for DEVICE_TOUCH: a floating virtual joystick (left half of the
## screen) for movement and a big button (right half) for interact. Reads raw
## InputEventScreenTouch/Drag directly (not the mouse-emulated versions Controls use
## for menu buttons elsewhere) so it doesn't fight with normal UI input, and so both
## can be held at once -- real multitouch, not a single emulated mouse pointer.

const JOYSTICK_RADIUS: float = 80.0

@onready var joystick_base: Control = $Joystick/Base
@onready var joystick_knob: Control = $Joystick/Base/Knob
@onready var button: Control = $Button

var _joystick_touch_index: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _button_touch_index: int = -1

func _ready() -> void:
	layer = 50 # above MatchUI's HUD
	joystick_base.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if event.position.x < get_viewport().get_visible_rect().size.x * 0.5:
			if _joystick_touch_index == -1:
				_joystick_touch_index = event.index
				_joystick_origin = event.position
				joystick_base.visible = true
				joystick_base.position = _joystick_origin - joystick_base.size * 0.5
				joystick_knob.position = joystick_base.size * 0.5 - joystick_knob.size * 0.5
		else:
			if _button_touch_index == -1:
				_button_touch_index = event.index
				TouchInput.interact_down = true
	else:
		if event.index == _joystick_touch_index:
			_joystick_touch_index = -1
			joystick_base.visible = false
			TouchInput.move = Vector2.ZERO
		elif event.index == _button_touch_index:
			_button_touch_index = -1
			TouchInput.interact_down = false

func _on_drag(event: InputEventScreenDrag) -> void:
	if event.index != _joystick_touch_index:
		return
	var offset := event.position - _joystick_origin
	var clamped := offset.limit_length(JOYSTICK_RADIUS)
	joystick_knob.position = joystick_base.size * 0.5 + clamped - joystick_knob.size * 0.5
	TouchInput.move = clamped / JOYSTICK_RADIUS
