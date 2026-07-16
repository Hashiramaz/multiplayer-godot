extends Node3D
## In-game level editor (mouse + keyboard, desktop-tool style). Edits a LevelData in
## memory across three tool modes:
##   - Terreno: sculpt the terrain heightmap with a brush.
##   - Objetos: place / move / rotate / delete gameplay & scenery objects and spawns.
##   - Propriedades: (Fase E) level-wide settings.
## Save writes a .tres to res://levels so it shows up in the level-select screen.
##
## The scene under $Objects is the working state while editing; it's synced back into
## the LevelData (objects + spawn_points) on Save / Test. Each item node carries meta
## ("kind"/"type_id"/"props") so the sync is a straight read of the tree.
##
## Camera: right-drag orbit, middle-drag pan, wheel zoom (see editor_camera.gd).

const LEVELS_DIR := "res://levels"
## Where on the ring texture the visible outline sits (0 = center, 1 = edge). Decal
## boxes are sized so this outline lands exactly at the intended world radius.
const RING_POS := 0.9
const MAX_SPAWNS := 4
const PICK_RADIUS := 2.5      # world XZ distance to select an object by clicking near it

var _level: LevelData
var _tool_mode: String = "terrain"      # terrain | objects | properties

# Terrain brush
var _brush_mode: String = "raise"       # raise | lower | smooth | flatten
var _brush_radius: float = 4.0
var _brush_strength: float = 1.0
var _painting: bool = false

# Shared cursor raycast (terrain point under the mouse)
var _cursor_hit: bool = false
var _cursor_point: Vector3 = Vector3.ZERO

# Object tool
var _armed_type: String = ""            # "" = select/move; else type_id or "spawn"
var _selected: Node3D = null
var _dragging_obj: bool = false
var _drag_offset: Vector3 = Vector3.ZERO  # selected.pos - cursor at grab, so it doesn't jump

# Grid snap (authoring aid for Overcooked-style layout/balancing). Editor-only state:
# it snaps X/Z to cell centers while Y keeps following the sculpted heightmap. Nothing
# here is written into LevelData -- placed objects still store a plain Transform3D.
var _snap_enabled: bool = false
var _grid_size: float = 2.0
var _grid_decal: Decal
var _grid_divisions: int = 0      # cached; the grid texture is rebuilt when this changes

@onready var _terrain: Node = $Island/Terrain
@onready var _camera: Camera3D = $EditorCamera
@onready var _objects: Node3D = $Objects
@onready var _ui: CanvasLayer = $UI

var _brush_decal: Decal
var _select_decal: Decal

# UI
var _name_edit: LineEdit
var _hint: Label
var _terrain_panel: Control
var _objects_panel: Control
var _inspector_box: VBoxContainer
var _properties_panel: Control
var _duration_spin: SpinBox
var _water_spin: SpinBox
var _grass_pick: ColorPickerButton
var _sand_pick: ColorPickerButton
var _seabed_pick: ColorPickerButton
var _open_dialog: FileDialog

func _ready() -> void:
	GameManager.set_state(GameManager.State.EDITOR)
	_level = LevelData.make_default_island()
	_build_decals()
	_build_ui()
	_load_into_scene()

# --- Level <-> scene ------------------------------------------------------------

func _load_into_scene() -> void:
	_terrain.build_from(_level)
	_rebuild_scene_items()
	_select(null)
	_refresh_properties()
	_name_edit.text = _level.level_name
	_set_hint("Fase carregada: %s" % _level.level_name)

## Rebuilds the working tree ($Objects) from the LevelData: one node per placed
## object (with meta for the sync) plus a marker per spawn point.
func _rebuild_scene_items() -> void:
	for child in _objects.get_children():
		child.queue_free()
	for o in _level.objects:
		_instantiate_object(o.type_id, o.transform, o.props)
	for i in _level.spawn_points.size():
		_instantiate_spawn(_level.spawn_points[i], i)

