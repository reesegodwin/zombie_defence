// The visible beam out of a spotlight: an additive cone, brightest at the
// lamp, fading to nothing along its length and softly at its edges.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform float strength = 0.0;   // 0 off .. 1 fully on (set from level.gd)

varying float along;   // 0 at the lamp .. 1 at the far end

void vertex() {
	along = 0.5 - VERTEX.y / max(0.001, 2.0 * 4.0);   // the cone is 8 m long, lamp end at +y
}

void fragment() {
	// Edges of the cone fade (viewed side-on, the rim faces away).
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(1.0 - clamp(along, 0.0, 1.0), 1.8) * smoothstep(0.0, 0.6, rim);
	ALBEDO = color.rgb * a * strength * 0.22;
}
