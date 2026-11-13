# The yards of the bases you hold, one per level (D.LEVELS "base"). The walls,
# walkways, gate and lanes are the same everywhere; what changes is where the
# buildings and clutter in the yard stand, so every base plays and looks a
# little different: where there's room to put turrets and traps, where the
# benches are, what's in the way when the dead get in.
#
# Each prop: [x, z, yaw] in metres and radians (the yaw is added to the
# prop's own). Footprints (FOOT) give each prop's blocked ground; D.BLOCKERS
# is built from them (see blockers()), with the path to the gate always kept
# clear. turrets: two spots in the yard for auto-turrets (the two at the ends
# of the front walkway are the same everywhere). radio: where the test bot
# puts the radio.
extends RefCounted

## Ground each prop takes up (width x, depth z), before its yaw.
const FOOT := {
	"bunker": Vector2(2.8, 2.4), "hut1": Vector2(1.7, 1.4), "hut2": Vector2(1.9, 1.8),
	"crates": Vector2(1.8, 1.8), "barrel1": Vector2(0.8, 0.8), "barrel2": Vector2(0.8, 0.8),
	"fire": Vector2(1.0, 1.0), "tent": Vector2(2.0, 2.2), "generator": Vector2(1.4, 1.0),
	"worklamp": Vector2(0.4, 0.4), "lamp1": Vector2(0.4, 0.4), "lamp2": Vector2(0.4, 0.4),
	"workshop": Vector2(1.8, 0.9), "research": Vector2(1.4, 1.0), "woodpile": Vector2(1.6, 0.8),
}
const CORNER_TURRETS := [Vector2(2.9, 15.0), Vector2(19.1, 15.0)]

