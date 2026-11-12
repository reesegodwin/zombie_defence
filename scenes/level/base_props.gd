# Dresses the base in the game's detailed, built-in-code style: the plain
# boxes in level.tscn (bunker, huts, crates, barrels, tent, gate, walkway) keep
# their places and sizes, but are drawn as proper things - a sandbagged
# concrete bunker, plank huts with rusty tin roofs, slatted crates, oil drums,
# a sagging canvas tent, a log gate, a plank walkway on posts. Built from the
# same Kit as the guns, the turret and the culverts (guns.gd).
extends RefCounted

const Guns = preload("res://scenes/actors/guns.gd")
const Culvert = preload("res://scenes/level/culvert.gd")

const CONCRETE := Color(0.5, 0.5, 0.5)
const DARK := Color(0.08, 0.08, 0.09)
const SANDBAG := Color(0.55, 0.49, 0.36)
const PLANK := Color(0.45, 0.33, 0.22)
const OLD_PLANK := Color(0.36, 0.3, 0.24)
const TIN := Color(0.5, 0.5, 0.48)
const RUST := Color(0.45, 0.26, 0.15)
const STEEL := Color(0.3, 0.32, 0.3)
const CANVAS := Color(0.43, 0.45, 0.32)
const ROPE := Color(0.62, 0.55, 0.4)
const LOG := Color(0.33, 0.24, 0.17)
const DRUMS := [Color(0.48, 0.17, 0.12), Color(0.2, 0.3, 0.45), Color(0.34, 0.37, 0.22), Color(0.55, 0.45, 0.15)]


## Swaps the level's placeholder boxes for the detailed props.
static func dress(level: Node3D) -> void:
	_replace(level, "Bunker", ["Block", "Top", "Door"], _bunker())
	for h in ["Hut1", "Hut2"]:
		_replace(level, h, ["Walls", "Roof"], _hut(h == "Hut1"))
	var i := 0
	for n in level.get_children():
		if n.name.begins_with("Crate") and n is MeshInstance3D:
			_swap(n, _crate(i))
			i += 1
		elif n.name.begins_with("Barrel") and n is MeshInstance3D:
			_swap(n, _drum(i, false))
			i += 1
	var fb := level.get_node_or_null("FireBarrel/Barrel")
	if fb:
		_swap(fb, _drum(7, true))
	var tent := level.get_node_or_null("Tent")
	if tent:
		_swap(tent, _tent())
	_replace(level, "Gate", ["PostL", "PostR", "Beam"], _gate())
	var deck := level.get_node_or_null("Walkway")
	if deck:
		_swap(deck, _walkway())


static func _replace(level: Node3D, at: String, hide: Array, mesh: Mesh) -> void:
	var node := level.get_node_or_null(at)
	if node == null:
		return
	for h in hide:
		var c := node.get_node_or_null(h)
		if c:
			c.visible = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Culvert._material()
	node.add_child(mi)


static func _swap(mi: MeshInstance3D, mesh: Mesh) -> void:
	mi.mesh = mesh
	mi.material_override = Culvert._material()


static func _kit(wear: float, seed_value: int) -> Guns.Kit:
	var k := Guns.Kit.new()
	k.wear = wear
	k.rng.seed = seed_value
	return k


## A sandbag: a squashed, pillowy block.
static func _bag(k: Guns.Kit, p: Vector3, yaw: float) -> void:
	var c := SANDBAG * k.rng.randf_range(0.88, 1.08)
	c.a = 1.0
	k.box(p, Vector3(0.44, 0.15, 0.24), c, Vector3(k.rng.randf_range(-0.05, 0.05), yaw + k.rng.randf_range(-0.08, 0.08), k.rng.randf_range(-0.04, 0.04)))
	k.box(p + Vector3(0, 0.0, 0), Vector3(0.38, 0.19, 0.18), c, Vector3(0, yaw, 0))


