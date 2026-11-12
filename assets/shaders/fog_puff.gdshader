// A puff of ground fog: an upright sprite standing on the ground and turning
// round its own vertical axis to face the camera (so it meets the ground and
// the zombies' legs cleanly), flat-bottomed and soft at the top and sides,
// with churning, lumpy edges. Each one drifts slowly about its spot and
// swells and shrinks a little. Lit, brighter on top than underneath.
// Per puff (MultiMesh custom data): x phase, y thickness, z pattern seed,
// w size; scaled by the instance transform's basis (width, height).
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.92, 0.95, 1.0);
uniform float density = 0.55;
uniform float wander = 0.7;     // how far a puff drifts from its spot, metres
uniform float churn = 0.035;    // how fast its edges roll

varying vec4 puff;
varying vec2 size;      // the puff's width and height, metres

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
	for (int k = 0; k < 4; k++) {
		v += noise(p) * a;
		p = p * 2.07 + vec2(13.0, 7.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	puff = INSTANCE_CUSTOM;
	float ph = puff.x * 6.2832;
	vec3 centre = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	size = vec2(w, h);
	// Wander slowly round its spot, and breathe.
	centre += vec3(sin(TIME * 0.05 + ph) * wander, 0.0, cos(TIME * 0.037 + ph * 1.7) * wander);
	float breathe = 1.0 + 0.12 * sin(TIME * 0.21 + ph * 2.3);
	// Face the camera, turning only about the vertical.
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 world = centre + right * VERTEX.x * w * breathe + vec3(0.0, 1.0, 0.0) * VERTEX.y * h * breathe;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Lit mostly from above, partly from the front.
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(up * 0.7 + vec3(0.0, 0.0, 1.0) * 0.3);
}

void fragment() {
	// x -1..1 across; y 0 at the ground .. 1 at the top.
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	vec2 drift = vec2(TIME * churn, -TIME * churn * 0.6) + puff.zz * 9.0;
	// The swirls are sized in metres, so they're round, not stretched.
	vec2 m = UV * size;
	float n = fbm(m * 1.3 + drift);
	float n2 = fbm(m * 2.9 - drift * 1.4 + 3.0);
	// A dome: round at the top and sides, flat where it sits on the ground.
	float r = length(vec2(q.x, max(q.y - 0.1, 0.0) * 1.1));
	float body = 1.0 - smoothstep(0.05 + 0.3 * n, 1.0, r + (n2 - 0.5) * 0.35);
	body *= smoothstep(1.0, 0.35, q.y);           // thinning into wisps at the top
	body *= smoothstep(0.0, 0.3, q.y + (n - 0.5) * 0.25);   // melting into the ground, raggedly
	float a = body * (0.45 + 0.75 * n);
	// A touch brighter on top.
	float shade = mix(0.9, 1.0, smoothstep(0.0, 0.9, q.y)) * (0.94 + 0.12 * n2);
	ALBEDO = tint.rgb * shade;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a * density * puff.y, 0.0, 1.0);
}
