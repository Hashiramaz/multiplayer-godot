extends CanvasLayer
## Runs the match: a countdown "threat clock" (the island closing in). Win when the
## boat is completed in time; lose when the clock hits zero. Shows the HUD timer and
## the end-of-match result screen.
##
## PAUSABLE process mode on purpose: the pause menu (get_tree().paused) freezes the
## clock too. The end-of-match freeze instead just disables the players, so the
## result screen's own buttons keep working without touching get_tree().paused.

@export var low_time_warning: float = 15.0

var _time_left: float = 0.0
var _over: bool = false
var _active: bool = false
## O barco, guardado no configure: além do sinal de vitória, é dele que sai o estado do
## objetivo secundário (baú embarcado) na hora de contar as estrelas.
var _boat: Node = null

## Estrelas: 3 = escapou COM o tesouro, 2 = escapou sem, 0 = derrota (o caso de 1
## estrela ainda não tem regra definida).
const STAR_GLYPHS := { 3: "★★★", 2: "★★☆", 1: "★☆☆" }

## Online: the host owns the clock and the ending; clients only display what it sends.
var _online: bool = false
var _is_host: bool = false
var _last_sent_sec: int = -1

@onready var timer_label: Label = $HUD/TimerLabel
@onready var result_panel: Control = $Result
@onready var result_title: Label = $Result/VBox/Title
@onready var result_stars: Label = $Result/VBox/Stars
@onready var replay_button: Button = $Result/VBox/Replay
@onready var menu_button: Button = $Result/VBox/Menu

func _ready() -> void:
	result_panel.visible = false
	_update_timer_label()
	replay_button.pressed.connect(_on_replay)
	menu_button.pressed.connect(_on_menu)

## Called by the Arena AFTER the level (and its boat) is built, so the countdown and
## the win condition wire up against objects that now exist in the tree. This node's
## own _ready runs before the Arena spawns content, hence the split.
func configure(level: LevelData) -> void:
	_time_left = level.match_duration
	_active = true
	_online = NetworkManager.is_online
	_is_host = (not _online) or multiplayer.is_server()
	_update_timer_label()

	# The sawmill is ALSO in group "station", so pick the one that actually has the
	# 'completed' signal (the boat) instead of whatever comes first.
	var boat: Node = null
	for s in get_tree().get_nodes_in_group("station"):
		if s.has_signal("completed"):
			boat = s
			break
	_boat = boat
	if boat != null:
		boat.completed.connect(_on_boat_completed)
	else:
		push_warning("MatchUI: no station with a 'completed' signal found.")

func _process(delta: float) -> void:
	if not _active or _over:
		return
	if _online and not _is_host:
		return # clients get the time (and the ending) from the host
	_time_left = maxf(_time_left - delta, 0.0)
	_update_timer_label()
	if _online:
		# The HUD only shows whole seconds, so only push when that changes.
		var sec := int(ceil(_time_left))
		if sec != _last_sent_sec:
			_last_sent_sec = sec
			_net_time.rpc(_time_left)
	if _time_left <= 0.0:
		_end_authoritative(false)

func _on_boat_completed() -> void:
	# Fires on every peer (submit runs everywhere), but only the host may call it.
	if _online and not _is_host:
		return
	_end_authoritative(true)

## Host (or offline) settles the outcome; online it fans out to every peer. As estrelas
## saem daqui junto com o resultado: quem tem a verdade do mundo é quem conta.
func _end_authoritative(won: bool) -> void:
	if _over:
		return
	var stars := _count_stars(won)
	if _online:
		_net_end.rpc(won, stars)
	else:
		_end(won, stars)

## 3 se escapou com o baú a bordo, 2 se escapou sem ele, 0 na derrota (o tesouro não
## salva quem não terminou o barco).
func _count_stars(won: bool) -> int:
	if not won:
		return 0
	if _boat != null and bool(_boat.get("treasure_stowed")):
		return 3
	return 2

@rpc("authority", "unreliable_ordered")
func _net_time(t: float) -> void:
	_time_left = t
	_update_timer_label()

@rpc("authority", "call_local", "reliable")
func _net_end(won: bool, stars: int) -> void:
	_end(won, stars)

func _end(won: bool, stars: int) -> void:
	_over = true
	GameManager.set_state(GameManager.State.RESULT)
	for player in get_tree().get_nodes_in_group("players"):
		(player as Node).process_mode = Node.PROCESS_MODE_DISABLED
	result_title.text = "Vocês escaparam da ilha!" if won else "O tempo acabou... a ilha venceu."
	result_stars.visible = stars > 0
	result_stars.text = STAR_GLYPHS.get(stars, "")
	# Online: return everyone to the lobby (host-driven); clients just wait.
	if _online:
		replay_button.text = "Voltar ao lobby" if _is_host else "Aguardando o host..."
		replay_button.disabled = not _is_host
	result_panel.visible = true
	if replay_button.disabled:
		menu_button.grab_focus()
	else:
		replay_button.grab_focus()

func _update_timer_label() -> void:
	var total := int(ceil(_time_left))
	@warning_ignore("integer_division")
	timer_label.text = "Tempo  %02d:%02d" % [total / 60, total % 60]
	if _time_left <= low_time_warning:
		timer_label.modulate = Color(1.0, 0.4, 0.35)
	else:
		timer_label.modulate = Color(1.0, 1.0, 1.0)

## Bridge the gamepad's A to the focused result button (default ui_accept isn't
## firing on the pad here), only while the result screen is up.
func _input(event: InputEvent) -> void:
	if not result_panel.visible:
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is BaseButton:
			get_viewport().set_input_as_handled()
			(focused as BaseButton).pressed.emit()

func _on_replay() -> void:
	if _online:
		NetworkManager.return_to_lobby() # keep the session; back to the online lobby
	else:
		GameManager.go_to_lobby()

func _on_menu() -> void:
	if _online:
		NetworkManager.leave()
	GameManager.go_to_main_menu()
