extends Camera3D
## Free-look camera for the level editor (a desktop tool, mouse-driven -- distinct
## from the game's shared CameraRig). Orbits around a pivot point:
##   Right mouse drag  -> orbit (yaw/pitch)
##   Middle mouse drag -> pan the pivot in the view plane
##   Mouse wheel       -> zoom (distance to pivot)
## Left mouse is left free for the editor's tools (sculpt / place).

@export var pivot: Vector3 = Vector3.ZERO
@export var yaw_deg: float = 0.0
@export var pitch_deg: float = 55.0
@export var distance: float = 34.0

@export var orbit_speed: float = 0.3      ## degrees per pixel
@export var pan_speed: float = 0.0016     ## world units per pixel, scaled by distance
@export var zoom_step: float = 2.5
@export var min_distance: float = 4.0
@export var max_distance: float = 90.0
@export var min_pitch: float = 8.0
@export var max_pitch: float = 89.0

func _ready() -> void:
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = maxf(min_distance, distance - zoom_step)
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = minf(max_distance, distance + zoom_step)
					_apply()
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			yaw_deg -= event.relative.x * orbit_speed
			pitch_deg = clampf(pitch_deg + event.relative.y * orbit_speed, min_pitch, max_pitch)
			_apply()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			pivot += (-right * event.relative.x + up * event.relative.y) * pan_speed * distance
			_apply()

func _apply() -> void:
	var yr := deg_to_rad(yaw_deg)
	var pr := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr))
	global_position = pivot + dir * distance
	look_at(pivot, Vector3.UP)
