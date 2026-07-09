extends Node3D
## Phase 1 test arena. Spawns one debug-controlled player (keyboard + any pad)
## so movement, collision and the shared camera can be validated solo.
## Real device-based join/spawn arrives in Phase 3 and moves into PlayerManager.

@export var player_scene: PackedScene

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

func _ready() -> void:
	_spawn_debug_player()

func _spawn_debug_player() -> void:
	if player_scene == null:
		push_warning("Arena: player_scene is not assigned.")
		return
	var player := player_scene.instantiate()
	players.add_child(player)
	var spawn := spawn_points.get_child(0) as Node3D
	player.global_transform = spawn.global_transform
	player.set_device(PlayerInput.DEVICE_DEBUG_ANY)
	player.set_color(PlayerManager.color_for_slot(0))
