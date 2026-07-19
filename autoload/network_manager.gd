extends Node
## Owns the online session and creates the MultiplayerPeer. The transport lives
## behind this façade -- today it's Steam via GodotSteam's built-in SteamMultiplayerPeer
## (create_host/create_client), but the rest of the game only touches Godot's
## `multiplayer` API + these methods, so the peer stays swappable without touching gameplay.
##
## Degrades gracefully if the Steam addons are missing: the peer is created via
## ClassDB so this autoload still PARSES/loads (the game boots), it just reports
## "online indisponível". See docs: online phase O1.

signal hosted(lobby_id: int)          ## Local player became host; lobby is open.
signal joined()                        ## Local player connected to a host.
signal peers_changed()                 ## Someone connected/disconnected.
signal connection_failed(reason: String)
## Browsable lobbies: Array of { id, host, members, max }.
signal lobby_list_updated(lobbies: Array)
## Roster/colors changed -- drives the lobby screen.
signal lobby_changed()

const MAX_LOBBY_MEMBERS: int = 4
const NUM_COLORS: int = 4 # PlayerManager.PLAYER_COLORS.size()
## Lobby data tags. `game` is what isolates our lobbies from the sea of other
## Spacewar (480) lobbies; `host` carries the host's name so the browser can show it
## without needing persona data for strangers.
const LOBBY_KEY_GAME: String = "game"
const LOBBY_VALUE_GAME: String = "escape-the-island"
const LOBBY_KEY_HOST: String = "host"
const LOBBY_MAX_RESULTS: int = 50

# GodotSteam enum values, kept as literals so this script still PARSES without the
# addon (we never name the `Steam` global at compile time). Verified against v4.20.
const STEAM_LOBBY_TYPE_PUBLIC: int = 2
const STEAM_LOBBY_COMPARISON_EQUAL: int = 0
const STEAM_LOBBY_DISTANCE_WORLDWIDE: int = 3
const STEAM_FRIEND_FLAG_IMMEDIATE: int = 4
const STEAM_PERSONA_STATE_OFFLINE: int = 0
## EResult / enter-response "OK" code from the Steamworks API.
const STEAM_RESULT_OK: int = 1

var is_online: bool = false
var is_host: bool = false
var lobby_id: int = 0

## Lobby roster, host-authoritative: peer_id(int) -> { "name": String, "color": int }.
var members: Dictionary = {}

var _peer: MultiplayerPeer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # session handling must survive a pause
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect_steam_signals()
	call_deferred("_check_launch_invite") # cold-start Steam invite, if any

func _connect_steam_signals() -> void:
	var steam := SteamManager.api()
	if steam == null:
		return
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("join_requested", _on_join_requested)
	steam.connect("lobby_match_list", _on_lobby_match_list)

# --- Public API (chamado pelo menu Online) --------------------------------

func host_game() -> void:
	if not _require_steam():
		return
	is_host = true
	SteamManager.api().createLobby(STEAM_LOBBY_TYPE_PUBLIC, MAX_LOBBY_MEMBERS)
	# Segue em _on_lobby_created.

func join_lobby(target_lobby_id: int) -> void:
	if not _require_steam():
		return
	is_host = false
	SteamManager.api().joinLobby(target_lobby_id)
	# Segue em _on_lobby_joined.

## Host-only: sends everyone (including the host) into the Arena scene together.
func start_online_match() -> void:
	if not multiplayer.is_server():
		return
	_rpc_go_to_arena.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_go_to_arena() -> void:
	GameManager.start_match()

## Opens the Steam overlay invite dialog for the current lobby (Shift+Tab UX).
## NOTE: the overlay only injects when the game is launched THROUGH Steam, so for
## builds run straight from the folder this silently does nothing -- use the lobby
## browser or invite_user() instead.
func invite_friends() -> void:
	if lobby_id == 0 or not _require_steam():
		return
	SteamManager.api().activateGameOverlayInviteDialog(lobby_id)

# --- Lobby browser --------------------------------------------------------
# Asks Steam for open lobbies tagged as ours. This is the no-overlay, no-lobby-id
# path: the host just hosts, everyone else sees the match in a list.

func refresh_lobbies() -> void:
	if not _require_steam():
		return
	var steam := SteamManager.api()
	# Without the game filter we'd get every Spacewar (480) lobby on Steam.
	steam.addRequestLobbyListStringFilter(
		LOBBY_KEY_GAME, LOBBY_VALUE_GAME, STEAM_LOBBY_COMPARISON_EQUAL)
	steam.addRequestLobbyListDistanceFilter(STEAM_LOBBY_DISTANCE_WORLDWIDE)
	steam.addRequestLobbyListResultCountFilter(LOBBY_MAX_RESULTS)
	steam.requestLobbyList()
	# Segue em _on_lobby_match_list.

