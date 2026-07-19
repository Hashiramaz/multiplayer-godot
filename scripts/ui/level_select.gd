extends Control
## Level picker, shown between the Lobby and the Arena. Lists the levels found on
## disk (res://levels and user://levels) plus a built-in default island, so there's
## always something to play even before any level is authored in the editor.
## Picking one stores it in GameManager and starts the match.
##
## Navigable by keyboard and controller, same bridge pattern as the other menus.

@onready var list: VBoxContainer = $VBox/List
@onready var back_button: Button = $VBox/Back

var _levels: Array[LevelData] = []

func _ready() -> void:
	GameManager.set_state(GameManager.State.LEVEL_SELECT)
	_build_list()
	back_button.pressed.connect(GameManager.go_to_lobby)

func _build_list() -> void:
	_levels = _load_levels()
	for i in _levels.size():
		var level := _levels[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(320, 52)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", 22)
		button.text = "%s        %ds" % [level.level_name, int(level.match_duration)]
		button.pressed.connect(_on_level_chosen.bind(i))
		list.add_child(button)
	if list.get_child_count() > 0:
		(list.get_child(0) as Button).grab_focus()
	else:
		back_button.grab_focus()

## The curated, ordered set of levels for the build (respects the manifest), so the
## couch picker matches what ships. Falls back to the built-in island if empty.
func _load_levels() -> Array[LevelData]:
	var out: Array[LevelData] = []
	for e in LevelData.shared_levels():
		out.append(LevelData.from_path(str(e["path"])))
	if out.is_empty():
		out.append(LevelData.make_default_island())
	return out

func _on_level_chosen(index: int) -> void:
	GameManager.selected_level = _levels[index]
	GameManager.start_match()

## Bridge gamepad A to the focused button, and B/Esc to go back -- read per-event so
## the gamepad works regardless of Godot's default ui_accept mapping here.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				var focused := get_viewport().gui_get_focus_owner()
				if focused is BaseButton:
					get_viewport().set_input_as_handled()
					(focused as BaseButton).pressed.emit()
			JOY_BUTTON_B:
				get_viewport().set_input_as_handled()
				GameManager.go_to_lobby()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			GameManager.go_to_lobby()
