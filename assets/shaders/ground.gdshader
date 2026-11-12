// The ground: grass (tinted per vertex by ground.gd for hollows, tops and
// slopes) with the dirt of the lanes and the yard painted into it, so the
// tracks blend into the forest floor with a soft, ragged edge instead of
// sitting on top of it. ground.gd works out how much dirt each point gets
// (UV2.x the front lane, UV2.y a side lane, COLOR.a the yard); a lane that's
// never used on this level stays grass.
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float grass_scale = 0.0667;   // world metres -> grass texture
uniform float dirt_scale = 0.12;
uniform float front_on = 1.0;
uniform float west_on = 1.0;
uniform float east_on = 1.0;

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float side_on = p.x < 11.0 ? west_on : east_on;
	float dirt = max(max(UV2.x * front_on, UV2.y * side_on), COLOR.a);
	// A ragged, tufty edge where the dirt meets the grass.
	float n = noise(p * 0.9);
	float edgeband = dirt * (1.0 - dirt) * 4.0;   // 1 mid-edge, 0 inside or out
	dirt = clamp(dirt + (n - 0.5) * 1.1 * edgeband, 0.0, 1.0);
	vec3 grass = texture(grass_tex, p * grass_scale).rgb * COLOR.rgb;
	vec3 soil = texture(dirt_tex, p * dirt_scale).rgb;
	ALBEDO = mix(grass, soil, dirt);
	ROUGHNESS = 1.0;
}