## Writes the working scene back into the LevelData. Called before Save / Test.
## The live terrain node is the source of truth for the (sculpted) heightmap -- it
## diverges from _level.heights via copy-on-write the moment you paint, so we must
## pull it back here or the save would keep the original flat island.
func _sync_level_from_scene() -> void:
	_level.heights = _terrain.heights
	_level.terrain_size = _terrain.size
	_level.terrain_resolution = _terrain.resolution
	_level.water_level = _terrain.water_level
	_level.grass_color = _terrain.grass_color
	_level.sand_color = _terrain.sand_color
	_level.seabed_color = _terrain.seabed_color

	var objs: Array[PlacedObject] = []
	var spawns: Array[Transform3D] = []
	for node in _objects.get_children():
		if String(node.get_meta("kind", "object")) == "spawn":
			spawns.append((node as Node3D).transform)
		else:
			var po := PlacedObject.new()
			po.type_id = String(node.get_meta("type_id", ""))
			po.transform = (node as Node3D).transform
			po.props = node.get_meta("props", {})
			objs.append(po)
	_level.objects = objs
	_level.spawn_points = spawns

func _instantiate_object(type_id: String, xform: Transform3D, props: Dictionary) -> Node3D:
	var def := LevelCatalog.get_def(type_id)
	if def == null or def.scene == null:
		push_warning("LevelEditor: unknown type_id '%s'" % type_id)
		return null
	var node := def.scene.instantiate() as Node3D
	node.transform = xform
	for key in props:
		node.set(key, props[key])
	node.set_meta("kind", "object")
	node.set_meta("type_id", type_id)
	node.set_meta("props", props.duplicate())
	_objects.add_child(node)
	node.process_mode = Node.PROCESS_MODE_DISABLED   # static preview: no timers / area logic
	return node

func _instantiate_spawn(xform: Transform3D, index: int) -> Node3D:
	var marker := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 0.2
	marker.mesh = cyl
	var col := PlayerManager.color_for_slot(index)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.5
	marker.material_override = mat
	marker.transform = xform
	marker.set_meta("kind", "spawn")
	_objects.add_child(marker)
	return marker

# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	match _tool_mode:
		"terrain":
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				_painting = event.pressed
		"objects":
			_objects_input(event)

func _objects_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_raycast_cursor()
			if not _cursor_hit:
				return
			if _armed_type != "":
				_place_new(_armed_type, _snap_xz(_cursor_point))
			else:
				var picked := _pick_object(_cursor_point)
				_select(picked)
				_dragging_obj = picked != null
				if picked != null:
					_drag_offset = picked.position - _cursor_point
		else:
			if _dragging_obj:
				_refresh_inspector()   # update the cell readout after a move
			_dragging_obj = false
	elif event is InputEventKey and event.pressed and not event.echo and _selected != null:
		match event.keycode:
			KEY_Q:
				_rotate_selected(-15.0)
			KEY_E:
				_rotate_selected(15.0)
			KEY_DELETE:
				_delete_selected()

func _process(delta: float) -> void:
	# Guard against a release swallowed by the UI leaving us stuck.
	if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_painting = false
	match _tool_mode:
		"terrain":
			_process_terrain(delta)
		"objects":
			_process_objects()
		_:
			_brush_decal.visible = false
			_select_decal.visible = false
			_grid_decal.visible = false

func _process_terrain(delta: float) -> void:
	_select_decal.visible = false
	_grid_decal.visible = false
	_raycast_cursor()
	_update_brush_decal()
	if _painting and _cursor_hit:
		_terrain.sculpt(_cursor_point, _brush_radius, _brush_strength * delta, _brush_mode)

func _process_objects() -> void:
	_raycast_cursor()
	_update_grid_decal()
	# Placement preview ring while a type is armed -- snapped so it shows the target cell.
	_brush_decal.visible = _cursor_hit and _armed_type != ""
	if _brush_decal.visible:
		var half := 1.2 / RING_POS
		_brush_decal.size = Vector3(half * 2.0, 40.0, half * 2.0)
		_brush_decal.global_position = _snap_xz(_cursor_point) + Vector3.UP * 8.0
		_brush_decal.modulate = Color(0.9, 0.95, 1.0, 0.85)
	# Drag the selected object along the terrain, re-seated on ground. With snap on we
	# drive straight from the (snapped) cursor cell; otherwise keep the grab offset so
	# free dragging doesn't jump.
	if _dragging_obj and _cursor_hit and _selected != null:
		var np := _snap_xz(_cursor_point) if _snap_enabled else _cursor_point + _drag_offset
		np.y = _terrain.height_at(np)
		_selected.position = np
	_update_select_decal()

