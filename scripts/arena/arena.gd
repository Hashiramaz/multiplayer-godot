extends Node3D
## Spawns the players registered in PlayerManager (one per joined device) at the
## matching spawn point. If opened directly with nobody registered (e.g. running
## Arena.tscn straight from the editor / MCP), falls back to a single keyboard
## player so the scene stays testable in isolation.

@export var player_scene: PackedScene

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

func _ready() -> void:
	_spawn_players()
	_setup_outline()

## Attaches the outline post-process as a CompositorEffect on the camera. Doing it
## after transparents (inside the effect) is what lets the transparent water show.
func _setup_outline() -> void:
	var camera := get_node_or_null("CameraRig/Camera3D") as Camera3D
	if camera == null:
		return
	var compositor := Compositor.new()
	compositor.compositor_effects = [OutlineEffect.new()]
	camera.compositor = compositor

func _spawn_players() -> void:
	if player_scene == null:
		push_warning("Arena: player_scene is not assigned.")
		return
	var devices := PlayerManager.registered_devices
	if devices.is_empty():
		_spawn_player(0, PlayerInput.DEVICE_KEYBOARD)
		return
	for slot in devices.size():
		_spawn_player(slot, devices[slot])

func _spawn_player(slot: int, device: int) -> void:
	var player := player_scene.instantiate()
	players.add_child(player)
	var spawn_index := clampi(slot, 0, spawn_points.get_child_count() - 1)
	var spawn := spawn_points.get_child(spawn_index) as Node3D
	player.global_transform = spawn.global_transform
	player.set_device(device)
	player.set_color(PlayerManager.color_for_slot(slot))
