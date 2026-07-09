extends Control
## Local join screen. Each device claims a slot; any joined player starts the
## match. Input is read per-device (same model as gameplay) in _input so it isn't
## swallowed by the UI focus system.
##   Gamepad:  A = join    B = leave    Start = begin
##   Keyboard: Enter = join  Esc = leave  Space = begin

@onready var slots_box: HBoxContainer = $VBox/Slots
@onready var title: Label = $VBox/Title
@onready var instructions: Label = $VBox/Instructions

var _slot_labels: Array[Label] = []

func _ready() -> void:
	GameManager.set_state(GameManager.State.LOBBY)
	title.add_theme_font_size_override("font_size", 34)
	instructions.add_theme_font_size_override("font_size", 18)
	_build_slots()
	PlayerManager.player_joined.connect(_on_roster_changed)
	PlayerManager.player_left.connect(_on_roster_changed)
	_refresh()

func _build_slots() -> void:
	for i in PlayerManager.MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(170, 210)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		panel.add_child(label)
		slots_box.add_child(panel)
		_slot_labels.append(label)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A:
				PlayerManager.join(event.device)
			JOY_BUTTON_B:
				PlayerManager.leave(event.device)
			JOY_BUTTON_START:
				_try_start()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				PlayerManager.join(PlayerInput.DEVICE_KEYBOARD)
			KEY_ESCAPE, KEY_BACKSPACE:
				PlayerManager.leave(PlayerInput.DEVICE_KEYBOARD)
			KEY_SPACE:
				_try_start()

func _try_start() -> void:
	if PlayerManager.slot_count() > 0:
		GameManager.start_match()

func _on_roster_changed(_slot: int, _device: int) -> void:
	_refresh()

func _refresh() -> void:
	for i in _slot_labels.size():
		var label := _slot_labels[i]
		if i < PlayerManager.slot_count():
			var device: int = PlayerManager.registered_devices[i]
			label.text = "Player %d\n%s\n\n● PRONTO" % [i + 1, _device_name(device)]
			label.modulate = PlayerManager.color_for_slot(i)
		else:
			label.text = "Vazio\n\n[ A / Enter ]"
			label.modulate = Color(1.0, 1.0, 1.0, 0.35)

func _device_name(device: int) -> String:
	if device == PlayerInput.DEVICE_KEYBOARD:
		return "Teclado"
	return "Controle %d" % device
