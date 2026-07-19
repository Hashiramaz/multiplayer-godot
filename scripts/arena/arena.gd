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

## Online spawn handshake state (server-side): who has loaded the Arena scene.
var _net_ready_peers: Dictionary = {}
var _net_expected: int = 0
var _net_spawned: bool = false

## Networked world objects by name. A registry (not get_node) because a carried log
## LEAVES $Interactables for a player's HoldPoint -- a path lookup couldn't follow it.
var _net_items: Dictionary = {}
## Counter for runtime-spawned items, so their names are identical on every peer.
var _net_item_count: int = 0

func _ready() -> void:
	var level := GameManager.selected_level
	# Online uses the default island on every peer so the terrain matches without
	# syncing LevelData yet (that comes later). Offline keeps the selected level.
	if NetworkManager.is_online or level == null:
		level = LevelData.make_default_island()
	_build_level(level)
	_setup_outline()
	if NetworkManager.is_online:
		_start_net_match()
	else:
		_spawn_players()

## Instantiates everything the level describes: terrain shape, gameplay/scenery
## objects (via LevelCatalog), spawn markers, and the match configuration.
func _build_level(level: LevelData) -> void:
	terrain.build_from(level)

	for i in level.objects.size():
		_place_object(level.objects[i], i)

	for i in level.spawn_points.size():
		var marker := Marker3D.new()
		marker.transform = level.spawn_points[i]
		spawn_points.add_child(marker)

	# The clock is host-authoritative online (see match_ui.gd): the host runs the
	# countdown and broadcasts it; clients just display. Wins/losses fan out from the host.
	if match_ui.has_method("configure"):
		match_ui.configure(level)

func _place_object(o: PlacedObject, index: int) -> void:
	var def := LevelCatalog.get_def(o.type_id)
	if def == null or def.scene == null:
		push_warning("Arena: unknown object type_id '%s'" % o.type_id)
		return
	var node := def.scene.instantiate()
	# Deterministic name: every peer builds the same level in the same order, so
	# "obj_3" is the same log everywhere -- that's what makes RPCs addressable.
	node.name = "obj_%d" % index
	# Set transform + prop overrides BEFORE add_child so the node's _ready sees them.
	(node as Node3D).transform = o.transform
	for key in o.props:
		node.set(key, o.props[key])
	interactables.add_child(node)
	_net_items[node.name] = node

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

# --- Networked match (O2: replicated players) -----------------------------
# Every peer builds the same island, then reports "ready" to the host once its
# Arena scene is up. The host waits for everyone, then spawns one penguin per peer
# via an RPC so all machines create the exact same node (named after the peer id,
# which drives authority in player.gd). Movement itself is client-authoritative.

func _start_net_match() -> void:
	if multiplayer.is_server():
		_net_expected = multiplayer.get_peers().size() + 1
		_net_ready_peers.clear()
		_net_mark_ready(1) # count ourselves (the host is peer 1)
	else:
		_net_client_ready.rpc_id(1)

## Client -> host: "my Arena scene finished loading."
@rpc("any_peer", "reliable")
func _net_client_ready() -> void:
	_net_mark_ready(multiplayer.get_remote_sender_id())

func _net_mark_ready(peer_id: int) -> void:
	if not multiplayer.is_server() or _net_spawned:
		return
	_net_ready_peers[peer_id] = true
	if _net_ready_peers.size() >= _net_expected:
		_net_spawn_all()

func _net_spawn_all() -> void:
	_net_spawned = true
	var ids: Array = [1]
	ids.append_array(multiplayer.get_peers())
	for i in ids.size():
		var pid: int = ids[i]
		_net_spawn_player.rpc(pid, NetworkManager.color_for_peer(pid), _net_spawn_transform(i))

## Host -> everyone (call_local): create this peer's penguin identically on all
## machines. The color index (chosen in the lobby) is passed so every peer paints
## each penguin the same without syncing the color itself.
@rpc("authority", "call_local", "reliable")
func _net_spawn_player(peer_id: int, color_index: int, xform: Transform3D) -> void:
	var player := player_scene.instantiate()
	player.name = str(peer_id) # must be set BEFORE _ready so authority is right
	players.add_child(player)
	player.transform = xform
	player.set_color(PlayerManager.color_for_slot(color_index))

func _net_spawn_transform(index: int) -> Transform3D:
	var n := spawn_points.get_child_count()
	if n > 0:
		return (spawn_points.get_child(clampi(index, 0, n - 1)) as Node3D).transform
	return Transform3D(Basis.IDENTITY, Vector3(index * 2.0, 1.0, 0.0))

# --- Networked interactions (O3a: host arbitrates the world) ---------------
# Movement is client-authoritative, but the WORLD is not: two players can reach for
# the same log at once. So clients only send intent (player.gd::_req_interact); the
# host decides on its own copy (positions are synced, so it sees the same items in
# range) and calls the host_* helpers below, which broadcast the result to everyone.
#
# The race resolves itself: once the host applies a pickup, the log's monitorable
# goes false on the host, so a second request simply finds nothing in range.

## Host -> everyone: player picked up item.
func host_pickup(player_name: String, item_name: String) -> void:
	_net_pickup.rpc(player_name, item_name)

## Host -> everyone: player dropped item at xform.
func host_drop(player_name: String, item_name: String, xform: Transform3D) -> void:
	_net_drop.rpc(player_name, item_name, xform)

## Host -> everyone: player handed item to station (station consumes it).
func host_deliver(player_name: String, item_name: String, station_name: String) -> void:
	_net_deliver.rpc(player_name, item_name, station_name)

## Host -> everyone: spawn a runtime item (e.g. the sawmill's plank). The host picks
## the name AND the position so the random jitter doesn't diverge per machine.
func host_spawn_item(scene_path: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_net_item_count += 1
	_net_spawn_item.rpc("item_%d" % _net_item_count, scene_path, pos)

@rpc("authority", "call_local", "reliable")
func _net_pickup(player_name: String, item_name: String) -> void:
	var p := players.get_node_or_null(player_name)
	var item: Node3D = _net_items.get(item_name)
	if p == null or item == null:
		return
	p.net_attach(item)

@rpc("authority", "call_local", "reliable")
func _net_drop(player_name: String, item_name: String, xform: Transform3D) -> void:
	var p := players.get_node_or_null(player_name)
	var item: Node3D = _net_items.get(item_name)
	if p == null or item == null:
		return
	p.net_release()
	item.reparent(interactables)
	item.global_transform = xform
	if item.has_method("set_held"):
		item.set_held(false)

@rpc("authority", "call_local", "reliable")
func _net_deliver(player_name: String, item_name: String, station_name: String) -> void:
	var p := players.get_node_or_null(player_name)
	var item: Node3D = _net_items.get(item_name)
	var station: Node = _net_items.get(station_name)
	if p == null or item == null or station == null:
		return
	p.net_release()
	_net_items.erase(item_name)
	# submit() is deterministic (boat: reveal plank + count; sawmill: queue++), so
	# running it on every peer keeps the station state in sync for free. It also
	# frees the item, which detaches it from the hold point.
	station.submit(item)

@rpc("authority", "call_local", "reliable")
func _net_spawn_item(item_name: String, scene_path: String, pos: Vector3) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_warning("Arena: could not load spawn scene '%s'" % scene_path)
		return
	var item: Node3D = packed.instantiate()
	item.name = item_name
	interactables.add_child(item)
	item.global_transform = Transform3D(Basis.IDENTITY, pos)
	_net_items[item_name] = item