## Quantize a world point's X/Z to grid cell centers, leaving Y untouched (callers
## re-seat it on the terrain). A no-op when snapping is off, so free placement still
## works exactly as before. Cell centers sit between the overlay's grid lines.
func _snap_xz(p: Vector3) -> Vector3:
	if not _snap_enabled:
		return p
	var gx := (floorf(p.x / _grid_size) + 0.5) * _grid_size
	var gz := (floorf(p.z / _grid_size) + 0.5) * _grid_size
	return Vector3(gx, p.y, gz)

func _raycast_cursor() -> void:
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	var hit: Dictionary = _terrain.raycast(origin, dir)
	_cursor_hit = hit.get("hit", false)
	if _cursor_hit:
		_cursor_point = hit["position"]

# --- Object placement / selection -----------------------------------------------

func _place_new(type_id: String, point: Vector3) -> void:
	point.y = _terrain.height_at(point)   # re-seat on the surface at the (snapped) X/Z
	if type_id == "spawn":
		if _count_spawns() >= MAX_SPAWNS:
			_set_hint("Máximo de %d spawns" % MAX_SPAWNS)
			return
		var marker := _instantiate_spawn(Transform3D(Basis.IDENTITY, point), _count_spawns())
		_select(marker)
		return
	var def := LevelCatalog.get_def(type_id)
	if def == null:
		return
	var node := _instantiate_object(type_id, Transform3D(Basis.IDENTITY, point), _default_props(def))
	_select(node)

