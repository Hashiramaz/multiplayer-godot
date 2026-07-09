extends Node
## Global game state (autoload / singleton, similar to a Unity manager).
## Skeleton for now; the state machine expands with the menu/lobby flow (Phase 5).

enum State { BOOT, MENU, LOBBY, PLAYING, PAUSED }

var state: State = State.BOOT

func set_state(new_state: State) -> void:
	state = new_state
