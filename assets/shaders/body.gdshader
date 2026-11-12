// The one material for every body (scenes/actors/body.gd). Colours come from
// the vertex colours (sRGB); their alpha says what the surface is: 1 dead skin
// (mottled, with dark veins), 0.75 living skin (faint blotches), 0.5 cloth (a
// coarse weave), 0 anything else (eyes, teeth, boots: left plain).
shader_type spatial;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	float dead = step(0.9, COLOR.a);
	float skin = step(0.65, COLOR.a);
	float cloth = step(0.25, COLOR.a) * (1.0 - skin);
	vec3 p = local_pos;

	// Skin: blotchy, with thin dark veins and a few darker patches.
	float mottle = noise(p * 22.0) * 0.6 + noise(p * 55.0) * 0.4;
	float vein = 1.0 - smoothstep(0.0, 0.03, abs(noise(p * 24.0 + vec3(7.1)) - 0.5));
	vein *= smoothstep(0.35, 0.75, noise(p * 7.0));
	vec3 sk = c * (0.82 + 0.36 * mottle);
	sk = mix(sk, sk * vec3(0.55, 0.6, 0.5), vein * 0.6 * dead);
	// The living are smoother, a touch warmer where the blood is.
	vec3 live = c * (0.93 + 0.12 * mottle);
	sk = mix(live, sk, dead);

	// Cloth: a coarse weave and wear.
	float weave = noise(p * vec3(260.0, 90.0, 260.0)) * 0.5 + noise(p * 40.0) * 0.5;
	vec3 cl = c * (0.8 + 0.4 * weave);

	ALBEDO = mix(c, mix(cl, sk, skin), max(skin, cloth));
	ROUGHNESS = mix(0.55, mix(0.95, 0.62, skin), max(skin, cloth));
	SPECULAR = mix(0.6, 0.35, cloth);
}