# --- The bunker (2.6 x 1.5 x 2.2, the door on +z) -----------------------------
static func _bunker() -> ArrayMesh:
	var k := _kit(0.55, 11)
	k.stain = Color(0.3, 0.32, 0.28)
	k.fade = Color(0.66, 0.66, 0.64)
	k.box(Vector3(0, 0.75, 0), Vector3(2.6, 1.5, 2.2), CONCRETE)
	# Cast-panel seams and grime streaks running down.
	for x in [-0.65, 0.0, 0.65]:
		k.box(Vector3(x, 0.75, 1.104), Vector3(0.025, 1.45, 0.01), CONCRETE.darkened(0.25))
	for i in 6:
		var x := k.rng.randf_range(-1.2, 1.2)
		k.box(Vector3(x, 1.1, 1.103), Vector3(0.06, 0.6, 0.01), CONCRETE.darkened(0.3))
	# Roof slab with an overhang, sandbags along its edge.
	k.box(Vector3(0, 1.56, 0), Vector3(2.85, 0.14, 2.45), CONCRETE.darkened(0.1))
	for i in 6:
		_bag(k, Vector3(-1.15 + i * 0.46, 1.72, 1.05), 0.0)
		_bag(k, Vector3(-1.15 + i * 0.46, 1.72, -1.05), 0.0)
	# The lookout on top, with a dark slit facing the wall.
	k.box(Vector3(0, 1.88, -0.1), Vector3(1.0, 0.5, 0.8), CONCRETE.lightened(0.05))
	k.box(Vector3(0, 1.95, -0.505), Vector3(0.7, 0.09, 0.02), DARK)
	k.box(Vector3(0, 2.15, -0.1), Vector3(1.1, 0.06, 0.9), CONCRETE.darkened(0.15))
	# The steel door, framed, riveted, with a handle.
	k.box(Vector3(0, 0.5, 1.12), Vector3(0.74, 1.0, 0.05), STEEL.darkened(0.3))
	k.box(Vector3(0, 0.47, 1.15), Vector3(0.6, 0.9, 0.04), Color(0.36, 0.4, 0.3))
	for y in [0.15, 0.47, 0.8]:
		k.box(Vector3(0, y, 1.175), Vector3(0.56, 0.04, 0.02), Color(0.3, 0.33, 0.25))
	k.box(Vector3(0.22, 0.47, 1.19), Vector3(0.05, 0.12, 0.04), STEEL)
	# Sandbag walls each side of the door, two rows high.
	for row in 2:
		for i in 4:
			for sx in [-1, 1]:
				_bag(k, Vector3(sx * (0.62 + i * 0.4 + row * 0.2), 0.08 + row * 0.17, 1.38), 0.0)
		for i in 5:
			_bag(k, Vector3(1.42, 0.08 + row * 0.17, -0.95 + i * 0.44 + row * 0.2), PI / 2)
	# A ladder up the side to the roof, and vent pipes.
	for z in [-0.35, 0.05]:
		k.box(Vector3(-1.34, 0.85, z), Vector3(0.05, 1.7, 0.05), STEEL)
	for i in 7:
		k.box(Vector3(-1.34, 0.18 + i * 0.22, -0.15), Vector3(0.04, 0.035, 0.4), STEEL)
	for x in [0.85, 1.05]:
		k.cyl(Vector3(x, 1.85, 0.6), 0.06, 0.45, STEEL, 8, Vector3(PI / 2, 0, 0))
		k.cyl(Vector3(x, 2.09, 0.6), 0.09, 0.04, STEEL.darkened(0.2), 8, Vector3(PI / 2, 0, 0))
	return k.mesh()


# --- A hut (1.4 x 1.0 x 1.1 walls; a tin roof up to 1.6) ------------------------
static func _hut(stove: bool) -> ArrayMesh:
	var k := _kit(0.5, 21 if stove else 22)
	k.stain = RUST
	k.fade = Color(0.6, 0.55, 0.45)
	k.box(Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.1), OLD_PLANK)
	# Vertical boards over the walls, each a slightly different shade.
	for face in 4:
		var along := 1.4 if face < 2 else 1.1
		var n := int(along / 0.16)
		for i in n:
			var o := -along / 2 + (i + 0.5) * along / n
			var c := PLANK * k.rng.randf_range(0.75, 1.1)
			c.a = 1.0
			var h := 1.0 - k.rng.randf_range(0.0, 0.05)
			match face:
				0: k.box(Vector3(o, h / 2, 0.56), Vector3(along / n - 0.015, h, 0.025), c)
				1: k.box(Vector3(o, h / 2, -0.56), Vector3(along / n - 0.015, h, 0.025), c)
				2: k.box(Vector3(0.71, h / 2, o), Vector3(0.025, h, along / n - 0.015), c)
				3: k.box(Vector3(-0.71, h / 2, o), Vector3(0.025, h, along / n - 0.015), c)
	# Gables front and back, under the roof.
	for z in [0.565, -0.565]:
		k.poly([Vector3(-0.7, 1.0, z), Vector3(0.7, 1.0, z), Vector3(0, 1.55, z)], OLD_PLANK.darkened(0.1), Vector3(0, 1.2, 0))
	# The tin roof: two corrugated slopes, rusting.
	var slope := atan2(0.6, 0.85)
	for sx in [-1, 1]:
		var mid := Vector3(sx * 0.43, 1.31, 0)
		k.box(mid, Vector3(1.08, 0.03, 1.5), TIN, Vector3(0, 0, -sx * slope))
		for i in 11:
			var z := -0.7 + i * 0.14
			k.box(mid + Vector3(0, 0.025, z), Vector3(1.06, 0.025, 0.04), TIN.darkened(0.12), Vector3(0, 0, -sx * slope))
	k.box(Vector3(0, 1.61, 0), Vector3(0.12, 0.05, 1.52), TIN.darkened(0.2))
	# A plank door, a boarded-up window.
	k.box(Vector3(-0.3, 0.42, 0.58), Vector3(0.42, 0.84, 0.03), PLANK.darkened(0.25))
	for y in [0.2, 0.62]:
		k.box(Vector3(-0.3, y, 0.6), Vector3(0.4, 0.06, 0.02), PLANK)
	k.box(Vector3(0.72, 0.6, 0.0), Vector3(0.02, 0.32, 0.38), DARK)
	for r in [0.6, -0.6]:
		k.box(Vector3(0.74, 0.6, 0.0), Vector3(0.02, 0.07, 0.5), PLANK.lightened(0.1), Vector3(r, 0, 0))
	if stove:
		k.cyl(Vector3(-0.35, 1.7, -0.25), 0.06, 0.6, STEEL.darkened(0.2), 8, Vector3(PI / 2, 0, 0))
		k.cyl(Vector3(-0.35, 2.02, -0.25), 0.1, 0.05, STEEL.darkened(0.4), 8, Vector3(PI / 2, 0, 0))
	return k.mesh()


