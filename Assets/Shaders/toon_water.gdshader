// Toon water, ported to Godot 4 from Erik Roystan Ross's Unity shader
// (https://roystan.net/articles/toon-water.html), original Godot 3 port on
// godotshaders.com. Godot 4 changes: DEPTH_TEXTURE declared as a uniform,
// hint_color -> source_color, depth reconstructed via INV_PROJECTION_MATRIX.
shader_type spatial;
render_mode cull_disabled;

const float SMOOTHSTEP_AA = 0.01;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D surfaceNoise : repeat_enable;
uniform sampler2D distortNoise : repeat_enable;

uniform float beer_factor = 1.5;

uniform float foam_max_distance = 0.4;
uniform float foam_min_distance = 0.04;
uniform vec4 foam_color : source_color = vec4(1.0);

uniform vec2 surface_noise_tiling = vec2(1.0, 4.0);
uniform vec3 surface_noise_scroll = vec3(0.03, 0.03, 0.0);
uniform float surface_noise_cutoff : hint_range(0.0, 1.0) = 0.777;
uniform float surface_distortion_amount : hint_range(0.0, 1.0) = 0.27;

uniform vec4 depth_gradient_shallow : source_color = vec4(0.325, 0.807, 0.971, 0.725);
uniform vec4 depth_gradient_deep : source_color = vec4(0.086, 0.407, 1.0, 0.749);
uniform float depth_max_distance : hint_range(0.0, 1.0) = 1.0;
uniform float depth_factor = 1.0;

varying vec2 noiseUV;
varying vec2 distortUV;
varying vec3 viewNormal;

vec4 alphaBlend(vec4 top, vec4 bottom) {
	vec3 color = (top.rgb * top.a) + (bottom.rgb * (1.0 - top.a));
	float alpha = top.a + bottom.a * (1.0 - top.a);
	return vec4(color, alpha);
}

void vertex() {
	viewNormal = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	noiseUV = UV * surface_noise_tiling;
	distortUV = UV;
}

void fragment() {
	// Reconstruct the opaque scene's view-space depth behind the water.
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	// Water column thickness (VERTEX.z is the water surface, both are negative).
	float depth = VERTEX.z - view.z;
	depth = 1.0 - exp(-depth * beer_factor);

	vec3 existingNormal = vec3(dFdx(depth), dFdy(depth), 0.0);
	float normalDot = clamp(dot(existingNormal, viewNormal), 0.0, 1.0);
	float foamDistance = mix(foam_max_distance, foam_min_distance, normalDot);

	float foamDepth = clamp(depth / foamDistance, 0.0, 1.0);
	float surfaceNoiseCutoff = foamDepth * surface_noise_cutoff;

	vec4 distortNoiseSample = texture(distortNoise, distortUV);
	vec2 distortAmount = (distortNoiseSample.xy * 2.0 - 1.0) * surface_distortion_amount;

	vec2 noise_uv = vec2(
		(noiseUV.x + TIME * surface_noise_scroll.x) + distortAmount.x,
		(noiseUV.y + TIME * surface_noise_scroll.y + distortAmount.y)
	);
	float surfaceNoiseSample = texture(surfaceNoise, noise_uv).r;
	float surfaceNoiseAmount = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

	float waterDepth = clamp(depth / depth_max_distance, 0.0, 1.0) * depth_factor;
	vec4 waterColor = mix(depth_gradient_shallow, depth_gradient_deep, waterDepth);

	vec4 surfaceNoiseColor = foam_color;
	surfaceNoiseColor.a *= surfaceNoiseAmount;
	vec4 color = alphaBlend(surfaceNoiseColor, waterColor);

	ALBEDO = color.rgb;
	ALPHA = color.a;
}
