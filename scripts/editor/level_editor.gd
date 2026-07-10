extends Node3D
## In-game level editor (mouse + keyboard, desktop-tool style). Edits a LevelData in
## memory: sculpt the terrain heightmap with a brush, then Save it to res://levels so
## it shows up in the level-select screen. Object placement and the level-properties
## panel land in later phases; the tool-mode switch is already here to host them.
##
## Camera: right-drag orbit, middle-drag pan, wheel zoom (see editor_camera.gd).
## Terrain brush: hold LEFT mouse over the terrain and drag.

const LEVELS_DIR := "res://levels"

var _level: LevelData
var _tool_mode: String = "terrain"      # terrain | objects | properties

var _brush_mode: String = "raise"       # raise | lower | smooth | flatten
var _brush_radius: float = 4.0
var _brush_strength: float = 1.0
var _painting: bool = false

@onready var _terrain: Node = $Island/Terrain
@onready var _camera: Camera3D = $EditorCamera
@onready var _objects: Node3D = $Objects
@onready var _ui: CanvasLayer = $UI

var _brush_decal: Decal

var _name_edit: LineEdit
var _hint: Label
var _terrain_panel: Control
var _placeholder: Label
var _open_dialog: FileDialog

func _ready() -> void:
	GameManager.set_state(GameManager.State.EDITOR)
	_level = LevelData.make_default_island()
	_build_brush_decal()
	_build_ui()
	_load_into_scene()

## The projected brush ring: a Decal (conforms to the terrain silhouette on its own)
## with a procedurally-drawn annulus texture. Inspired by the "telegraph decals"
## look -- a ground marking that bends over hills to show reach.
func _build_brush_decal() -> void:
	_brush_decal = Decal.new()
	_brush_decal.texture_albedo = _make_ring_texture()
	_brush_decal.albedo_mix = 1.0
	_brush_decal.upper_fade = 0.05
	_brush_decal.lower_fade = 0.05
	_brush_decal.visible = false
	add_child(_brush_decal)

## Draws a soft annulus (bright outline at RING_POS + faint inner fill) as a white
## RGBA texture; the ring color comes from the Decal's modulate at runtime.
func _make_ring_texture() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var center := Vector2(s, s) * 0.5
	var max_r := float(s) * 0.5
	for y in s:
		for x in s:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center) / max_r
			var outline := 1.0 - smoothstep(0.0, 0.05, absf(d - RING_POS))
			var fill := (1.0 - smoothstep(RING_POS - 0.06, RING_POS, d)) * 0.14
			var a := clampf(outline + fill, 0.0, 1.0)
			if d > 1.0:
				a = 0.0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

# --- Level <-> scene ------------------------------------------------------------

func _load_into_scene() -> void:
	_terrain.build_from(_level)
	_rebuild_objects()
	_name_edit.text = _level.level_name
	_set_hint("Fase carregada: %s" % _level.level_name)

## Static, non-interactive previews of the placed objects so the terrain isn't empty
## while editing. (Full placement/selection comes in the next phase.)
func _rebuild_objects() -> void:
	for child in _objects.get_children():
		child.queue_free()
	for o in _level.objects:
		var def := LevelCatalog.get_def(o.type_id)
		if def == null or def.scene == null:
			continue
		var node := def.scene.instantiate()
		(node as Node3D).transform = o.transform
		for key in o.props:
			node.set(key, o.props[key])
		_objects.add_child(node)
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED

# --- Terrain brush --------------------------------------------------------------
## Where on the ring texture the visible outline sits (0 = center, 1 = edge). The
## decal box is sized so this outline lands exactly at the real sculpt radius.
const RING_POS := 0.9

var _brush_hit: bool = false
var _brush_point: Vector3 = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if _tool_mode != "terrain":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed

func _process(delta: float) -> void:
	# Guard against a release swallowed by the UI leaving us stuck painting.
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_painting = false
	if _tool_mode != "terrain":
		_brush_decal.visible = false
		return
	_raycast_brush()
	_update_brush_decal()
	if _painting and _brush_hit:
		_terrain.sculpt(_brush_point, _brush_radius, _brush_strength * delta, _brush_mode)

func _raycast_brush() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var hit: Dictionary = _terrain.raycast(origin, dir)
	_brush_hit = hit.get("hit", false)
	if _brush_hit:
		_brush_point = hit["position"]

## Positions and styles the projected brush ring: radius -> decal footprint,
## strength -> ring opacity/brightness, brush mode -> hue. Follows the cursor even
## when not painting so you can aim.
func _update_brush_decal() -> void:
	_brush_decal.visible = _brush_hit
	if not _brush_hit:
		return
	var half := _brush_radius / RING_POS
	_brush_decal.size = Vector3(half * 2.0, 40.0, half * 2.0)
	_brush_decal.global_position = _brush_point + Vector3.UP * 8.0
	var base := _mode_color(_brush_mode)
	var t := clampf((_brush_strength - 0.1) / 3.9, 0.0, 1.0)
	var bright := lerpf(0.6, 1.15, t)
	_brush_decal.modulate = Color(
		minf(base.r * bright, 1.0),
		minf(base.g * bright, 1.0),
		minf(base.b * bright, 1.0),
		lerpf(0.45, 1.0, t))

func _mode_color(mode: String) -> Color:
	match mode:
		"raise": return Color(0.35, 0.9, 0.4)   # green: building up
		"lower": return Color(0.95, 0.4, 0.35)  # red: digging down
		"smooth": return Color(0.4, 0.75, 1.0)  # blue
		"flatten": return Color(1.0, 0.85, 0.3) # yellow
	return Color.WHITE

