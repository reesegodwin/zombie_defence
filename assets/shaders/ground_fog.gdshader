// One layer of ground fog (scenes/level/ground_fog.gd stacks several). Lit, so
// it's pale by day, dark at night and glows in the floodlight; in drifting
// patches; and vertex alpha thins it where the ground rises.
shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.6, 0.63, 0.68, 1.0);
uniform float density = 0.15;     // this layer's opacity where the fog is thickest
uniform float seed = 0.0;         // offsets the pattern per layer, so they don't line up
uniform float drift = 0.025;      // how fast the patches roll along, tiles a second

varying vec3 world;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 3; k++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz * 0.11 + vec2(seed * 3.7, seed * 1.3) + vec2(TIME * drift, TIME * drift * 0.6);
	float big = fbm(p);
	float wisp = noise(p * 3.1 - vec2(TIME * drift * 1.7, 0.0));   // one octave: cheap
	float patch = smoothstep(0.36, 0.7, big) * (0.55 + 0.45 * wisp);
	ALBEDO = tint.rgb;
	ROUGHNESS = 1.0;
	ALPHA = density * patch * COLOR.a;
}
