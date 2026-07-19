extends Control
## Online entry: host a match, or find/join one. On host/join we're taken to the
## dedicated lobby screen automatically (NetworkManager.go_to_online_lobby).

@onready var status: Label = $VBox/Status
@onready var host_button: Button = $VBox/Actions/HostButton
@onready var refresh_button: Button = $VBox/Actions/RefreshButton
@onready var lobby_list: VBoxContainer = $VBox/LobbyScroll/LobbyList
@onready var lobby_input: LineEdit = $VBox/JoinRow/LobbyInput
@onready var join_button: Button = $VBox/JoinRow/JoinButton
@onready var back_button: Button = $VBox/BackButton

func _ready() -> void:
	GameManager.set_state(GameManager.State.ONLINE)
	host_button.pressed.connect(_on_host)
	refresh_button.pressed.connect(_on_refresh)
	join_button.pressed.connect(_on_join)
	back_button.pressed.connect(_on_back)
	NetworkManager.lobby_list_updated.connect(_on_lobby_list_updated)
	NetworkManager.connection_failed.connect(_on_failed)
	_update_steam_status()
	host_button.grab_focus()
	if SteamManager.available:
		_on_refresh()

func _update_steam_status() -> void:
	if SteamManager.available:
		status.text = "Steam: %s" % SteamManager.persona
	else:
		status.text = "Steam indisponível — abra a Steam e reinicie o jogo."
		host_button.disabled = true
		refresh_button.disabled = true
		join_button.disabled = true

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

func _on_refresh() -> void:
	_clear(lobby_list)
	_hint(lobby_list, "Procurando partidas...")
	NetworkManager.refresh_lobbies()

func _on_lobby_list_updated(lobbies: Array) -> void:
	_clear(lobby_list)
	if lobbies.is_empty():
		_hint(lobby_list, "Nenhuma partida aberta. Clique em Hospedar.")
		return
	for info in lobbies:
		var b := Button.new()
		var host_name := str(info.get("host", ""))
		if host_name.is_empty():
			host_name = "Partida"
		b.text = "%s — %d/%d" % [host_name, int(info.get("members", 0)), int(info.get("max", 0))]
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(_join_id.bind(int(info["id"])))
		lobby_list.add_child(b)

func _join_id(id: int) -> void:
	status.text = "Entrando na partida..."
	NetworkManager.join_lobby(id)

func _on_failed(reason: String) -> void:
	status.text = "Falha: %s" % reason

func _clear(container: Node) -> void:
	for c in container.get_children():
		c.queue_free()

func _hint(container: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(l)

func _on_back() -> void:
	NetworkManager.leave()
	GameManager.go_to_main_menu()
