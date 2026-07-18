extends Control
## Online lobby screen. Two ways in without ever typing an id: browse open matches
## (Steam lobby list, filtered to our game tag) or accept a direct friend invite.
## The manual id field stays as a fallback. Starting the match into the networked
## Arena is host-only.

@onready var status: Label = $VBox/Status
@onready var host_button: Button = $VBox/Actions/HostButton
@onready var refresh_button: Button = $VBox/Actions/RefreshButton
@onready var lobby_list: VBoxContainer = $VBox/LobbyScroll/LobbyList
@onready var lobby_input: LineEdit = $VBox/JoinRow/LobbyInput
@onready var join_button: Button = $VBox/JoinRow/JoinButton
@onready var lobby_id_label: Label = $VBox/LobbyIdLabel
@onready var peers_label: Label = $VBox/PeersLabel
@onready var friends_label: Label = $VBox/FriendsLabel
@onready var friends_scroll: ScrollContainer = $VBox/FriendsScroll
@onready var friends_list: VBoxContainer = $VBox/FriendsScroll/FriendsList
@onready var invite_button: Button = $VBox/Bottom/InviteButton
@onready var start_button: Button = $VBox/Bottom/StartButton
@onready var back_button: Button = $VBox/BackButton

func _ready() -> void:
	GameManager.set_state(GameManager.State.ONLINE)
	host_button.pressed.connect(_on_host)
	refresh_button.pressed.connect(_on_refresh)
	join_button.pressed.connect(_on_join)
	invite_button.pressed.connect(NetworkManager.invite_friends)
	start_button.pressed.connect(NetworkManager.start_online_match)
	back_button.pressed.connect(_on_back)

	NetworkManager.hosted.connect(_on_hosted)
	NetworkManager.joined.connect(_on_joined)
	NetworkManager.peers_changed.connect(_refresh_peers)
	NetworkManager.connection_failed.connect(_on_failed)
	NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)

	_set_host_ui_visible(false)
	lobby_id_label.text = ""
	peers_label.text = ""
	_update_steam_status()
	host_button.grab_focus()
	if SteamManager.available:
		_on_refresh() # show open matches immediately on open

## The friends/invite/start block only makes sense once we're the host.
func _set_host_ui_visible(v: bool) -> void:
	friends_label.visible = v
	friends_scroll.visible = v
	invite_button.visible = v
	start_button.visible = v

func _update_steam_status() -> void:
	if SteamManager.available:
		status.text = "Steam: %s" % SteamManager.persona
	else:
		status.text = "Steam indisponível — abra a Steam e reinicie o jogo."
		host_button.disabled = true
		join_button.disabled = true
		refresh_button.disabled = true

# --- Hosting / joining ----------------------------------------------------

func _on_host() -> void:
	status.text = "Criando lobby..."
	NetworkManager.host_game()

func _on_join() -> void:
	var id := lobby_input.text.strip_edges()
	if not id.is_valid_int():
		status.text = "Digite um ID de lobby válido."
		return
	status.text = "Entrando no lobby..."
	NetworkManager.join_lobby(int(id))

func _join_from_list(id: int) -> void:
	status.text = "Entrando na partida..."
	NetworkManager.join_lobby(id)

func _on_hosted(new_lobby_id: int) -> void:
	# Overlay invites only work when launched through Steam, so copying the id keeps
	# the "paste it in Discord" path available as a last resort.
	DisplayServer.clipboard_set(str(new_lobby_id))
	status.text = "Lobby aberto! Seus amigos já veem em 'Procurar partidas'."
	lobby_id_label.text = "ID do lobby: %d (copiado)" % new_lobby_id
	_set_host_ui_visible(true)
	_refresh_friends()
	start_button.grab_focus()
	_refresh_peers()

func _on_joined() -> void:
	status.text = "Conectado! Aguardando o host iniciar..."
	_refresh_peers()

func _on_failed(reason: String) -> void:
	status.text = "Falha: %s" % reason

func _refresh_peers() -> void:
	var count := NetworkManager.player_count()
	peers_label.text = "Jogadores conectados: %d" % count if count > 0 else ""

# --- Lobby browser --------------------------------------------------------

func _on_refresh() -> void:
	_clear(lobby_list)
	_add_hint(lobby_list, "Procurando partidas...")
	NetworkManager.refresh_lobbies()

func _on_lobby_list_updated(lobbies: Array) -> void:
	_clear(lobby_list)
	if lobbies.is_empty():
		_add_hint(lobby_list, "Nenhuma partida aberta. Alguém precisa clicar em Hospedar.")
		return
	for info in lobbies:
		var b := Button.new()
		var host_name := str(info.get("host", ""))
		if host_name.is_empty():
			host_name = "Partida"
		b.text = "%s — %d/%d" % [host_name, int(info.get("members", 0)), int(info.get("max", 0))]
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(_join_from_list.bind(int(info["id"])))
		lobby_list.add_child(b)

# --- Friends + invites ----------------------------------------------------

func _refresh_friends() -> void:
	_clear(friends_list)
	var friends := NetworkManager.list_friends()
	if friends.is_empty():
		_add_hint(friends_list, "Nenhum amigo online.")
		return
	for f in friends:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		var in_game: bool = f.get("in_game", false)
		name_label.text = "%s%s" % [f.get("name", "?"), "  •  no jogo" if in_game else ""]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.text = "Convidar"
		b.custom_minimum_size = Vector2(100, 32)
		b.pressed.connect(_invite.bind(int(f["id"]), str(f.get("name", "?"))))
		row.add_child(name_label)
		row.add_child(b)
		friends_list.add_child(row)

func _invite(friend_id: int, friend_name: String) -> void:
	NetworkManager.invite_user(friend_id)
	status.text = "Convite enviado para %s." % friend_name

# --- Helpers --------------------------------------------------------------

func _clear(container: Node) -> void:
	for c in container.get_children():
		c.queue_free()

func _add_hint(container: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(l)

func _on_back() -> void:
	NetworkManager.leave()
	GameManager.go_to_main_menu()
