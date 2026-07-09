extends Node
## Global game state + high-level scene flow (autoload / singleton, like a Unity
## manager). The state machine expands with the menu flow (Phase 5).

enum State { BOOT, MENU, LOBBY, PLAYING, PAUSED }

const LOBBY_SCENE: String = "res://scenes/lobby/Lobby.tscn"
const ARENA_SCENE: String = "res://scenes/arena/Arena.tscn"

var state: State = State.BOOT

func set_state(new_state: State) -> void:
	state = new_state

func start_match() -> void:
	set_state(State.PLAYING)
	get_tree().change_scene_to_file(ARENA_SCENE)

func return_to_lobby() -> void:
	set_state(State.LOBBY)
	get_tree().change_scene_to_file(LOBBY_SCENE)