## Nearest object/spawn to a world point within PICK_RADIUS (XZ), or null.
func _pick_object(point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_RADIUS
	for child in _objects.get_children():
		var n := child as Node3D
		var d := Vector2(n.position.x - point.x, n.position.z - point.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best

func _select(node: Node3D) -> void:
	_selected = node
	_refresh_inspector()

func _rotate_selected(deg: float) -> void:
	if _selected != null:
		_selected.rotate_y(deg_to_rad(deg))

func _delete_selected() -> void:
	if _selected == null:
		return
	_selected.queue_free()
	_selected = null
	_refresh_inspector()

func _count_spawns() -> int:
	var n := 0
	for child in _objects.get_children():
		if String(child.get_meta("kind", "object")) == "spawn":
			n += 1
	return n

func _default_props(def: ObjectDef) -> Dictionary:
	var d := {}
	for p in def.editable_props:
		d[p["name"]] = p["default"]
	return d

func _toggle_snap(on: bool) -> void:
	_snap_enabled = on
	_set_hint("Grade %s" % ("ligada" if on else "desligada"))

func _set_grid_size(v: float) -> void:
	_grid_size = v
	_grid_divisions = 0   # force the overlay texture to rebuild at the new cell count

func _arm(type_id: String) -> void:
	_armed_type = type_id
	if type_id == "":
		_set_hint("Modo seleção: clique para selecionar, arraste para mover")
	elif type_id == "spawn":
		_set_hint("Colocando spawns (clique no terreno)")
	else:
		var def := LevelCatalog.get_def(type_id)
		_set_hint("Colocando: %s" % (def.display_name if def else type_id))

# --- Decals (brush ring + selection ring) ---------------------------------------

func _build_decals() -> void:
	var tex := _make_ring_texture()
	_brush_decal = _make_decal(tex)
	_select_decal = _make_decal(tex)
	# The grid overlay drapes over the terrain (decals project straight down), so it
	# reads correctly even on a sculpted heightmap. Rebuilt lazily in _update_grid_decal.
	_grid_decal = _make_decal(_make_ring_texture())
	_grid_decal.albedo_mix = 0.9

func _make_decal(tex: ImageTexture) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.albedo_mix = 1.0
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.visible = false
	add_child(d)
	return d

func _update_brush_decal() -> void:
	_brush_decal.visible = _cursor_hit
	if not _cursor_hit:
		return
	var half := _brush_radius / RING_POS
	_brush_decal.size = Vector3(half * 2.0, 40.0, half * 2.0)
	_brush_decal.global_position = _cursor_point + Vector3.UP * 8.0
	var base := _mode_color(_brush_mode)
	var t := clampf((_brush_strength - 0.1) / 3.9, 0.0, 1.0)
	var bright := lerpf(0.6, 1.15, t)
	_brush_decal.modulate = Color(
		minf(base.r * bright, 1.0),
		minf(base.g * bright, 1.0),
		minf(base.b * bright, 1.0),
		lerpf(0.45, 1.0, t))

func _update_grid_decal() -> void:
	_grid_decal.visible = _snap_enabled
	if not _snap_enabled:
		return
	var terrain_size: float = _terrain.size
	var divisions: int = maxi(1, int(round(terrain_size / _grid_size)))
	if divisions != _grid_divisions:
		_grid_divisions = divisions
		_grid_decal.texture_albedo = _make_grid_texture(divisions)
	_grid_decal.size = Vector3(terrain_size, 40.0, terrain_size)
	_grid_decal.global_position = Vector3(0.0, 8.0, 0.0)   # centered over the terrain
	_grid_decal.modulate = Color(0.6, 0.85, 1.0, 0.5)

## A square grid of thin lines (transparent cells) that the overlay decal projects onto
## the terrain. `divisions` = terrain_size / grid_size, so the lines land on world
## multiples of grid_size and objects snap to the cell centers between them.
func _make_grid_texture(divisions: int) -> ImageTexture:
	var s := 512
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var line := Color(1.0, 1.0, 1.0, 1.0)
	for i in range(divisions + 1):
		var c := clampi(int(round(float(i) / float(divisions) * float(s - 1))), 0, s - 1)
		for t in range(s):
			img.set_pixel(c, t, line)   # vertical grid line
			img.set_pixel(t, c, line)   # horizontal grid line
	return ImageTexture.create_from_image(img)

func _update_select_decal() -> void:
	if _selected == null:
		_select_decal.visible = false
		return
	_select_decal.visible = true
	_select_decal.size = Vector3(3.0, 40.0, 3.0)
	_select_decal.global_position = _selected.global_position + Vector3.UP * 8.0
	_select_decal.modulate = Color(1.0, 1.0, 1.0, 0.9)

func _mode_color(mode: String) -> Color:
	match mode:
		"raise": return Color(0.35, 0.9, 0.4)   # green: building up
		"lower": return Color(0.95, 0.4, 0.35)  # red: digging down
		"smooth": return Color(0.4, 0.75, 1.0)  # blue
		"flatten": return Color(1.0, 0.85, 0.3) # yellow
	return Color.WHITE

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

# --- Toolbar actions ------------------------------------------------------------

func _on_new() -> void:
	_level = LevelData.make_default_island()
	_level.level_name = "Nova Fase"
	_armed_type = ""
	_load_into_scene()

func _on_save() -> void:
	_sync_level_from_scene()
	var problem := _validate()
	if problem != "":
		_set_hint("Não salvo: %s" % problem)
		return
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

## Returns "" if the level is playable, else a short reason. A level needs somewhere
## to spawn players and a boat to complete (the win condition).
func _validate() -> String:
	if _level.spawn_points.is_empty():
		return "adicione ao menos 1 ponto de spawn"
	var has_boat := false
	for o in _level.objects:
		if o.type_id == "boat":
			has_boat = true
			break
	if not has_boat:
		return "adicione um barco (objetivo)"
	return ""

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
	_sync_level_from_scene()
	var problem := _validate()
	if problem != "":
		_set_hint("Não dá pra testar: %s" % problem)
		return
	_level.level_name = _name_edit.text.strip_edges()
	GameManager.selected_level = _level
	GameManager.start_match()

func _on_menu() -> void:
	GameManager.go_to_main_menu()

func _set_tool_mode(mode: String) -> void:
	_tool_mode = mode
	_terrain_panel.visible = mode == "terrain"
	_objects_panel.visible = mode == "objects"
	_properties_panel.visible = mode == "properties"
	if mode == "objects":
		_refresh_inspector()

func _set_brush_mode(mode: String) -> void:
	_brush_mode = mode

func _set_brush_radius(v: float) -> void:
	_brush_radius = v

func _set_brush_strength(v: float) -> void:
	_brush_strength = v

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
	_build_objects_panel()
	_build_properties_panel()
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

func _build_objects_panel() -> void:
	_objects_panel = PanelContainer.new()
	_objects_panel.position = Vector2(8, 52)
	_objects_panel.custom_minimum_size = Vector2(230, 0)
	_ui.add_child(_objects_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_objects_panel.add_child(box)

	var title := Label.new()
	title.text = "Objetos"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	_add_button(box, "↖ Selecionar / Mover", _arm.bind(""))

	_add_section_label(box, "Grade")
	var snap_toggle := CheckButton.new()
	snap_toggle.text = "Encaixar na grade"
	snap_toggle.button_pressed = _snap_enabled
	snap_toggle.toggled.connect(_toggle_snap)
	box.add_child(snap_toggle)
	box.add_child(_make_slider("Célula", 0.5, 4.0, 0.5, _grid_size, _set_grid_size))

	_add_section_label(box, "Gameplay")
	for def in LevelCatalog.defs("gameplay"):
		_add_button(box, "+ %s" % def.display_name, _arm.bind(def.id))
	_add_button(box, "+ Ponto de Spawn", _arm.bind("spawn"))

	_add_section_label(box, "Cenário")
	for def in LevelCatalog.defs("scenery"):
		_add_button(box, "+ %s" % def.display_name, _arm.bind(def.id))

	var help := Label.new()
	help.text = "Clique: coloca/seleciona\nArraste: move  ·  Q/E: girar\nDel: apagar"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)

	_add_separator_h(box)
	_add_section_label(box, "Seleção")
	_inspector_box = VBoxContainer.new()
	_inspector_box.add_theme_constant_override("separation", 4)
	box.add_child(_inspector_box)

func _refresh_inspector() -> void:
	if _inspector_box == null:
		return
	for child in _inspector_box.get_children():
		child.queue_free()
	if _selected == null:
		var none := Label.new()
		none.text = "(nada selecionado)"
		none.modulate = Color(1, 1, 1, 0.6)
		_inspector_box.add_child(none)
		return

	var kind := String(_selected.get_meta("kind", "object"))
	if kind == "spawn":
		var l := Label.new()
		l.text = "Ponto de spawn"
		_inspector_box.add_child(l)
		_add_cell_label(_inspector_box)
		_add_button(_inspector_box, "Apagar (Del)", _delete_selected)
		return

	var type_id := String(_selected.get_meta("type_id", ""))
	var def := LevelCatalog.get_def(type_id)
	var title := Label.new()
	title.text = def.display_name if def else type_id
	_inspector_box.add_child(title)
	_add_cell_label(_inspector_box)

	var props: Dictionary = _selected.get_meta("props", {})
	if def != null:
		for p in def.editable_props:
			_add_prop_field(_inspector_box, p, props)
	_add_button(_inspector_box, "Apagar (Del)", _delete_selected)

## Grid cell of the selected item (floor of position / grid_size), for spacing/balance
## reference. Shown even with snap off so you can read where a free-placed object sits.
func _add_cell_label(parent: Node) -> void:
	if _selected == null:
		return
	var cx := floori(_selected.position.x / _grid_size)
	var cz := floori(_selected.position.z / _grid_size)
	var l := Label.new()
	l.text = "Célula: (%d, %d)" % [cx, cz]
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(0.7, 0.85, 1.0)
	parent.add_child(l)

func _add_prop_field(parent: Node, prop: Dictionary, props: Dictionary) -> void:
	var pname := String(prop["name"])
	var ptype := String(prop["type"])
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = pname
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	if ptype == "bool":
		var cb := CheckBox.new()
		cb.button_pressed = bool(props.get(pname, prop["default"]))
		cb.toggled.connect(_on_prop_bool.bind(pname))
		row.add_child(cb)
	else:
		var sb := SpinBox.new()
		sb.step = 1.0 if ptype == "int" else 0.1
		sb.min_value = 0.0
		sb.max_value = 999.0
		sb.value = float(props.get(pname, prop["default"]))
		sb.value_changed.connect(_on_prop_num.bind(pname, ptype))
		row.add_child(sb)
	parent.add_child(row)

func _on_prop_num(value: float, pname: String, ptype: String) -> void:
	if _selected == null:
		return
	var v: Variant = int(value) if ptype == "int" else value
	var props: Dictionary = _selected.get_meta("props", {})
	props[pname] = v
	_selected.set_meta("props", props)
	_selected.set(pname, v)

func _on_prop_bool(pressed: bool, pname: String) -> void:
	if _selected == null:
		return
	var props: Dictionary = _selected.get_meta("props", {})
	props[pname] = pressed
	_selected.set_meta("props", props)
	_selected.set(pname, pressed)

func _build_properties_panel() -> void:
	_properties_panel = PanelContainer.new()
	_properties_panel.position = Vector2(8, 52)
	_properties_panel.custom_minimum_size = Vector2(240, 0)
	_properties_panel.visible = false
	_ui.add_child(_properties_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_properties_panel.add_child(box)

	var title := Label.new()
	title.text = "Propriedades da Fase"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	_duration_spin = _make_spin(box, "Tempo (s)", 10.0, 999.0, 5.0, _level.match_duration, _on_duration_changed)
	_water_spin = _make_spin(box, "Nível da água", -5.0, 5.0, 0.1, _level.water_level, _on_water_changed)

	_add_section_label(box, "Cores do terreno")
	_grass_pick = _make_color(box, "Grama", _level.grass_color, _on_grass_changed)
	_sand_pick = _make_color(box, "Areia", _level.sand_color, _on_sand_changed)
	_seabed_pick = _make_color(box, "Fundo", _level.seabed_color, _on_seabed_changed)

	var note := Label.new()
	note.text = "Nome: na barra de cima.\nObjetivo (barco): no inspector\ndo objeto barco."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)

func _on_duration_changed(v: float) -> void:
	_level.match_duration = v

func _on_water_changed(v: float) -> void:
	_level.water_level = v
	_apply_appearance()

func _on_grass_changed(c: Color) -> void:
	_level.grass_color = c
	_apply_appearance()

func _on_sand_changed(c: Color) -> void:
	_level.sand_color = c
	_apply_appearance()

func _on_seabed_changed(c: Color) -> void:
	_level.seabed_color = c
	_apply_appearance()

## Restyles the terrain from _level's colors/water without disturbing the sculpt.
func _apply_appearance() -> void:
	_terrain.set_appearance(_level.grass_color, _level.sand_color, _level.seabed_color, _level.water_level)

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
	parent.add_child(VSeparator.new())

func _add_separator_h(parent: Node) -> void:
	parent.add_child(HSeparator.new())

func _add_section_label(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.7, 0.85, 1.0)
	parent.add_child(l)

func _make_spin(parent: Node, label_text: String, min_v: float, max_v: float,
		step: float, value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	parent.add_child(row)
	return spin

func _make_color(parent: Node, label_text: String, value: Color, on_change: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(80, 26)
	picker.color = value
	picker.edit_alpha = false
	picker.color_changed.connect(on_change)
	row.add_child(picker)
	parent.add_child(row)
	return picker

## Pushes the current _level's properties into the panel controls after a load,
## with signals blocked so it doesn't trigger appearance rebuilds.
func _refresh_properties() -> void:
	for c in [_duration_spin, _water_spin, _grass_pick, _sand_pick, _seabed_pick]:
		(c as Node).set_block_signals(true)
	_duration_spin.value = _level.match_duration
	_water_spin.value = _level.water_level
	_grass_pick.color = _level.grass_color
	_sand_pick.color = _level.sand_color
	_seabed_pick.color = _level.seabed_color
	for c in [_duration_spin, _water_spin, _grass_pick, _sand_pick, _seabed_pick]:
		(c as Node).set_block_signals(false)

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