# --- A crate (0.55 cube, centred) ----------------------------------------------
static func _crate(i: int) -> ArrayMesh:
	var k := _kit(0.3, 31 + i)
	var wood := PLANK.lightened(0.05)
	k.box(Vector3.ZERO, Vector3(0.53, 0.53, 0.53), wood)
	for s in 3:   # slats on the sides
		var y := -0.17 + s * 0.17
		for face in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
			var p: Vector3 = face * 0.268 + Vector3(0, y, 0)
			var sz := Vector3(0.5, 0.13, 0.01) if face.z != 0.0 else Vector3(0.01, 0.13, 0.5)
			k.box(p, sz, wood * k.rng.randf_range(0.8, 1.05))
	# The dark frame along its edges, and a brace across two faces.
	var e := 0.275
	for a in [-1, 1]:
		for b in [-1, 1]:
			k.box(Vector3(a * e, 0, b * e), Vector3(0.05, 0.56, 0.05), PLANK.darkened(0.3))
			k.box(Vector3(a * e, b * e, 0), Vector3(0.05, 0.05, 0.56), PLANK.darkened(0.3))
			k.box(Vector3(0, a * e, b * e), Vector3(0.56, 0.05, 0.05), PLANK.darkened(0.3))
	k.box(Vector3(0, 0, 0.282), Vector3(0.66, 0.05, 0.015), PLANK.darkened(0.2), Vector3(0, 0, 0.78))
	k.box(Vector3(0.282, 0, 0), Vector3(0.015, 0.05, 0.66), PLANK.darkened(0.2), Vector3(0.78, 0, 0))
	return k.mesh()


# --- An oil drum (r 0.25, 0.8 tall, centred) -----------------------------------
static func _drum(i: int, burning: bool) -> ArrayMesh:
	var k := _kit(0.75 if burning else 0.55, 41 + i)
	var c: Color = Color(0.18, 0.16, 0.15) if burning else DRUMS[i % DRUMS.size()]
	var up := Vector3(PI / 2, 0, 0)
	k.cyl(Vector3.ZERO, 0.25, 0.8, c, 14, up)
	for y in [-0.36, -0.12, 0.12, 0.36]:
		k.cyl(Vector3(0, y, 0), 0.262, 0.035, c.darkened(0.25), 14, up)
	k.cyl(Vector3(0, 0.395, 0), 0.22, 0.02, c.darkened(0.15) if not burning else DARK, 14, up)
	if not burning:
		k.cyl(Vector3(0.12, 0.41, 0.05), 0.03, 0.03, STEEL, 6, up)
	else:
		for n in 8:   # holes punched round it for the draught
			var a := TAU * n / 8.0
			k.box(Vector3(cos(a) * 0.252, -0.22, sin(a) * 0.252), Vector3(0.05, 0.05, 0.05), Color(0.9, 0.45, 0.12), Vector3(0, -a, 0))
	return k.mesh()


