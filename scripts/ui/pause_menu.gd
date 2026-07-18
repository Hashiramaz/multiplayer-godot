extends CanvasLayer
## In-match pause overlay. Lives inside the Arena and runs with process_mode ALWAYS
## so it keeps receiving input while the rest of the tree is frozen by
## get_tree().paused. Toggle: Start (gamepad) / Esc (keyboard).

@onready var panel: Control = $Panel
@onready var resume_button: Button = $Panel/VBox/Resume

## Tracked ourselves instead of reading get_tree().paused, because online we do NOT
## freeze the tree (that would stall the shared world + netcode) -- see _pause().
var _paused: bool = false

func _ready() -> void:
	panel.visible = false
	resume_button.pressed.connect(_resume)
	($Panel/VBox/Lobby as Button).pressed.connect(_go_lobby)
	($Panel/VBox/Menu as Button).pressed.connect(_go_menu)

func _input(event: InputEvent) -> void:
	# Once the match is over (result screen up), the pause menu goes silent.
	if GameManager.state == GameManager.State.RESULT:
		return
	if _is_toggle(event):
		get_viewport().set_input_as_handled()
		if _paused:
			_resume()
		else:
			_pause()
		return
	# While paused, bridge the gamepad's A to activate the focused button
	# (the default ui_accept isn't firing on the pad here).
	if _paused and event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_A:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			get_viewport().set_input_as_handled()
			(focused as BaseButton).pressed.emit()

func _is_toggle(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		return true
	return false

func _pause() -> void:
	_paused = true
	# Online: freezing the tree would stop the shared world for everyone (the host is
	# authoritative) AND stall the Steam poll -- so pause is a LOCAL menu that only
	# stops our own penguin. Offline (couch): freeze the whole tree as before.
	if NetworkManager.is_online:
		_set_local_player_paused(true)
	else:
		get_tree().paused = true
	GameManager.set_state(GameManager.State.PAUSED)
	panel.visible = true
	resume_button.grab_focus()

func _resume() -> void:
	_paused = false
	if NetworkManager.is_online:
		_set_local_player_paused(false)
	else:
		get_tree().paused = false
	GameManager.set_state(GameManager.State.PLAYING)
	panel.visible = false

## Stops (or resumes) just the penguin we control, by disabling its processing.
func _set_local_player_paused(paused: bool) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var node := p as Node
		if node.is_multiplayer_authority():
			node.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT

func _go_lobby() -> void:
	_leave()
	GameManager.go_to_lobby()

func _go_menu() -> void:
	_leave()
	GameManager.go_to_main_menu()

## Tear down before leaving: unfreeze (offline) or disconnect (online).
func _leave() -> void:
	_paused = false
	if NetworkManager.is_online:
		NetworkManager.leave()
	else:
		get_tree().paused = false
