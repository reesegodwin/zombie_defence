// Rock that turns see-through (with a dither pattern) wherever it stands
// between the camera and someone walking the mountain pass, so you can always
// see the scavenger. main.gd sets the walker positions every frame.
shader_type spatial;

global uniform vec3 walker_a;
global uniform vec3 walker_b;

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D grain : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float grain_scale = 0.12;
uniform float roughness_value = 1.0;
uniform float strata_amount = 0.05;   // faint rock layers; 0 for snow
uniform float radius = 2.6;        // metres around the walker, across the screen
uniform float softness = 1.2;

varying vec4 vcolor;
varying vec3 wpos;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);
	return (m[idx] + 0.5) / 16.0;
}

float cover(vec3 walker, vec3 view_pos, mat4 view) {
	if (walker.y < -50.0) {
		return 0.0;
	}
	vec3 w = (view * vec4(walker + vec3(0.0, 0.9, 0.0), 1.0)).xyz;
	// Only rock nearer the camera than the walker gets in the way.
	if (view_pos.z < w.z + 0.4) {
		return 0.0;
	}
	float d = length(view_pos.xy - w.xy);
	return 1.0 - smoothstep(radius, radius + softness, d);
}

void vertex() {
	vcolor = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float g = texture(grain, wpos.xz * grain_scale + vec2(wpos.y * 0.08)).r;
	float strata = 1.0 - strata_amount + strata_amount * sin(wpos.y * 2.5 + g * 6.0);
	ALBEDO = vcolor.rgb * tint.rgb * mix(0.7, 1.2, g) * strata;
	ROUGHNESS = roughness_value;
	float fade = max(cover(walker_a, VERTEX, VIEW_MATRIX), cover(walker_b, VERTEX, VIEW_MATRIX));
	if (fade * 0.85 > bayer4(FRAGCOORD.xy)) {
		discard;
	}
}
