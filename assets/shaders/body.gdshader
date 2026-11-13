// The one material for every body (scenes/actors/body.gd). Colours come from
// the vertex colours (sRGB); their alpha says what the surface is: 1 dead skin
// (mottled, with dark veins, sores and grime), 0.75 living skin (faint
// blotches), 0.5 cloth (a coarse weave), 0.35 cloth knitted in stripes, 0.15
// something that glows (eyes), 0 anything else (eyes, teeth, boots: plain).
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
	float stripe = cloth * (1.0 - step(0.43, COLOR.a));
	float glow = step(0.08, COLOR.a) * (1.0 - step(0.25, COLOR.a));
	vec3 p = local_pos;

	// Skin: blotchy, with thin dark veins and a few darker patches.
	float mottle = noise(p * 22.0) * 0.6 + noise(p * 55.0) * 0.4;
	float vein = 1.0 - smoothstep(0.0, mix(0.03, 0.012, dead), abs(noise(p * 24.0 + vec3(7.1)) - 0.5));
	vein *= smoothstep(0.35, 0.75, noise(p * 7.0));
	vec3 sk = c * (0.82 + 0.36 * mottle);
	sk = mix(sk, sk * vec3(0.62, 0.66, 0.72), vein * 0.22 * dead);
	// The dead: bruises going dark under the skin, small open sores, ingrained dirt.
	float bruise = smoothstep(0.55, 0.8, noise(p * 9.0 + vec3(3.3)));
	sk = mix(sk, sk * vec3(0.62, 0.5, 0.58), bruise * 0.55 * dead);
	float sore = smoothstep(0.7, 0.78, noise(p * 31.0 + vec3(11.7))) * smoothstep(0.45, 0.7, noise(p * 6.0 + vec3(5.1)));
	sk = mix(sk, vec3(0.13, 0.018, 0.012), sore * 0.8 * dead);
	float filth = smoothstep(0.5, 0.9, noise(p * 14.0 + vec3(21.0)) * 0.6 + noise(p * 70.0) * 0.4);
	sk = mix(sk, sk * vec3(0.5, 0.42, 0.33), filth * 0.5 * dead);
	// The living are smoother, a touch warmer where the blood is.
	vec3 live = c * (0.93 + 0.12 * mottle);
	sk = mix(live, sk, dead);

	// Cloth: a coarse weave and wear.
	float weave = noise(p * vec3(260.0, 90.0, 260.0)) * 0.5 + noise(p * 40.0) * 0.5;
	vec3 cl = c;
	// Stripes: every other band knitted in a dirty off-white.
	float band = smoothstep(0.46, 0.5, abs(fract(p.y / 0.084) - 0.5) * 2.0);
	cl = mix(cl, mix(cl, vec3(0.3, 0.28, 0.24), 0.75), band * stripe);
	cl *= 0.8 + 0.4 * weave;
	// Creases, and a rib knit on the stripes.
	cl *= 1.0 - 0.18 * smoothstep(0.55, 0.8, noise(p * vec3(30.0, 9.0, 30.0) + vec3(4.0)));
	cl *= 1.0 - 0.12 * stripe * step(0.5, fract(p.y * 180.0));

	ALBEDO = mix(c, mix(cl, sk, skin), max(skin, cloth));
	ROUGHNESS = mix(0.55, mix(0.95, 0.62, skin), max(skin, cloth));
	SPECULAR = mix(0.6, 0.35, cloth);
	// Wet blood shines.
	float wet = smoothstep(0.1, 0.3, c.r - c.g * 2.2) * step(c.r, 0.2) * (1.0 - glow);
	ROUGHNESS = mix(ROUGHNESS, 0.32, wet * 0.8);
	EMISSION = c * 2.6 * glow;
}