func _on_lobby_match_list(lobbies: Array) -> void:
	var steam := SteamManager.api()
	var out: Array = []
	for id in lobbies:
		out.append({
			"id": id,
			"host": steam.getLobbyData(id, LOBBY_KEY_HOST),
			"members": steam.getNumLobbyMembers(id),
			"max": steam.getLobbyMemberLimit(id),
		})
	lobby_list_updated.emit(out)

# --- Friends + direct invites ---------------------------------------------
# inviteUserToLobby does NOT need the overlay: Steam delivers the invite, and the
# friend's running game picks it up via the join_requested signal below.

## Online friends: Array of { id, name, in_game }, those already in-game first.
func list_friends() -> Array:
	if not SteamManager.available:
		return []
	var steam := SteamManager.api()
	var out: Array = []
	var count: int = steam.getFriendCount(STEAM_FRIEND_FLAG_IMMEDIATE)
	for i in count:
		var fid: int = steam.getFriendByIndex(i, STEAM_FRIEND_FLAG_IMMEDIATE)
		if steam.getFriendPersonaState(fid) == STEAM_PERSONA_STATE_OFFLINE:
			continue
		out.append({
			"id": fid,
			"name": str(steam.getFriendPersonaName(fid)),
			"in_game": _is_playing_our_game(steam.getFriendGamePlayed(fid)),
		})
	out.sort_custom(func(a, b): return int(a["in_game"]) > int(b["in_game"]))
	return out

## The shape of getFriendGamePlayed's dictionary varies by version, so probe the
## plausible app-id keys instead of betting on one.
func _is_playing_our_game(game: Dictionary) -> bool:
	if game.is_empty():
		return false
	for key in ["id", "app_id", "game_id", "appid"]:
		if game.has(key) and int(game[key]) == SteamManager.TEST_APP_ID:
			return true
	return false

func invite_user(friend_id: int) -> void:
	if lobby_id == 0 or not _require_steam():
		return
	# Arg order matters: (lobby, invitee) -- verified against GodotSteam v4.20.
	SteamManager.api().inviteUserToLobby(lobby_id, friend_id)

func leave() -> void:
	if lobby_id != 0 and SteamManager.available:
		SteamManager.api().leaveLobby(lobby_id)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	# Restore the pristine offline peer (unique id 1) instead of leaving it null --
	# with null, is_multiplayer_authority() goes false and would freeze couch players.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	is_online = false
	is_host = false
	lobby_id = 0
	members.clear()

## Peer ids in the session, including ourselves.
func player_count() -> int:
	if not (is_online or is_host):
		return 0
	return multiplayer.get_peers().size() + 1

# --- Steam lobby callbacks ------------------------------------------------

func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != STEAM_RESULT_OK:
		is_host = false
		connection_failed.emit("lobby_create_failed(%d)" % result)
		return
	lobby_id = new_lobby_id
	var steam := SteamManager.api()
	steam.setLobbyData(lobby_id, LOBBY_KEY_GAME, LOBBY_VALUE_GAME)
	steam.setLobbyData(lobby_id, LOBBY_KEY_HOST, SteamManager.persona)
	var err := _create_peer_host()
	if err != OK:
		connection_failed.emit("host_peer_failed(%d)" % err)
		return
	is_online = true
	members.clear()
	_host_add_member(1, SteamManager.persona) # the host is peer 1
	hosted.emit(lobby_id)
	GameManager.go_to_online_lobby()

