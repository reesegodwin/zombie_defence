// The base's props, the culverts and the walkways: their colours baked into
// the mesh (as sRGB vertex colours), lit like plain rough paint. On snowy
// levels, "snow" lays white over whatever faces up (roofs, the tops of
// crates and benches, the walkway planks), patchy, thinning on slopes.
shader_type spatial;

uniform float snow = 0.0;
uniform vec4 snow_color : source_color = vec4(0.86, 0.88, 0.93, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 vcol;

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

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	// (As StandardMaterial3D's vertex_color_is_srgb does: only where the
	// renderer works in linear light.)
	vcol = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) {
		vcol = srgb_to_linear(vcol);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = vcol;
	float k = 0.0;
	if (snow > 0.0) {
		float up = smoothstep(0.45, 0.85, normalize(wnorm).y);
		float patch = smoothstep(0.25, 0.6, noise(wpos.xz * 2.3) * 0.7 + noise(wpos.xz * 7.0) * 0.3);
		k = snow * up * mix(0.55, 1.0, patch);
	}
	ALBEDO = mix(c, snow_color.rgb, k);
	ROUGHNESS = mix(0.95, 0.8, k);
}
