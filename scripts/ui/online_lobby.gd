extends Control
## Connected online lobby: shows the roster with colors, lets you pick your penguin
## color and leave, and (host only) kick players, invite friends, and start the match.
## Reached automatically on host/join (incl. accepting a Steam invite).

@onready var status: Label = $VBox/Status
@onready var members_list: VBoxContainer = $VBox/MembersList
@onready var color_row: HBoxContainer = $VBox/ColorRow
@onready var level_label: Label = $VBox/LevelRow/LevelLabel
@onready var level_picker: OptionButton = $VBox/LevelRow/LevelPicker
@onready var start_button: Button = $VBox/ButtonsRow/StartButton
@onready var leave_button: Button = $VBox/ButtonsRow/LeaveButton
@onready var invite_button: Button = $VBox/InviteButton
@onready var friends_label: Label = $VBox/FriendsLabel
@onready var friends_scroll: ScrollContainer = $VBox/FriendsScroll
@onready var friends_list: VBoxContainer = $VBox/FriendsScroll/FriendsList

var _color_buttons: Array[Button] = []
var _levels: Array = [] # [{ name, path }] -- shippable levels, index == picker item

func _ready() -> void:
	GameManager.set_state(GameManager.State.ONLINE)
	start_button.pressed.connect(NetworkManager.start_online_match)
	leave_button.pressed.connect(_on_leave)
	invite_button.pressed.connect(NetworkManager.invite_friends)
	NetworkManager.lobby_changed.connect(_refresh)
	NetworkManager.peers_changed.connect(_refresh)
	_build_color_buttons()
	_build_level_picker()
	_refresh()
	leave_button.grab_focus()

func _build_level_picker() -> void:
	_levels = LevelData.shared_levels()
	for lv in _levels:
		level_picker.add_item(str(lv["name"]))
	level_picker.item_selected.connect(_on_level_picked)
	_select_current_level()

func _on_level_picked(idx: int) -> void:
	NetworkManager.set_level(str(_levels[idx]["path"]))

func _select_current_level() -> void:
	for i in _levels.size():
		if str(_levels[i]["path"]) == NetworkManager.selected_level_path:
			level_picker.select(i)
			return

func _name_for_level(path: String) -> String:
	for lv in _levels:
		if str(lv["path"]) == path:
			return str(lv["name"])
	return "?"

func _is_host() -> bool:
	return multiplayer.is_server()

func _build_color_buttons() -> void:
	for i in NetworkManager.NUM_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 42)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PlayerManager.color_for_slot(i)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("disabled", sb)
		b.pressed.connect(NetworkManager.choose_color.bind(i))
		color_row.add_child(b)
		_color_buttons.append(b)

func _refresh() -> void:
	var my_id := multiplayer.get_unique_id()
	status.text = "Lobby #%d — %s" % [
		NetworkManager.lobby_id, "você é o host" if _is_host() else "conectado"]

	for c in members_list.get_children():
		c.queue_free()
	var my_color := -1
	var taken := {} # color_index -> owner peer id
	for id in NetworkManager.members:
		var m: Dictionary = NetworkManager.members[id]
		var cidx := int(m["color"])
		taken[cidx] = int(id)
		if int(id) == my_id:
			my_color = cidx
		members_list.add_child(_member_row(int(id), str(m["name"]), cidx, my_id))

	# Own color highlighted; colors taken by OTHERS are disabled.
	for i in _color_buttons.size():
		var btn := _color_buttons[i]
		btn.disabled = taken.has(i) and int(taken[i]) != my_id
		btn.text = "✓" if i == my_color else ""

	level_label.text = "Fase: " + _name_for_level(NetworkManager.selected_level_path)
	level_picker.visible = _is_host() # only the host chooses; others just see it
	_select_current_level()

	start_button.visible = _is_host()
	invite_button.visible = _is_host()
	friends_label.visible = _is_host()
	friends_scroll.visible = _is_host()
	if _is_host():
		_refresh_friends()

func _member_row(id: int, pname: String, color_index: int, my_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(24, 24)
	swatch.color = PlayerManager.color_for_slot(color_index)
	row.add_child(swatch)
	var name_label := Label.new()
	var tag := "  (host)" if id == 1 else ("  (você)" if id == my_id else "")
	name_label.text = pname + tag
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if _is_host() and id != 1:
		var kick := Button.new()
		kick.text = "Expulsar"
		kick.pressed.connect(NetworkManager.kick.bind(id))
		row.add_child(kick)
	return row

func _refresh_friends() -> void:
	for c in friends_list.get_children():
		c.queue_free()
	var friends := NetworkManager.list_friends()
	if friends.is_empty():
		var l := Label.new()
		l.text = "Nenhum amigo online."
		friends_list.add_child(l)
		return
	for f in friends:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		var in_game: bool = f.get("in_game", false)
		name_label.text = "%s%s" % [f.get("name", "?"), "  •  no jogo" if in_game else ""]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.text = "Convidar"
		b.pressed.connect(NetworkManager.invite_user.bind(int(f["id"])))
		row.add_child(name_label)
		row.add_child(b)
		friends_list.add_child(row)

func _on_leave() -> void:
	NetworkManager.leave()
	GameManager.go_to_online()

## Bridge the gamepad's A to the focused button (default ui_accept not firing on pad).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			get_viewport().set_input_as_handled()
			(focused as BaseButton).pressed.emit()
