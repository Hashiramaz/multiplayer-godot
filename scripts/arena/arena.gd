extends Node3D
## Phase 2 test arena. Spawns several players so the shared camera framing can be
## tuned: slot 0 is drivable (keyboard + any pad); the rest stand still as spread
## references. Walk the blue one around to feel the camera open up / zoom in.
##
## Real device-based join (each player on its own controller) arrives in Phase 3
## and moves into PlayerManager.

@export var player_scene: PackedScene
@export_range(1, 4) var debug_player_count: int = 3

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

func _ready() -> void:
	_spawn_debug_players()

func _spawn_debug_players() -> void:
	if player_scene == null:
		push_warning("Arena: player_scene is not assigned.")
		return
	var count := clampi(debug_player_count, 1, spawn_points.get_child_count())
	for slot in count:
		# Slot 0 is the one you drive solo; the others are stationary references.
		var device := PlayerInput.DEVICE_DEBUG_ANY if slot == 0 else PlayerInput.DEVICE_NONE
		_spawn_player(slot, device)

func _spawn_player(slot: int, device: int) -> void:
	var player := player_scene.instantiate()
	players.add_child(player)
	var spawn := spawn_points.get_child(slot) as Node3D
	player.global_transform = spawn.global_transform
	player.set_device(device)
	player.set_color(PlayerManager.color_for_slot(slot))
