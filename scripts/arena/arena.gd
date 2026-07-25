extends Node3D
## Builds a level from data (LevelData) and runs it: terrain, placed objects, spawn
## points, and the match clock all come from GameManager.selected_level. Opened with
## no level selected (e.g. running Arena.tscn straight from the editor / a test),
## it falls back to the default island so the scene stays playable in isolation --
## same spirit as the single keyboard-player fallback below.

@export var player_scene: PackedScene

## Baú do objetivo secundário: não é colocável no editor (nasce ao cavar o X certo).
const CHEST_SCENE_PATH := "res://scenes/interactables/Chest.tscn"

@onready var terrain: Node = $Island/Terrain
@onready var interactables: Node3D = $Interactables
@onready var spawn_points: Node3D = $SpawnPoints
@onready var players: Node3D = $Players
@onready var match_ui: Node = $MatchUI

## Online spawn (host-side): peer_id -> slot index, for peers that reported ready.
var _net_ready: Dictionary = {}
var _net_slot_counter: int = 0
## Client-side: throttle for re-sending our "ready" ping until we're spawned.
var _net_ready_timer: float = 0.0

## Networked world objects by name. A registry (not get_node) because a carried log
## LEAVES $Interactables for a player's HoldPoint -- a path lookup couldn't follow it.
var _net_items: Dictionary = {}
## Counter for runtime-spawned items, so their names are identical on every peer.
var _net_item_count: int = 0

## Escavações em andamento: player (Node) -> { "spot": Node3D, "t": float }. Só existe
## em quem cronometra (offline esta máquina, online o host).
var _digs: Dictionary = {}

func _ready() -> void:
	var level := GameManager.selected_level
	# Online: everyone builds the level the host picked in the lobby (resolved by its
	# res:// path, which every build shares). Offline keeps the level-select choice.
	if NetworkManager.is_online:
		level = LevelData.from_path(NetworkManager.selected_level_path)
	elif level == null:
		level = LevelData.make_default_island()
	_build_level(level)
	_setup_treasure()
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
	var has_touch_player := false
	if devices.is_empty():
		var device := PlayerInput.DEVICE_TOUCH if _is_touch_platform() else PlayerInput.DEVICE_KEYBOARD
		_spawn_player(0, device)
		has_touch_player = device == PlayerInput.DEVICE_TOUCH
	else:
		for slot in devices.size():
			_spawn_player(slot, devices[slot])
		has_touch_player = PlayerInput.DEVICE_TOUCH in devices
	if has_touch_player:
		add_child(preload("res://scenes/ui/TouchControls.tscn").instantiate())

## True on a device with no physical keyboard/gamepad expected -- Android, or any
## touchscreen (kept generic so a touch-first desktop build would also pick it up).
func _is_touch_platform() -> bool:
	return OS.get_name() == "Android" or DisplayServer.is_touchscreen_available()

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
	player.set_spawn_info(spawn.global_transform, _water_level())

# --- Tesouro: sorteio + escavação ------------------------------------------
# Objetivo secundário. A fase pode ter N marcas de "X"; UMA esconde o baú. Quem
# cronometra a escavação e decide o resultado é offline esta máquina, online o HOST --
# mesma regra da serraria (timer por máquina diverge) e do pickup (o mundo é do host).

## Sorteia o X certo. Só quem resolve precisa saber, então online **apenas o host**
## sorteia: se cada máquina rolasse o dado, cada uma acharia um tesouro diferente --
## e, de quebra, o segredo nunca trafega, então não dá pra "ver" a resposta na rede.
func _setup_treasure() -> void:
	if NetworkManager.is_online and not multiplayer.is_server():
		return
	var spots := get_tree().get_nodes_in_group("dig_spot")
	if spots.is_empty():
		return # fase sem marcas: sem objetivo secundário (fases antigas seguem iguais)
	var chosen := spots[randi() % spots.size()] as Node
	chosen.set("is_treasure", true)

## Chamado pelo dono do pinguim: `spot` = X que ele quer cavar, null = parou/cancelou.
func report_dig(player: Node3D, spot: Node3D) -> void:
	if not NetworkManager.is_online or multiplayer.is_server():
		_apply_dig(player, spot)
	else:
		_req_dig.rpc_id(1, str(player.name), "" if spot == null else str(spot.name))

