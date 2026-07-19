extends Control
## Title screen. Buttons are navigable by keyboard and controller out of the box
## (Godot's default ui_up/down/accept cover arrows/Enter and D-pad/A).

func _ready() -> void:
	GameManager.set_state(GameManager.State.MENU)
	var play := $VBox/Play as Button
	var online := $VBox/Online as Button
	var editor := $VBox/Editor as Button
	var quit := $VBox/Quit as Button
	play.pressed.connect(GameManager.go_to_lobby)
	online.pressed.connect(GameManager.go_to_online)
	editor.pressed.connect(GameManager.go_to_editor)
	quit.pressed.connect(_on_quit)
	($VersionLabel as Label).text = GameManager.get_version()
	play.grab_focus()

## The default ui_accept isn't firing on the gamepad's A here, so bridge it:
## pressing A activates whatever button currently has focus.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			get_viewport().set_input_as_handled()
			(focused as BaseButton).pressed.emit()

func _on_quit() -> void:
	get_tree().quit()