# --- The tent (1.4 wide, 0.9 tall, 1.7 deep, centred) ----------------------------
static func _tent() -> ArrayMesh:
	var k := _kit(0.35, 51)
	k.stain = Color(0.32, 0.3, 0.22)
	var top := 0.45
	var bot := -0.45
	var half := 0.85
	# Two canvas slopes, sagging a little between the poles.
	for sx in [-1, 1]:
		var zs := [-half, -0.28, 0.28, half]
		for i in 3:
			var za: float = zs[i]
			var zb: float = zs[i + 1]
			var sag_a := 0.0 if absf(za) > 0.8 else 0.06
			var sag_b := 0.0 if absf(zb) > 0.8 else 0.06
			var mid_a := Vector3(sx * 0.36, (top + bot) / 2 - sag_a, za)
			var mid_b := Vector3(sx * 0.36, (top + bot) / 2 - sag_b, zb)
			var c := CANVAS * (0.95 if i == 1 else 1.0)
			c.a = 1.0
			k.poly([Vector3(0, top, za), Vector3(0, top, zb), mid_b, mid_a], c, Vector3(0, -2, 0))
			k.poly([mid_a, mid_b, Vector3(sx * 0.72, bot, zb), Vector3(sx * 0.72, bot, za)], c.darkened(0.06), Vector3(0, -2, 0))
	# The back closed; the front open, one flap tied back.
	k.poly([Vector3(-0.72, bot, -half), Vector3(0.72, bot, -half), Vector3(0, top, -half)], CANVAS.darkened(0.1), Vector3(0, 0, 0))
	k.poly([Vector3(-0.42, bot, half - 0.02), Vector3(0.42, bot, half - 0.02), Vector3(0, top - 0.05, half - 0.02)], DARK, Vector3(0, 0, 0))
	k.poly([Vector3(0, top, half), Vector3(-0.72, bot, half), Vector3(-0.3, bot, half + 0.12)], CANVAS.darkened(0.15), Vector3(0, 0, 0))
	# Ridge pole, guy ropes and pegs, a ground sheet.
	k.box(Vector3(0, top + 0.02, 0), Vector3(0.04, 0.04, half * 2 + 0.25), LOG)
	for z in [-half - 0.12, half + 0.12]:
		k.box(Vector3(0, 0.0, z), Vector3(0.04, 0.95, 0.04), LOG)
	for sx in [-1, 1]:
		for z in [-0.55, 0.55]:
			k.box(Vector3(sx * 0.95, bot + 0.18, z), Vector3(0.012, 0.012, 0.62), ROPE, Vector3(0, PI / 2, sx * 0.55))
			k.box(Vector3(sx * 1.2, bot + 0.04, z), Vector3(0.03, 0.1, 0.03), LOG)
	k.box(Vector3(0, bot + 0.01, 0.1), Vector3(1.6, 0.02, 2.0), Color(0.24, 0.27, 0.2))
	return k.mesh()


# --- The gate to the pass (posts 2 m apart, beam at 2.05 m) -----------------------
static func _gate() -> ArrayMesh:
	var k := _kit(0.4, 61)
	var up := Vector3(PI / 2, 0, 0)
	for sx in [-1, 1]:
		k.cyl(Vector3(sx * 1.0, 1.05, 0), 0.12, 2.2, LOG, 8, up)
		k.cyl(Vector3(sx * 1.0, 2.17, 0), 0.1, 0.06, LOG.darkened(0.2), 8, up)
		k.box(Vector3(sx * 0.8, 1.72, 0), Vector3(0.5, 0.08, 0.08), LOG.lightened(0.05), Vector3(0, 0, sx * 0.75))
	k.cyl(Vector3(0, 2.0, 0), 0.1, 2.6, LOG, 8, Vector3(0, PI / 2, 0))
	# A plank sign hung on ropes.
	for sx in [-0.45, 0.45]:
		k.box(Vector3(sx, 1.8, 0.05), Vector3(0.02, 0.3, 0.02), ROPE)
	k.box(Vector3(0, 1.6, 0.06), Vector3(1.2, 0.22, 0.04), PLANK)
	k.box(Vector3(0, 1.6, 0.085), Vector3(0.9, 0.05, 0.01), Color(0.75, 0.2, 0.12))
	return k.mesh()


# --- The front walkway (14 x 0.45 x 1.3, centred) -------------------------------
static func _walkway(length := 14.0) -> ArrayMesh:
	var h := length / 2.0
	var k := _kit(0.3, 71)
	k.box(Vector3(0, -0.04, 0), Vector3(length, 0.37, 1.24), OLD_PLANK.darkened(0.25))
	# Boards along the top, each its own shade, small gaps between.
	for i in 5:
		var z := -0.52 + i * 0.26
		var x := -h
		while x < h:
			var l := minf(k.rng.randf_range(1.8, 3.2), h - x)
			var c := PLANK * k.rng.randf_range(0.8, 1.1)
			c.a = 1.0
			k.box(Vector3(x + l / 2, 0.19, z), Vector3(l - 0.02, 0.07, 0.24), c)
			x += l
	# Posts and a beam along the yard side.
	k.box(Vector3(0, 0.05, 0.64), Vector3(length, 0.12, 0.08), LOG)
	var px := -h + 0.2
	while px <= h - 0.1:
		k.box(Vector3(px, -0.05, 0.64), Vector3(0.12, 0.42, 0.12), LOG)
		px += 1.7
	return k.mesh()
