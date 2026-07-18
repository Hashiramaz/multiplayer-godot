extends Area3D
## Sawmill: the chaining step. Takes a raw "log", works on it for `process_time`,
## then pops out a "plank" at its output for someone to carry to the boat. Logs
## queue up if it's busy. This is what makes the resource loop cooperative -- one
## player can feed logs while another ferries planks.

@export var plank_scene: PackedScene
@export var process_time: float = 2.0

var _queue: int = 0
var _working: bool = false
var _timer: float = 0.0

@onready var _output: Node3D = $Output
@onready var _label: Label3D = $Label
@onready var _progress_bar: Node3D = $ProgressBar
@onready var _fill: Node3D = $ProgressBar/Fill

func _ready() -> void:
	add_to_group("station")
	_update_label()
	_update_bar()

func accepts(item_kind: String) -> bool:
	return item_kind == "log"

## Takes the log (consumes it) and queues a plank to be produced. Runs on every peer
## (via the deliver RPC), but only the host's queue actually drives production; the
## host's _net_push then corrects everyone's displayed count.
func submit(item: Node3D) -> bool:
	item.queue_free()
	_queue += 1
	_update_label()
	_net_push()
	return true

func _process(delta: float) -> void:
	# Online: only the host runs production. If every peer ticked its own timer they'd
	# drift, and each would spawn its OWN plank -- two planks, divergent worlds.
	# (Clients' label/bar therefore lag until O3b syncs the display.)
	if NetworkManager.is_online and not multiplayer.is_server():
		return
	if _working:
		_timer -= delta
		if _timer <= 0.0:
			_finish_one()
		_update_label()
		_update_bar()
		_net_push() # stream the moving bar to clients
	elif _queue > 0:
		_start_one()

func _start_one() -> void:
	_queue -= 1
	_working = true
	_timer = process_time
	_update_label()
	_update_bar()
	_net_push()

func _finish_one() -> void:
	_working = false
	if plank_scene != null:
		# randf_range would roll a different number on each machine, so online the host
		# picks the spot once and the Arena spawns the same plank everywhere.
		var jitter := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var pos := _output.global_position + jitter
		if NetworkManager.is_online:
			var arena := get_tree().current_scene
			if arena != null and arena.has_method("host_spawn_item"):
				arena.host_spawn_item(plank_scene.resource_path, pos)
		else:
			var plank := plank_scene.instantiate()
			get_tree().current_scene.add_child(plank)
			plank.global_transform = Transform3D(Basis.IDENTITY, pos)
	_update_label()
	_update_bar()
	_net_push()

# --- Networked display (O3b) ----------------------------------------------
# Only the host runs the timer, so clients would show a frozen label/bar. The host
# streams its display state; clients apply it verbatim (they never tick locally).

func _net_push() -> void:
	if NetworkManager.is_online and multiplayer.is_server():
		_net_apply_state.rpc(_working, _queue, _bar_progress())

## Keep a tiny minimum so the fill's transform never collapses to zero scale.
func _bar_progress() -> float:
	if _working and process_time > 0.0:
		return clampf(1.0 - _timer / process_time, 0.02, 1.0)
	return 0.02

@rpc("authority", "unreliable_ordered")
func _net_apply_state(working: bool, queue: int, progress: float) -> void:
	_working = working
	_queue = queue
	_update_label()
	_progress_bar.visible = working
	_fill.scale.x = progress

## Progress bar: visible only while working; the fill grows left-to-right 0 -> 1.
func _update_bar() -> void:
	_progress_bar.visible = _working
	_fill.scale.x = _bar_progress()

func _update_label() -> void:
	if _working:
		_label.text = "Serrando...  (fila %d)" % _queue
	elif _queue > 0:
		_label.text = "Fila: %d" % _queue
	else:
		_label.text = "Serraria"
