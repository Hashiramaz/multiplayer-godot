@tool
extends Node3D
## Shared setup for Kenney nature-kit scenery (palms, rocks, ...). Those FBX all
## sample a single `colormap.png` atlas through their UVs, but the material link is
## lost on import, so they render untextured. This walks the instanced model and:
##   - applies the colormap as albedo (restores the flat colors), and
##   - builds trimesh collision at runtime so players bump into them.
##
## @tool so the colors also show while previewing the scene in the Godot editor;
## collision is only generated at runtime (not needed in-editor).

const COLORMAP: Texture2D = preload("res://Assets/Visual/Environment/colormap.png")

@export var add_collision: bool = true

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = COLORMAP
	mat.roughness = 0.9
	_setup(self, mat)

func _setup(node: Node, mat: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat
			if add_collision and not Engine.is_editor_hint():
				(child as MeshInstance3D).create_trimesh_collision()
		_setup(child, mat)
