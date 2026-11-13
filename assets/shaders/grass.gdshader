// Low-poly grass tufts: colours from the mesh (straw at the roots, green at
// the tips), both sides drawn, lit as if facing up (so they shade like the
// ground they grow from), swaying in the wind more toward the tips.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float sway = 0.07;     // metres the tips move
uniform float gust = 1.3;      // how fast
uniform vec4 pull = vec4(1.0, 1.0, 1.0, 0.0);   // the level's country: tint toward rgb by a

varying vec3 vcol;

void vertex() {
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vcol = mix(COLOR.rgb, pull.rgb * (0.6 + lum), pull.a);
	vec3 at = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float t = TIME * gust + at.x * 0.37 + at.z * 0.23;
	VERTEX.x += (sin(t) + 0.4 * sin(t * 2.3 + 1.0)) * sway * h * h * 6.0;
	VERTEX.z += cos(t * 0.8) * sway * 0.5 * h * h * 6.0;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = vcol;
	ROUGHNESS = 1.0;
}
