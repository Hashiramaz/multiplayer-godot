extends Node
## Global game state + high-level scene flow (autoload / singleton, like a Unity
## manager). Flow: MainMenu -> Lobby -> Arena, with in-match pause.

enum State { BOOT, MENU, LOBBY, PLAYING, PAUSED, RESULT }

const MAIN_MENU_SCENE: String = "res://scenes/menu/MainMenu.tscn"
const LOBBY_SCENE: String = "res://scenes/lobby/Lobby.tscn"
const ARENA_SCENE: String = "res://scenes/arena/Arena.tscn"

var state: State = State.BOOT

func set_state(new_state: State) -> void:
	state = new_state

func go_to_main_menu() -> void:
	set_state(State.MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func go_to_lobby() -> void:
	# Fresh lobby each time: clear who joined last session.
	PlayerManager.clear()
	set_state(State.LOBBY)
	get_tree().change_scene_to_file(LOBBY_SCENE)

func start_match() -> void:
	set_state(State.PLAYING)
	get_tree().change_scene_to_file(ARENA_SCENE)