func _on_lobby_joined(joined_lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	if response != STEAM_RESULT_OK:
		connection_failed.emit("lobby_join_failed(%d)" % response)
		return
	lobby_id = joined_lobby_id
	var owner_id: int = SteamManager.api().getLobbyOwner(lobby_id)
	if owner_id == SteamManager.steam_id:
		return # We're the host; the host peer is already set up.
	var err := _create_peer_client(owner_id)
	if err != OK:
		connection_failed.emit("client_peer_failed(%d)" % err)

## Accepting a Steam overlay invite (game already running) routes here.
func _on_join_requested(request_lobby_id: int, _friend_id: int) -> void:
	join_lobby(request_lobby_id)

# --- Lobby roster (host-authoritative) ------------------------------------
# The host owns `members` and broadcasts the whole dict on every change. Clients
# only display it and send requests (register name, pick color) back to the host.

func _host_add_member(id: int, pname: String) -> void:
	if not multiplayer.is_server():
		return
	members[id] = { "name": pname, "color": _host_free_color() }
	_broadcast_members()

func _host_free_color() -> int:
	var used := {}
	for m in members.values():
		used[int(m["color"])] = true
	for c in NUM_COLORS:
		if not used.has(c):
			return c
	return 0

func _broadcast_members() -> void:
	if multiplayer.is_server():
		_sync_members.rpc(members)

@rpc("authority", "call_local", "reliable")
func _sync_members(data: Dictionary) -> void:
	members = data
	lobby_changed.emit()

## Client -> host: "I'm in, here's my name." Host adds us + assigns a free color.
@rpc("any_peer", "reliable")
func _register_member(pname: String) -> void:
	if not multiplayer.is_server():
		return
	_host_add_member(multiplayer.get_remote_sender_id(), pname)

## Anyone can ask for a color; the host grants it only if it's free.
func choose_color(index: int) -> void:
	if multiplayer.is_server():
		_apply_color(multiplayer.get_unique_id(), index)
	else:
		_request_color.rpc_id(1, index)

@rpc("any_peer", "reliable")
func _request_color(index: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_color(multiplayer.get_remote_sender_id(), index)

func _apply_color(id: int, index: int) -> void:
	if not multiplayer.is_server() or index < 0 or index >= NUM_COLORS:
		return
	for k in members:
		if k != id and int(members[k]["color"]) == index:
			return # already taken
	if members.has(id):
		members[id]["color"] = index
		_broadcast_members()

## Host-only: boot a peer. RPC tells them to leave; we also drop them + cut the link.
func kick(id: int) -> void:
	if not multiplayer.is_server() or id == 1:
		return
	_kicked.rpc_id(id)
	if members.has(id):
		members.erase(id)
		_broadcast_members()
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.has_method("disconnect_peer"):
		peer.disconnect_peer(id)

## Host -> a specific client: you were removed; back to the online menu.
@rpc("authority", "reliable")
func _kicked() -> void:
	leave()
	GameManager.go_to_online()

## Color index a peer picked, used when spawning. Defaults to 0 if unknown.
func color_for_peer(id: int) -> int:
	if members.has(id):
		return int(members[id]["color"])
	return 0

## Cold-start invite: Steam launches the game with "+connect_lobby <id>" when a
## friend accepts an invite while the game is closed. Join it once we're ready.
func _check_launch_invite() -> void:
	if not SteamManager.available:
		return
	var args := OS.get_cmdline_args()
	var idx := args.find("+connect_lobby")
	if idx != -1 and idx + 1 < args.size():
		var lid := int(args[idx + 1])
		if lid != 0:
			join_lobby(lid)

# --- Peer creation (SteamMultiplayerPeer via ClassDB) ---------------------

func _create_peer_host() -> int:
	_peer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if _peer == null:
		return FAILED
	var err: int = _peer.call("create_host", 0)
	if err == OK:
		multiplayer.multiplayer_peer = _peer
	return err

func _create_peer_client(host_steam_id: int) -> int:
	_peer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if _peer == null:
		return FAILED
	var err: int = _peer.call("create_client", host_steam_id, 0)
	if err == OK:
		multiplayer.multiplayer_peer = _peer
	return err

# --- MultiplayerAPI callbacks ---------------------------------------------

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: peer conectado %d" % id)
	peers_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: peer saiu %d" % id)
	if multiplayer.is_server() and members.has(id):
		members.erase(id)
		_broadcast_members()
	peers_changed.emit()

func _on_connected_to_server() -> void:
	print("NetworkManager: conectado ao host")
	is_online = true
	joined.emit()
	# Tell the host who we are so it can add us to the roster + assign a color.
	_register_member.rpc_id(1, SteamManager.persona)
	GameManager.go_to_online_lobby()

func _on_connection_failed() -> void:
	push_warning("NetworkManager: falha ao conectar")
	connection_failed.emit("connection_failed")

func _on_server_disconnected() -> void:
	is_online = false
	members.clear()
	push_warning("NetworkManager: host caiu")
	peers_changed.emit()
	lobby_changed.emit()
	# Host went away -- bounce back to the online entry screen.
	GameManager.go_to_online()

# --- Helpers --------------------------------------------------------------

func _require_steam() -> bool:
	if SteamManager.available:
		return true
	push_warning("NetworkManager: Steam indisponível (addon não instalado ou offline).")
	connection_failed.emit("steam_unavailable")
	return false
