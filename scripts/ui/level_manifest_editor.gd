extends Control
## Dev-only screen: curate which levels ship in the build and in what order.
## Checkbox toggles inclusion; Subir/Descer reorders. Save writes the manifest to
## res://levels/manifest.tres (only works running from the editor -- res:// is
## read-only in a build). Commit that file for the build to pick it up.

@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var status: Label = $VBox/Status
@onready var save_button: Button = $VBox/Buttons/Save
@onready var back_button: Button = $VBox/Buttons/Back

var _rows: Array = [] # working copy: [{ name, path, enabled }]

func _ready() -> void:
	GameManager.set_state(GameManager.State.EDITOR)
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(GameManager.go_to_main_menu)
	_rows = LevelData.manifest_entries()
	_rebuild()

func _rebuild() -> void:
	for c in list.get_children():
		c.queue_free()
	for i in _rows.size():
		list.add_child(_make_row(i))

func _make_row(i: int) -> Control:
	var r: Dictionary = _rows[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var chk := CheckBox.new()
	chk.button_pressed = bool(r["enabled"])
	chk.toggled.connect(_on_toggle.bind(i))
	row.add_child(chk)

	var name_label := Label.new()
	var suffix := "  (embutida)" if str(r["path"]) == "" else ""
	name_label.text = str(r["name"]) + suffix
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 20)
	row.add_child(name_label)

	var up := Button.new()
	up.text = "Subir"
	up.disabled = i == 0
	up.pressed.connect(_move.bind(i, -1))
	row.add_child(up)

	var down := Button.new()
	down.text = "Descer"
	down.disabled = i == _rows.size() - 1
	down.pressed.connect(_move.bind(i, 1))
	row.add_child(down)
	return row

func _on_toggle(pressed: bool, i: int) -> void:
	_rows[i]["enabled"] = pressed

func _move(i: int, dir: int) -> void:
	var j := i + dir
	if j < 0 or j >= _rows.size():
		return
	var tmp: Dictionary = _rows[i]
	_rows[i] = _rows[j]
	_rows[j] = tmp
	_rebuild()

func _on_save() -> void:
	var order := PackedStringArray()
	var disabled := PackedStringArray()
	for r in _rows:
		var p := str(r["path"])
		order.append(p)
		if not bool(r["enabled"]):
			disabled.append(p)
	var m := LevelManifest.new()
	m.order = order
	m.disabled = disabled
	var err := m.save()
	if err == OK:
		status.text = "Salvo! %d fase(s) na build." % (order.size() - disabled.size())
	else:
		status.text = "Erro ao salvar (%d) — só funciona rodando do editor." % err