@rpc("any_peer", "reliable")
func _req_dig(player_name: String, spot_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := players.get_node_or_null(player_name)
	if p == null or p.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return # só o dono daquele pinguim manda nele
	_apply_dig(p, _net_items.get(spot_name))

## Abre ou fecha uma sessão de escavação (host/offline).
func _apply_dig(player: Node3D, spot: Node3D) -> void:
	if player == null:
		return
	var current: Dictionary = _digs.get(player, {})
	var current_spot: Node3D = current.get("spot")
	if spot == null:
		if current_spot == null:
			return
		_digs.erase(player)
		if is_instance_valid(current_spot):
			_dig_progress(str(current_spot.name), 0.0) # cancelou: barra zera
		_dig_state(str(player.name), false)
		return
	if not (spot.has_method("can_dig") and spot.can_dig()):
		return
	if current_spot == spot:
		return # já estava cavando esse mesmo X
	if is_instance_valid(current_spot):
		_dig_progress(str(current_spot.name), 0.0) # trocou de X: a barra do antigo zera
	_digs[player] = { "spot": spot, "t": 0.0 }
	_dig_state(str(player.name), true)

func _tick_digs(delta: float) -> void:
	for player in _digs.keys(): # keys() é uma cópia -- dá pra apagar durante o loop
		var d: Dictionary = _digs[player]
		var spot: Node3D = d["spot"]
		# A sessão morre sozinha se alguém sumiu, afogou ou o X já foi cavado. (Largar
		# a pá ou sair de cima o próprio dono avisa, via report_dig(null).)
		if not is_instance_valid(player) or not is_instance_valid(spot) \
				or not spot.can_dig() or player.is_dead():
			_digs.erase(player)
			continue
		d["t"] += delta
		var duration: float = maxf(spot.dig_duration, 0.01)
		if d["t"] >= duration:
			_digs.erase(player)
			_resolve_dig(player, spot)
		else:
			_dig_progress(str(spot.name), d["t"] / duration)

func _resolve_dig(player: Node3D, spot: Node3D) -> void:
	var found: bool = spot.is_treasure
	_dig_state(str(player.name), false)
	_dig_result(str(spot.name), found)
	if found:
		_spawn_chest(spot.global_position)

## O baú nasce em cima do buraco. Online ele PRECISA vir pelo host_spawn_item: é lá que
## ganha nome determinístico e entra no _net_items, o que faz pegar/entregar em rede
## funcionar de graça.
func _spawn_chest(at: Vector3) -> void:
	var pos := at + Vector3(0.0, 0.35, 0.0)
	if NetworkManager.is_online:
		host_spawn_item(CHEST_SCENE_PATH, pos)
		return
	var packed: PackedScene = load(CHEST_SCENE_PATH)
	if packed == null:
		push_warning("Arena: não consegui carregar o baú (%s)" % CHEST_SCENE_PATH)
		return
	var chest: Node3D = packed.instantiate()
	interactables.add_child(chest)
	chest.global_transform = Transform3D(Basis.IDENTITY, pos)

# Os três abaixo aplicam o mesmo efeito em todo mundo; offline chamam direto, online o
# host transmite -- sempre com call_local, porque a máquina do host também precisa do
# efeito (o progresso vai unreliable, como a barra da serraria).

func _dig_state(player_name: String, active: bool) -> void:
	if NetworkManager.is_online:
		_net_dig_state.rpc(player_name, active)
	else:
		_local_dig_state(player_name, active)

func _dig_progress(spot_name: String, p: float) -> void:
	if NetworkManager.is_online:
		_net_dig_progress.rpc(spot_name, p)
	else:
		_local_dig_progress(spot_name, p)

func _dig_result(spot_name: String, found: bool) -> void:
	if NetworkManager.is_online:
		_net_dig_result.rpc(spot_name, found)
	else:
		_local_dig_result(spot_name, found)

@rpc("authority", "call_local", "reliable")
func _net_dig_state(player_name: String, active: bool) -> void:
	_local_dig_state(player_name, active)

## call_local é obrigatório aqui: diferente da serraria (que atualiza a própria barra no
## _process), este broadcast é o ÚNICO lugar que escreve o progresso -- sem ele o host
## fica sem barra na própria tela.
@rpc("authority", "call_local", "unreliable_ordered")
func _net_dig_progress(spot_name: String, p: float) -> void:
	_local_dig_progress(spot_name, p)

@rpc("authority", "call_local", "reliable")
func _net_dig_result(spot_name: String, found: bool) -> void:
	_local_dig_result(spot_name, found)

func _local_dig_state(player_name: String, active: bool) -> void:
	var p := players.get_node_or_null(player_name)
	if p != null and p.has_method("set_digging"):
		p.set_digging(active)

func _local_dig_progress(spot_name: String, p: float) -> void:
	var spot: Node = _net_items.get(spot_name)
	if spot != null and spot.has_method("set_progress"):
		spot.set_progress(p)

func _local_dig_result(spot_name: String, found: bool) -> void:
	var spot: Node = _net_items.get(spot_name)
	if spot != null and spot.has_method("resolve"):
		spot.resolve(found)

# --- Networked match: replicated players (robust, per-peer spawn) ----------
# Movement is client-authoritative, but the host owns spawning. Each peer, once its
# Arena scene is up, pings the host "ready"; the host spawns THAT peer's penguin on
# everyone already in, and catches the newcomer up on the ones spawned before it.
# There's NO all-or-nothing wait: a lost/early ping just gets retried (see _process),
# so a dropped handshake can never leave the match empty (the "no penguins" bug).

func _start_net_match() -> void:
	if multiplayer.is_server():
		_net_ready.clear()
		_net_slot_counter = 0
		_net_on_ready(1) # the host itself (peer 1) -- spawns immediately
	else:
		_net_client_ready.rpc_id(1)

func _process(delta: float) -> void:
	# Client re-pings "ready" until its own penguin exists -- self-heals a lost or
	# too-early handshake. No-op on the host and offline.
	if not NetworkManager.is_online or multiplayer.is_server():
		_tick_digs(delta) # quem cronometra as escavações: offline esta máquina, online o host
		return
	if players.has_node(str(multiplayer.get_unique_id())):
		return
	_net_ready_timer -= delta
	if _net_ready_timer <= 0.0:
		_net_ready_timer = 0.5
		_net_client_ready.rpc_id(1)

## Client -> host: "my Arena scene is up." Safe to call repeatedly (host is idempotent).
@rpc("any_peer", "reliable")
func _net_client_ready() -> void:
	if multiplayer.is_server():
		_net_on_ready(multiplayer.get_remote_sender_id())

func _net_on_ready(pid: int) -> void:
	if not multiplayer.is_server():
		return
	if _net_ready.has(pid):
		_net_send_world_to(pid) # a retry -> just re-send the whole roster to them
		return
	var slot := _net_slot_counter
	_net_slot_counter += 1
	_net_ready[pid] = slot
	# Spawn the newcomer on everyone already in (themselves included)...
	for q in _net_ready:
		_net_spawn_player.rpc_id(q, pid, NetworkManager.color_for_peer(pid), _net_spawn_transform(slot))
	# ...and catch the newcomer up on everyone who arrived before them.
	_net_send_world_to(pid)

## Send every already-ready peer's penguin to one target peer.
func _net_send_world_to(target: int) -> void:
	for other in _net_ready:
		_net_spawn_player.rpc_id(
			target, other, NetworkManager.color_for_peer(other), _net_spawn_transform(_net_ready[other]))

## Host -> a peer: create a penguin. Idempotent -- guards against retry/catch-up dupes.
## The color index (chosen in the lobby) is passed so every machine paints it the same.
@rpc("authority", "call_local", "reliable")
func _net_spawn_player(peer_id: int, color_index: int, xform: Transform3D) -> void:
	if players.has_node(str(peer_id)):
		return
	var player := player_scene.instantiate()
	player.name = str(peer_id) # must be set BEFORE _ready so authority is right
	players.add_child(player)
	player.transform = xform
	player.set_color(PlayerManager.color_for_slot(color_index))
	player.set_spawn_info(xform, _water_level())

func _net_spawn_transform(index: int) -> Transform3D:
	var n := spawn_points.get_child_count()
	if n > 0:
		return (spawn_points.get_child(clampi(index, 0, n - 1)) as Node3D).transform
	return Transform3D(Basis.IDENTITY, Vector3(index * 2.0, 1.0, 0.0))

## Water surface Y for this level (drives drowning). The terrain has it after build_from.
func _water_level() -> float:
	return float(terrain.water_level)

# --- Water deaths (host-authoritative online) -----------------------------
# The owner of a penguin detects its own drowning; online it reports here and the
# host decides + broadcasts, so death/respawn stay consistent on every machine.

func report_drown(player_name: String) -> void:
	if not NetworkManager.is_online:
		return # couch is handled locally by the player
	if multiplayer.is_server():
		_host_drown(player_name)
	else:
		_req_drown.rpc_id(1, player_name)

@rpc("any_peer", "reliable")
func _req_drown(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := players.get_node_or_null(player_name)
	if p != null and p.get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_host_drown(player_name)

func _host_drown(player_name: String) -> void:
	var p := players.get_node_or_null(player_name)
	if p == null or p.is_dead():
		return
	# Drop what they carried on safe ground (their spawn) so it isn't lost underwater.
	var carried: Node3D = p.get_carried()
	if carried != null:
		var pos: Vector3 = p.get_spawn_origin()
		pos.y = 0.25
		host_drop(player_name, str(carried.name), Transform3D(Basis.IDENTITY, pos))
	_net_die.rpc(player_name)
	var delay: float = p.respawn_delay
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(p):
		_net_respawn.rpc(player_name)

@rpc("authority", "call_local", "reliable")
func _net_die(player_name: String) -> void:
	var p := players.get_node_or_null(player_name)
	if p != null:
		p.die()

@rpc("authority", "call_local", "reliable")
func _net_respawn(player_name: String) -> void:
	var p := players.get_node_or_null(player_name)
	if p != null:
		p.respawn()

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
