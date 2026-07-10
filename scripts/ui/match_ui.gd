extends CanvasLayer
## Runs the match: a countdown "threat clock" (the island closing in). Win when the
## boat is completed in time; lose when the clock hits zero. Shows the HUD timer and
## the end-of-match result screen.
##
## PAUSABLE process mode on purpose: the pause menu (get_tree().paused) freezes the
## clock too. The end-of-match freeze instead just disables the players, so the
## result screen's own buttons keep working without touching get_tree().paused.

@export var match_duration: float = 90.0
@export var low_time_warning: float = 15.0

var _time_left: float = 0.0
var _over: bool = false

@onready var timer_label: Label = $HUD/TimerLabel
@onready var result_panel: Control = $Result
@onready var result_title: Label = $Result/VBox/Title
@onready var replay_button: Button = $Result/VBox/Replay

func _ready() -> void:
	_time_left = match_duration
	result_panel.visible = false
	_update_timer_label()

	var boat := get_tree().get_first_node_in_group("station")
	if boat != null and boat.has_signal("completed"):
		boat.completed.connect(_on_boat_completed)
	else:
		push_warning("MatchUI: no station with a 'completed' signal found.")

	replay_button.pressed.connect(_on_replay)
	($Result/VBox/Menu as Button).pressed.connect(_on_menu)

func _process(delta: float) -> void:
	if _over:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_update_timer_label()
	if _time_left <= 0.0:
		_end(false)

func _on_boat_completed() -> void:
	if not _over:
		_end(true)

func _end(won: bool) -> void:
	_over = true
	GameManager.set_state(GameManager.State.RESULT)
	for player in get_tree().get_nodes_in_group("players"):
		(player as Node).process_mode = Node.PROCESS_MODE_DISABLED
	result_title.text = "Vocês escaparam da ilha!" if won else "O tempo acabou... a ilha venceu."
	result_panel.visible = true
	replay_button.grab_focus()

func _update_timer_label() -> void:
	var total := int(ceil(_time_left))
	@warning_ignore("integer_division")
	timer_label.text = "Tempo  %02d:%02d" % [total / 60, total % 60]
	if _time_left <= low_time_warning:
		timer_label.modulate = Color(1.0, 0.4, 0.35)
	else:
		timer_label.modulate = Color(1.0, 1.0, 1.0)

## Bridge the gamepad's A to the focused result button (default ui_accept isn't
## firing on the pad here), only while the result screen is up.
func _input(event: InputEvent) -> void:
	if not result_panel.visible:
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			get_viewport().set_input_as_handled()
			(focused as BaseButton).pressed.emit()

func _on_replay() -> void:
	GameManager.go_to_lobby()

func _on_menu() -> void:
	GameManager.go_to_main_menu()
