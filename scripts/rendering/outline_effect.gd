@tool
class_name OutlineEffect
extends CompositorEffect
## Screen-space silhouette outline as a Godot 4 CompositorEffect. It runs
## POST_TRANSPARENT -- after the water and other transparents are drawn -- so it
## composes correctly with transparency, unlike a fullscreen quad that reads
## SCREEN_TEXTURE (which only sees the opaque pass and hid the water).
##
## Advanced / low-level: it dispatches a compute shader over the color + depth
## buffers via the RenderingDevice.

@export var outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var thickness: float = 1.2
@export var depth_threshold: float = 0.35

@export_group("Camera depth range")
@export var near: float = 0.05
@export var far: float = 4000.0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_initialize)

func _initialize() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var shader_file: RDShaderFile = load("res://Assets/Shaders/outline_compute.glsl")
	if shader_file == null:
		return
	var spirv := shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		if _sampler.is_valid():
			_rd.free_rid(_sampler)
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var x_groups := ceili(size.x / 8.0)
	var y_groups := ceili(size.y / 8.0)

	var push := PackedFloat32Array([
		float(size.x), float(size.y), thickness, depth_threshold,
		near, far, 0.0, 0.0,
		outline_color.r, outline_color.g, outline_color.b, outline_color.a
	]).to_byte_array()

	for view in range(buffers.get_view_count()):
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)

		var u_color := RDUniform.new()
		u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_color.binding = 0
		u_color.add_id(color)

		var u_depth := RDUniform.new()
		u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_depth.binding = 1
		u_depth.add_id(_sampler)
		u_depth.add_id(depth)

		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [u_color, u_depth])

		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, x_groups, y_groups, 1)
		_rd.compute_list_end()
