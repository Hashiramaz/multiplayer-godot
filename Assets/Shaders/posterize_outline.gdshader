shader_type spatial;
// depth_draw_never: the fullscreen quad must NOT write depth, otherwise it
// occludes transparent objects drawn afterwards (Label3D text disappeared).
render_mode unshaded, depth_draw_never;

uniform sampler2D DEPTH_TEXTURE : source_color, hint_depth_texture, filter_linear_mipmap;
uniform sampler2D NORMAL_TEXTURE : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : source_color, hint_screen_texture, repeat_disable, filter_nearest;

uniform float zNear = 0.05;
uniform float zFar = 100;

uniform bool enable_outline = false;
uniform vec3 outline_color : source_color = vec3(0.0,0.0,0.0);
uniform float outline_thickness = 10.0;

uniform bool enable_color_limit = true;
uniform int color_levels : hint_range(2, 32) = 8;

uniform bool enable_color_palette = true;
uniform vec4 color1  : source_color  = vec4(1.0,0.925,0.839,1.0);
uniform vec4 color2  : source_color  = vec4(1.0,0.831,0.639,1.0);
uniform vec4 color3  : source_color  = vec4(1.0,0.667,0.369,1.0);
uniform vec4 color4  : source_color  = vec4(0.816,0.506,0.349,1.0);
uniform vec4 color5  : source_color  = vec4(0.553,0.412,0.478,1.0);
uniform vec4 color6  : source_color  = vec4(0.329,0.306,0.408,1.0);
uniform vec4 color7  : source_color  = vec4(0.125,0.236,0.337,1.0);
uniform vec4 color8  : source_color  = vec4(0.05,0.169,0.271,1.0);

uniform bool enable_dithering = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.3;

const mat3 Gx = mat3(
				vec3(-1,-2,-1),
				vec3(0, 0, 0),
				vec3(1, 2, 1)
);
const mat3 Gy = mat3(
				vec3(-1,0,1),
				vec3(-2,0,2),
				vec3(-1,0,1)
);

float depth(sampler2D depth_texture, vec2 screen_uv, mat4 inv_proj_mat, in vec3 vertex)
{
	float depth_raw = texture(depth_texture, screen_uv)[0];
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth_raw);
	vec4 view_space = inv_proj_mat * vec4(ndc,1.0);
	view_space.z /= view_space.w;
	float linear_depth = view_space.z;
	float scaled_depth = (zFar-zNear)/(zNear + linear_depth * (zNear-zFar));

	return scaled_depth;
}

float sobel_depth(in vec2 uv, in vec2 offset, in vec3 vertex, mat4 inv_proj_mat)
{
	float xSobDepth = 0.0;
	float ySobDepth = 0.0;

	for (int row = 0; row < 3; row++)
	{
		for (int col = 0; col < 3; col++)
		{
			float depth = depth(DEPTH_TEXTURE, uv + offset * vec2(float(col-1),float(row-1)),inv_proj_mat,vertex);
			xSobDepth += Gx[row][col] * depth;
			ySobDepth += Gy[row][col] * depth;
		}
	}

	return sqrt(pow(xSobDepth,2.0) + pow(ySobDepth,2.0));
}

float luminance(vec3 color)
{
	const vec3 weight = vec3(0.2125, 0.7154, 0.0721);
	return dot(weight,color);
}

float sobel_normal(in vec2 uv, in vec2 offset)
{
	float xSobNormal = 0.0;
	float ySobNormal = 0.0;

	for (int row = 0; row < 3; row++)
	{
		for (int col = 0; col < 3; col++)
		{
			float lumi = luminance(texture(NORMAL_TEXTURE, uv + offset * vec2(float(col-1),float(row-1))).rgb);
			xSobNormal += Gx[row][col] * lumi;
			ySobNormal += Gy[row][col] * lumi;
		}
	}

	return sqrt(pow(xSobNormal,2.0) + pow(ySobNormal,2.0));
}

float posterize(float val, int levels)
{
	return round(val * float(levels)) / float(levels);
}

float dither(vec2 position, float brightness)
{
	int x = int(mod(position.x, 4.0));
	int y = int(mod(position.y, 4.0));
	int index = x + y * 4;

	float dithering[16] = float[](
		0.0,0.5,0.125,0.625,
		0.75,0.25,0.875,0.375,
		0.1875,0.6875,0.0625,0.5625,
		0.9375,0.4375,1.0,0.8125
	);
	float threshold = dithering[index];
	return brightness < threshold ? 0.0 : 1.0;
}

void vertex() {
	POSITION = vec4(VERTEX.xy,1.0,1.0);
}

void fragment() {
	vec3 palette[8];
		palette[0] = color1.rgb;
		palette[1] = color2.rgb;
		palette[2] = color3.rgb;
		palette[3] = color4.rgb;
		palette[4] = color5.rgb;
		palette[5] = color6.rgb;
		palette[6] = color7.rgb;
		palette[7] = color8.rgb;

	vec3 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	vec3 final_color = screen_color;

	if(enable_color_limit)
	{
		final_color = vec3(posterize(final_color.r,color_levels),posterize(final_color.g,color_levels),posterize(final_color.b,color_levels));

	}

	if (enable_color_palette)
	{
		vec3 difference = final_color - palette[0];
		float dist = dot(difference,difference);

		float closest_distance = dist;
		vec3 closest_color = palette[0];

		for( int i = 0; i < palette.length(); i++)
		{
			difference = final_color - palette[i];
			dist = dot(difference,difference);

			if(dist<closest_distance)
			{
				closest_distance = dist;
				closest_color = palette[i];
			}
		}
		final_color = closest_color;
	}

	if(enable_dithering)
	{
		float brightness = dot(final_color, vec3(0.3,0.59,0.11));
		brightness += dither_strength * (dither(FRAGCOORD.xy, brightness) -0.5);
		final_color *= (1.0 + dither_strength * (dither(FRAGCOORD.xy, brightness) -0.5));
	}

	if(enable_outline)
	{
		vec2 offset = outline_thickness / VIEWPORT_SIZE;
		vec2 uv = SCREEN_UV;

		float depth = depth(DEPTH_TEXTURE, uv, INV_PROJECTION_MATRIX,VERTEX);

		vec3 pixel_color = texture(SCREEN_TEXTURE, uv).rgb;

		float edge_depth = sobel_depth(uv, offset, VERTEX, INV_PROJECTION_MATRIX);
		float edge_normal = sobel_normal(uv, offset);

		float outline = smoothstep(0.0,1.0,10.0 * edge_depth + edge_normal);

		final_color = mix(final_color, outline_color, outline);
	}

	ALBEDO = final_color;
}

void light() {
}
