#[compute]
#version 450

// Depth-based silhouette outline, run as a Godot 4 CompositorEffect (POST_TRANSPARENT),
// so it composes correctly over transparent surfaces (the toon water) unlike a
// fullscreen screen-reading quad.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float thickness;
	float depth_threshold;
	float near;
	float far;
	float pad0;
	float pad1;
	vec4 outline_color;
} params;

// Godot 4 uses reversed-Z (ndc = 1 at near, 0 at far). Return positive view distance.
float linearize(float ndc) {
	return params.near * params.far / ((params.far - params.near) * ndc + params.near);
}

void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 isize = ivec2(params.raster_size);
	if (coord.x >= isize.x || coord.y >= isize.y) {
		return;
	}

	vec2 texel = 1.0 / params.raster_size;
	vec2 uv = (vec2(coord) + 0.5) * texel;
	float t = params.thickness;

	float dc = linearize(texture(depth_tex, uv).r);
	float dl = linearize(texture(depth_tex, uv + vec2(-texel.x * t, 0.0)).r);
	float dr = linearize(texture(depth_tex, uv + vec2(texel.x * t, 0.0)).r);
	float dd = linearize(texture(depth_tex, uv + vec2(0.0, -texel.y * t)).r);
	float du = linearize(texture(depth_tex, uv + vec2(0.0, texel.y * t)).r);

	float edge = abs(dc - dl) + abs(dc - dr) + abs(dc - dd) + abs(dc - du);
	float outline = smoothstep(params.depth_threshold, params.depth_threshold * 2.0, edge);

	vec4 color = imageLoad(color_image, coord);
	color.rgb = mix(color.rgb, params.outline_color.rgb, outline * params.outline_color.a);
	imageStore(color_image, coord, color);
}
