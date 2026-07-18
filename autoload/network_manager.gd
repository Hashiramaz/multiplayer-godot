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

const MAX_LOBBY_MEMBERS: int = 4
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

var _peer: MultiplayerPeer = null

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect_steam_signals()

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
	multiplayer.multiplayer_peer = null
	_peer = null
	is_online = false
	is_host = false
	lobby_id = 0

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
	hosted.emit(lobby_id)

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

## Accepting a Steam overlay invite routes here with the target lobby.
func _on_join_requested(request_lobby_id: int, _friend_id: int) -> void:
	join_lobby(request_lobby_id)

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
	peers_changed.emit()

func _on_connected_to_server() -> void:
	print("NetworkManager: conectado ao host")
	is_online = true
	joined.emit()

func _on_connection_failed() -> void:
	push_warning("NetworkManager: falha ao conectar")
	connection_failed.emit("connection_failed")

func _on_server_disconnected() -> void:
	is_online = false
	push_warning("NetworkManager: host caiu")
	peers_changed.emit()

# --- Helpers --------------------------------------------------------------

func _require_steam() -> bool:
	if SteamManager.available:
		return true
	push_warning("NetworkManager: Steam indisponível (addon não instalado ou offline).")
	connection_failed.emit("steam_unavailable")
	return false