const BASES := {
	# The outpost of the first levels: bunker at the front left, huts at the
	# front right, the tent and crates between, the benches at the back.
	"outpost": {
		"props": {"bunker": [5.0, 18.0, 0.0], "hut1": [14.0, 18.0, 0.0], "hut2": [15.4, 19.6, 0.0],
			"crates": [9.5, 18.6, 0.0], "barrel1": [12.2, 19.4, 0.0], "barrel2": [8.3, 20.3, 0.0],
			"fire": [12.8, 20.2, 0.0], "tent": [8.9, 20.9, 0.0], "generator": [4.3, 26.6, 0.0],
			"worklamp": [5.4, 25.6, 0.0], "lamp1": [8.0, 24.5, 0.0], "lamp2": [14.5, 24.5, 0.0],
			"workshop": [17.0, 27.05, 0.0], "research": [7.4, 26.85, 0.0], "woodpile": [14.2, 27.2, 0.0]},
		"turrets": [Vector2(6.8, 22.0), Vector2(15.8, 22.6)], "radio": Vector2(17.8, 25.0)},
	# A ridge camp: everything pulled back against the rear fence, a wide open
	# yard behind the wall.
	"ridge": {
		"props": {"bunker": [4.6, 25.8, 0.0], "hut1": [16.2, 25.9, 0.0], "hut2": [18.4, 24.4, -0.6],
			"crates": [7.6, 26.6, 0.4], "barrel1": [13.6, 26.9, 0.0], "barrel2": [14.4, 26.6, 0.0],
			"fire": [8.4, 21.4, 0.0], "tent": [17.3, 21.6, 1.57], "generator": [3.4, 22.6, 1.57],
			"worklamp": [4.4, 21.4, 0.0], "lamp1": [6.2, 19.4, 0.0], "lamp2": [15.6, 19.4, 0.0],
			"workshop": [17.6, 17.4, 0.0], "research": [4.6, 17.4, 0.0], "woodpile": [8.4, 24.0, 0.0]},
		"turrets": [Vector2(6.0, 21.6), Vector2(14.6, 21.4)], "radio": Vector2(14.6, 23.6)},
	# A marsh station: the bunker in the middle of the right, the huts on
	# stilts at the left, the benches by the wall where the light is.
	"marsh": {
		"props": {"bunker": [16.6, 21.6, 0.0], "hut1": [4.0, 19.0, 0.0], "hut2": [4.4, 21.4, 0.4],
			"crates": [8.4, 24.6, 0.0], "barrel1": [13.4, 24.6, 0.0], "barrel2": [14.0, 25.4, 0.0],
			"fire": [8.0, 21.8, 0.0], "tent": [5.6, 26.0, 1.57], "generator": [18.2, 26.6, 0.0],
			"worklamp": [16.6, 25.4, 0.0], "lamp1": [8.6, 18.2, 0.0], "lamp2": [13.6, 18.2, 0.0],
			"workshop": [14.6, 16.8, 0.0], "research": [7.0, 16.9, 0.0], "woodpile": [16.6, 18.6, 0.0]},
		"turrets": [Vector2(13.6, 21.0), Vector2(6.4, 21.6)], "radio": Vector2(15.2, 26.6)},
	# A farmstead: two barns (the huts) side by side at the back, the bunker
	# a root cellar at the front right.
	"farm": {
		"props": {"bunker": [16.6, 18.2, 0.0], "hut1": [5.0, 26.0, 0.0], "hut2": [7.6, 26.0, 0.0],
			"crates": [14.6, 22.6, 0.6], "barrel1": [13.4, 26.8, 0.0], "barrel2": [14.2, 27.0, 0.0],
			"fire": [6.6, 20.6, 0.0], "tent": [4.6, 18.6, 0.0], "generator": [18.6, 26.4, 1.57],
			"worklamp": [17.4, 25.0, 0.0], "lamp1": [8.6, 22.6, 0.0], "lamp2": [13.4, 20.2, 0.0],
			"workshop": [16.0, 24.4, 0.0], "research": [7.6, 18.0, 0.0], "woodpile": [4.0, 22.6, 1.57]},
		"turrets": [Vector2(6.4, 23.4), Vector2(18.4, 21.2)], "radio": Vector2(17.9, 23.0)},
	# A burnt-out camp: the huts and tent strung along the left, the bunker
	# alone at the back right, the middle left clear.
	"camp": {
		"props": {"bunker": [17.0, 25.8, 0.0], "hut1": [3.6, 18.4, 1.57], "hut2": [3.8, 21.4, 1.2],
			"crates": [8.2, 26.4, 0.0], "barrel1": [13.6, 18.0, 0.0], "barrel2": [14.4, 18.4, 0.0],
			"fire": [7.4, 22.0, 0.0], "tent": [4.4, 25.4, 1.57], "generator": [18.6, 21.6, 1.57],
			"worklamp": [18.0, 19.6, 0.0], "lamp1": [8.4, 19.0, 0.0], "lamp2": [14.6, 22.8, 0.0],
			"workshop": [16.6, 17.2, 0.0], "research": [6.6, 17.0, 0.0], "woodpile": [13.6, 27.0, 0.0]},
		"turrets": [Vector2(8.0, 24.4), Vector2(15.8, 20.6)], "radio": Vector2(14.6, 25.0)},
	# A mill: a long line of buildings down the middle of each half, lanes of
	# open ground between them.
	"mill": {
		"props": {"bunker": [6.2, 22.4, 1.57], "hut1": [15.6, 20.4, 0.0], "hut2": [15.6, 22.4, 0.0],
			"crates": [15.6, 25.4, 0.0], "barrel1": [6.2, 18.4, 0.0], "barrel2": [7.0, 18.6, 0.0],
			"fire": [8.8, 25.6, 0.0], "tent": [6.0, 26.4, 0.0], "generator": [18.8, 17.6, 1.57],
			"worklamp": [17.8, 18.4, 0.0], "lamp1": [8.8, 20.0, 0.0], "lamp2": [13.4, 24.0, 0.0],
			"workshop": [17.4, 27.2, 0.0], "research": [3.2, 18.6, 1.57], "woodpile": [3.2, 25.6, 1.57]},
		"turrets": [Vector2(3.6, 22.2), Vector2(18.2, 22.6)], "radio": Vector2(13.4, 18.6)},
	# A rail depot: bunker and huts in a row along the back, crates stacked
	# by the wall, the benches in the middle.
	"depot": {
		"props": {"bunker": [4.6, 26.0, 0.0], "hut1": [15.2, 26.6, 0.0], "hut2": [17.6, 26.4, 0.0],
			"crates": [4.4, 17.6, 0.0], "barrel1": [17.6, 17.4, 0.0], "barrel2": [18.4, 17.8, 0.0],
			"fire": [8.6, 23.4, 0.0], "tent": [17.0, 21.6, 1.57], "generator": [7.8, 26.8, 0.0],
			"worklamp": [8.8, 25.4, 0.0], "lamp1": [6.6, 21.0, 0.0], "lamp2": [14.2, 23.0, 0.0],
			"workshop": [14.4, 20.4, 0.0], "research": [7.2, 18.8, 0.0], "woodpile": [3.4, 22.2, 1.57]},
		"turrets": [Vector2(5.0, 23.4), Vector2(15.4, 24.4)], "radio": Vector2(13.6, 18.2)},
	# A hunting lodge: the bunker as the lodge at the back left, a crowded
	# yard of huts and tents to the right.
	"lodge": {
		"props": {"bunker": [5.2, 25.2, 0.0], "hut1": [15.0, 18.0, 0.4], "hut2": [17.8, 19.6, -0.3],
			"crates": [17.4, 25.4, 0.0], "barrel1": [13.6, 21.8, 0.0], "barrel2": [14.2, 22.6, 0.0],
			"fire": [7.6, 20.4, 0.0], "tent": [16.6, 22.8, 0.0], "generator": [3.6, 21.6, 1.57],
			"worklamp": [4.6, 20.2, 0.0], "lamp1": [8.6, 18.0, 0.0], "lamp2": [14.0, 26.4, 0.0],
			"workshop": [7.6, 22.8, 0.0], "research": [4.4, 17.6, 0.0], "woodpile": [18.4, 27.2, 0.0]},
		"turrets": [Vector2(6.0, 18.2), Vector2(13.4, 24.4)], "radio": Vector2(8.6, 25.6)},
	# A trench line: everything low and spread in a staggered line across the
	# middle, the back of the yard clear for turrets.
	"trench": {
		"props": {"bunker": [11.2, 18.4, 0.0], "hut1": [4.0, 20.4, 0.0], "hut2": [18.0, 20.4, 0.0],
			"crates": [6.8, 21.0, 0.0], "barrel1": [15.0, 21.0, 0.0], "barrel2": [15.8, 21.4, 0.0],
			"fire": [7.8, 24.6, 0.0], "tent": [4.4, 25.2, 0.0], "generator": [18.6, 24.6, 1.57],
			"worklamp": [17.6, 23.2, 0.0], "lamp1": [8.4, 18.2, 0.0], "lamp2": [14.2, 18.2, 0.0],
			"workshop": [16.6, 27.0, 0.0], "research": [6.6, 27.0, 0.0], "woodpile": [13.6, 24.4, 0.0]},
		"turrets": [Vector2(4.6, 17.6), Vector2(17.6, 17.6)], "radio": Vector2(14.0, 26.0)},
	# A barricade: crates, barrels and the tent strung across as a second
	# line of cover a few metres behind the wall.
	"barricade": {
		"props": {"bunker": [16.8, 25.6, 0.0], "hut1": [4.0, 26.2, 0.0], "hut2": [6.4, 26.4, 0.0],
			"crates": [4.4, 19.6, 0.0], "barrel1": [8.0, 19.4, 0.0], "barrel2": [13.6, 19.6, 0.0],
			"fire": [14.4, 22.6, 0.0], "tent": [17.6, 19.8, 0.0], "generator": [3.4, 23.0, 1.57],
			"worklamp": [4.4, 22.0, 0.0], "lamp1": [8.4, 22.4, 0.0], "lamp2": [14.0, 25.6, 0.0],
			"workshop": [8.0, 24.2, 0.0], "research": [17.6, 22.6, 0.0], "woodpile": [6.4, 19.6, 0.0]},
		"turrets": [Vector2(15.6, 17.4), Vector2(6.4, 17.4)], "radio": Vector2(13.6, 26.6)},
	# The fortress: the bunker dead centre in front of the gate path, huts
	# flanking, benches tucked in the back corners.
	"fortress": {
		"props": {"bunker": [11.2, 18.6, 0.0], "hut1": [5.0, 18.4, 0.0], "hut2": [17.2, 18.4, 0.0],
			"crates": [5.0, 22.6, 0.0], "barrel1": [16.6, 22.0, 0.0], "barrel2": [17.4, 22.4, 0.0],
			"fire": [8.4, 23.2, 0.0], "tent": [16.8, 25.0, 1.57], "generator": [3.4, 25.6, 1.57],
			"worklamp": [4.4, 24.6, 0.0], "lamp1": [8.4, 20.6, 0.0], "lamp2": [14.2, 20.6, 0.0],
			"workshop": [18.4, 27.2, 0.0], "research": [3.8, 27.4, 0.0], "woodpile": [7.6, 27.2, 0.0]},
		"turrets": [Vector2(7.0, 25.4), Vector2(14.0, 23.6)], "radio": Vector2(14.2, 26.6)},
}