# --- Actions --------------------------------------------------------------------

func _on_new() -> void:
	_level = LevelData.make_default_island()
	_level.level_name = "Nova Fase"
	_load_into_scene()

func _on_save() -> void:
	_level.level_name = _name_edit.text.strip_edges()
	if _level.level_name == "":
		_level.level_name = "Nova Fase"
	if not DirAccess.dir_exists_absolute(LEVELS_DIR):
		DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var path := "%s/%s.tres" % [LEVELS_DIR, _slugify(_level.level_name)]
	var err := ResourceSaver.save(_level, path)
	if err == OK:
		_set_hint("Salvo em %s" % path)
	else:
		_set_hint("Falha ao salvar (%d)" % err)

func _on_open_pressed() -> void:
	_open_dialog.popup_centered_ratio(0.6)

func _on_open_file(path: String) -> void:
	var res := load(path)
	if res is LevelData:
		_level = res as LevelData
		_load_into_scene()
	else:
		_set_hint("Arquivo não é uma fase válida")

func _on_test() -> void:
	_level.level_name = _name_edit.text.strip_edges()
	GameManager.selected_level = _level
	GameManager.start_match()

func _on_menu() -> void:
	GameManager.go_to_main_menu()

func _set_brush_mode(mode: String) -> void:
	_brush_mode = mode

func _set_brush_radius(v: float) -> void:
	_brush_radius = v

func _set_brush_strength(v: float) -> void:
	_brush_strength = v

func _set_tool_mode(mode: String) -> void:
	_tool_mode = mode
	_terrain_panel.visible = mode == "terrain"
	_placeholder.visible = mode != "terrain"
	if mode == "objects":
		_placeholder.text = "Objetos: em breve (Fase D)"
	elif mode == "properties":
		_placeholder.text = "Propriedades: em breve (Fase E)"

func _slugify(raw: String) -> String:
	var out := ""
	for c in raw.to_lower():
		if c.is_valid_int() or (c >= "a" and c <= "z"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	if out == "":
		out = "fase"
	return out

func _set_hint(text: String) -> void:
	_hint.text = text

# --- UI construction ------------------------------------------------------------

func _build_ui() -> void:
	_build_toolbar()
	_build_terrain_panel()
	_build_placeholder()
	_build_hint()
	_build_open_dialog()
	_set_tool_mode("terrain")

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 44
	_ui.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	_add_button(row, "Novo", _on_new)
	_add_button(row, "Abrir", _on_open_pressed)
	_add_button(row, "Salvar", _on_save)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(200, 0)
	_name_edit.placeholder_text = "Nome da fase"
	row.add_child(_name_edit)

	_add_separator(row)
	_add_button(row, "Terreno", _set_tool_mode.bind("terrain"))
	_add_button(row, "Objetos", _set_tool_mode.bind("objects"))
	_add_button(row, "Propriedades", _set_tool_mode.bind("properties"))
	_add_separator(row)
	_add_button(row, "Testar", _on_test)
	_add_button(row, "Menu", _on_menu)

func _build_terrain_panel() -> void:
	_terrain_panel = PanelContainer.new()
	_terrain_panel.position = Vector2(8, 52)
	_terrain_panel.custom_minimum_size = Vector2(220, 0)
	_ui.add_child(_terrain_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_terrain_panel.add_child(box)

	var title := Label.new()
	title.text = "Pincel de Terreno"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var modes := GridContainer.new()
	modes.columns = 2
	box.add_child(modes)
	_add_button(modes, "Subir", _set_brush_mode.bind("raise"))
	_add_button(modes, "Descer", _set_brush_mode.bind("lower"))
	_add_button(modes, "Suavizar", _set_brush_mode.bind("smooth"))
	_add_button(modes, "Nivelar", _set_brush_mode.bind("flatten"))

	box.add_child(_make_slider("Raio", 1.0, 12.0, 0.5, _brush_radius, _set_brush_radius))
	box.add_child(_make_slider("Força", 0.1, 4.0, 0.1, _brush_strength, _set_brush_strength))

	var help := Label.new()
	help.text = "Segure o botão esquerdo\ndo mouse sobre o terreno."
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)

func _build_placeholder() -> void:
	_placeholder = Label.new()
	_placeholder.position = Vector2(12, 56)
	_placeholder.add_theme_font_size_override("font_size", 16)
	_placeholder.visible = false
	_ui.add_child(_placeholder)

func _build_hint() -> void:
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -28
	_hint.offset_left = 8
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 14)
	_ui.add_child(_hint)

func _build_open_dialog() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_RESOURCES
	_open_dialog.filters = PackedStringArray(["*.tres ; Fases"])
	_open_dialog.current_dir = LEVELS_DIR
	_open_dialog.file_selected.connect(_on_open_file)
	_ui.add_child(_open_dialog)

# --- Small UI helpers -----------------------------------------------------------

func _add_button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

func _add_separator(parent: Node) -> void:
	var sep := VSeparator.new()
	parent.add_child(sep)

func _make_slider(label_text: String, min_v: float, max_v: float, step: float,
		value: float, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %.1f" % [label_text, value]
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.value_changed.connect(_on_slider_changed.bind(label, label_text, on_change))
	box.add_child(slider)
	return box

func _on_slider_changed(value: float, label: Label, label_text: String, on_change: Callable) -> void:
	label.text = "%s: %.1f" % [label_text, value]
	on_change.call(value)
