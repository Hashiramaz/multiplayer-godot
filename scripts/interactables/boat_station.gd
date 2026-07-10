extends Area3D
## The boat under construction -- Escape-the-Island's central objective. It only
## accepts finished "plank"s (see sawmill.gd); each one reveals a plank on the hull
## and updates the label, until the boat is complete.

signal completed

@export var required: int = 4

var delivered: int = 0

@onready var _planks: Array[Node] = $Planks.get_children()
@onready var _label: Label3D = $Progress

func _ready() -> void:
	add_to_group("station")
	for plank in _planks:
		(plank as Node3D).visible = false
	_update_label()

func can_deliver() -> bool:
	return delivered < required

func accepts(item_kind: String) -> bool:
	return item_kind == "plank" and can_deliver()

## Consumes a plank and advances construction. Returns true if it was accepted.
func submit(item: Node3D) -> bool:
	if not can_deliver():
		return false
	if delivered < _planks.size():
		(_planks[delivered] as Node3D).visible = true
	delivered += 1
	item.queue_free()
	_update_label()
	if delivered >= required:
		_on_complete()
	return true

func _on_complete() -> void:
	_label.text = "BARCO PRONTO!"
	completed.emit()
	print("[BoatStation] Barco pronto -- vocês podem escapar da ilha!")

func _update_label() -> void:
	if delivered < required:
		_label.text = "Barco  %d/%d" % [delivered, required]
