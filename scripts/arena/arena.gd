extends Node3D
## Builds a level from data (LevelData) and runs it: terrain, placed objects, spawn
## points, and the match clock all come from GameManager.selected_level. Opened with
## no level selected (e.g. running Arena.tscn straight from the editor / a test),
## it falls back to the default island so the scene stays playable in isolation --
## same spirit as the single keyboard-player fallback below.

@export var player_scene: PackedScene

@onready var terrain: Node = $Island/Terrain
@onready var interactables: Node3D = $Interactables
@onready var spawn_points: Node3D = $SpawnPoints
@onready var players: Node3D = $Players
@onready var match_ui: Node = $MatchUI

func _ready() -> void:
	var level := GameManager.selected_level
	if level == null:
		level = LevelData.make_default_island()
	_build_level(level)
	_spawn_players()
	_setup_outline()

## Instantiates everything the level describes: terrain shape, gameplay/scenery
## objects (via LevelCatalog), spawn markers, and the match configuration.
func _build_level(level: LevelData) -> void:
	terrain.build_from(level)

	for o in level.objects:
		_place_object(o)

	for i in level.spawn_points.size():
		var marker := Marker3D.new()
		marker.transform = level.spawn_points[i]
		spawn_points.add_child(marker)

	if match_ui.has_method("configure"):
		match_ui.configure(level)

func _place_object(o: PlacedObject) -> void:
	var def := LevelCatalog.get_def(o.type_id)
	if def == null or def.scene == null:
		push_warning("Arena: unknown object type_id '%s'" % o.type_id)
		return
	var node := def.scene.instantiate()
	# Set transform + prop overrides BEFORE add_child so the node's _ready sees them.
	(node as Node3D).transform = o.transform
	for key in o.props:
		node.set(key, o.props[key])
	interactables.add_child(node)

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
	if spawn_points.get_child_count() == 0:
		push_warning("Arena: level has no spawn points.")
		return
	var player := player_scene.instantiate()
	players.add_child(player)
	var spawn_index := clampi(slot, 0, spawn_points.get_child_count() - 1)
	var spawn := spawn_points.get_child(spawn_index) as Node3D
	player.global_transform = spawn.global_transform
	player.set_device(device)
	player.set_color(PlayerManager.color_for_slot(slot))