## How each kind of country looks (D.LEVELS "palette"): the grass, the bare
## dirt, the trees and the grass tufts are each pulled toward a colour by an
## amount (0 leaves them as they are), and the haze takes a tint.
const PALETTES := {
	"green": {},
	"snow": {"grass": [Color(0.88, 0.9, 0.95), 0.92], "soil": [Color(0.78, 0.78, 0.8), 0.5], "trees": [Color(0.7, 0.78, 0.8), 0.35],
		"tufts": [Color(0.85, 0.86, 0.82), 0.7], "haze": Color(0.85, 0.9, 1.0)},
	"marsh": {"grass": [Color(0.25, 0.3, 0.18), 0.55], "soil": [Color(0.24, 0.21, 0.15), 0.55], "trees": [Color(0.1, 0.15, 0.09), 0.4],
		"tufts": [Color(0.35, 0.42, 0.2), 0.45], "haze": Color(0.8, 0.92, 0.8)},
	"dust": {"grass": [Color(0.62, 0.52, 0.32), 0.8], "soil": [Color(0.7, 0.56, 0.38), 0.4], "trees": [Color(0.3, 0.29, 0.14), 0.5],
		"tufts": [Color(0.75, 0.65, 0.35), 0.8], "haze": Color(1.05, 0.95, 0.8)},
	"ash": {"grass": [Color(0.2, 0.19, 0.18), 0.85], "soil": [Color(0.25, 0.23, 0.22), 0.5], "trees": [Color(0.08, 0.075, 0.07), 0.85],
		"tufts": [Color(0.3, 0.28, 0.25), 0.8], "haze": Color(0.85, 0.82, 0.8)},
	"autumn": {"grass": [Color(0.48, 0.4, 0.18), 0.5], "soil": [Color(0.45, 0.32, 0.2), 0.2], "trees": [Color(0.55, 0.2, 0.07), 0.6],
		"tufts": [Color(0.75, 0.45, 0.15), 0.6], "haze": Color(1.05, 0.9, 0.8)},
	"rust": {"grass": [Color(0.38, 0.33, 0.22), 0.55], "soil": [Color(0.42, 0.26, 0.16), 0.5], "trees": [Color(0.15, 0.16, 0.1), 0.3],
		"tufts": [Color(0.55, 0.45, 0.25), 0.5], "haze": Color(1.0, 0.88, 0.8)},
}


## A palette's pull for one thing ("grass", ...): [colour, amount].
static func pull(palette: String, what: String) -> Array:
	return PALETTES.get(palette, {}).get(what, [Color.WHITE, 0.0])


## The ground a prop at [x, z, yaw] blocks (turned a quarter or more, its
## width and depth swap).
static func foot_rect(prop: String, at: Array) -> Rect2:
	var f: Vector2 = FOOT[prop]
	var yaw := absf(wrapf(float(at[2]), -PI, PI))
	if yaw > PI * 0.25 and yaw < PI * 0.75:
		f = Vector2(f.y, f.x)
	return Rect2(Vector2(at[0], at[1]) - f / 2.0, f)


## D.BLOCKERS for a base: every prop's footprint, plus the path to the gate.
static func blockers(key: String, gate_path: Rect2) -> Array:
	var out: Array = []
	var props: Dictionary = BASES[key]["props"]
	for p in props:
		out.append(foot_rect(p, props[p]))
	out.append(gate_path)
	return out


static func turret_spots(key: String) -> Array:
	return CORNER_TURRETS + BASES[key]["turrets"]
