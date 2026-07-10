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

func _ready() -> void:
	add_to_group("station")
	_update_label()

func accepts(item_kind: String) -> bool:
	return item_kind == "log"

## Takes the log (consumes it) and queues a plank to be produced.
func submit(item: Node3D) -> bool:
	item.queue_free()
	_queue += 1
	_update_label()
	return true

func _process(delta: float) -> void:
	if _working:
		_timer -= delta
		if _timer <= 0.0:
			_finish_one()
		_update_label()
	elif _queue > 0:
		_start_one()

func _start_one() -> void:
	_queue -= 1
	_working = true
	_timer = process_time
	_update_label()

func _finish_one() -> void:
	_working = false
	if plank_scene != null:
		var plank := plank_scene.instantiate()
		get_tree().current_scene.add_child(plank)
		var jitter := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		plank.global_transform = Transform3D(Basis.IDENTITY, _output.global_position + jitter)
	_update_label()

func _update_label() -> void:
	if _working:
		_label.text = "Serrando...  (fila %d)" % _queue
	elif _queue > 0:
		_label.text = "Fila: %d" % _queue
	else:
		_label.text = "Serraria"
