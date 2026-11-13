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


## Swaps the level's placeholder boxes for the detailed props, and adds the
## yard's clutter and lights. Returns the yard lights (level.gd dims them by day).
static func dress(level: Node3D) -> Array:
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
	return _yard(level)


## The yard's own things, so it isn't dark and bare at night: a generator with
## a work lamp, two lamp posts by the path, a workbench under a hanging bulb,
## a woodpile. (Their footprints are in defs.gd BLOCKERS.)
static func _yard(level: Node3D) -> Array:
	var lights: Array = []
	var add := func(nm: String, mesh: Mesh, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = mesh
		mi.material_override = Culvert._material()
		mi.position = pos
		mi.rotation.y = yaw
		level.add_child(mi)
		return mi
	# Each lamp's light hangs off its prop, so it moves with it (bases.gd).
	var lamp := func(on: Node3D, local: Vector3, rng: float, col: Color) -> void:
		var l := OmniLight3D.new()
		l.position = local
		l.light_color = col
		l.omni_range = rng
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		on.add_child(l)
		lights.append(l)
	add.call("Generator", _generator(), Vector3(4.3, 0.0, 26.6))
	var wl: MeshInstance3D = add.call("WorkLamp", _lamp_post(true), Vector3(5.4, 0.0, 25.6), PI * 0.75)
	lamp.call(wl, Vector3(0.0, 2.1, 0.57), 8.0, Color(1.0, 0.85, 0.6))
	for k in 2:
		var lp: MeshInstance3D = add.call("LampPost%d" % (k + 1), _lamp_post(false), Vector3([8.0, 14.5][k], 0.0, 24.5))
		lamp.call(lp, Vector3(0.48, 1.95, 0.0), 8.5, Color(1.0, 0.75, 0.45))
	var wb: MeshInstance3D = add.call("WorkshopBench", _workbench(), Vector3(17.0, 0.0, 27.05))
	lamp.call(wb, Vector3(0.0, 1.75, -0.15), 6.0, Color(1.0, 0.8, 0.5))
	add.call("Woodpile", _woodpile(), Vector3(14.2, 0.0, 27.2))
	add.call("ResearchDesk", _drafting_table(), Vector3(7.4, 0.0, 26.85))
	return lights


static func _bulb(k: Guns.Kit, p: Vector3) -> void:
	k.cyl(p, 0.07, 0.12, Color(1.0, 0.9, 0.6) * 2.0, 8, Vector3(PI / 2, 0, 0))


## A rusty generator on skids, with an exhaust and a fuel can.
static func _generator() -> ArrayMesh:
	var k := _kit(0.6, 81)
	k.stain = RUST
	for z in [-0.3, 0.3]:
		k.box(Vector3(0, 0.05, z), Vector3(1.3, 0.1, 0.1), LOG.darkened(0.3))
	k.box(Vector3(0, 0.42, 0), Vector3(1.1, 0.62, 0.7), Color(0.55, 0.42, 0.12))
	k.box(Vector3(0.1, 0.42, 0.36), Vector3(0.6, 0.4, 0.02), Color(0.2, 0.2, 0.2))   # grille
	k.box(Vector3(-0.38, 0.6, 0.36), Vector3(0.16, 0.12, 0.03), Color(0.15, 0.5, 0.2) * 1.4)   # running light
	k.cyl(Vector3(0.42, 0.95, -0.15), 0.05, 0.45, STEEL.darkened(0.3), 8, Vector3(PI / 2, 0, 0))
	k.box(Vector3(-0.8, 0.22, 0.2), Vector3(0.24, 0.4, 0.16), Color(0.6, 0.12, 0.1))   # fuel can
	for i in 6:   # cable snaking off toward the lamp
		k.box(Vector3(0.62 + i * 0.12, 0.02, 0.4 - i * 0.09), Vector3(0.14, 0.03, 0.03), Color(0.08, 0.08, 0.08), Vector3(0, 0.6, 0))
	return k.mesh()


## A lamp post: a pole with a shaded lamp on an arm (work = a tripod work lamp).
static func _lamp_post(work: bool) -> ArrayMesh:
	var k := _kit(0.3, 91)
	var up := Vector3(PI / 2, 0, 0)
	if work:
		for i in 3:
			var a := TAU * i / 3.0
			k.box(Vector3(cos(a) * 0.18, 0.55, sin(a) * 0.18), Vector3(0.03, 1.15, 0.03), STEEL, Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25))
		k.box(Vector3(0, 1.85, 0), Vector3(0.05, 0.8, 0.05), STEEL)
		k.box(Vector3(0, 2.2, 0.22), Vector3(0.4, 0.3, 0.12), Color(0.85, 0.65, 0.12))
		k.box(Vector3(0, 2.2, 0.29), Vector3(0.34, 0.24, 0.02), Color(1.0, 0.95, 0.75) * 2.0)
	else:
		# A pole with an arm out from the top (braced), and a deep enamel
		# shade hanging off its end over the bulb.
		k.cyl(Vector3(0, 1.2, 0), 0.06, 2.4, LOG, 8, up)
		k.cyl(Vector3(0, 2.42, 0), 0.07, 0.04, LOG.darkened(0.2), 8, up)            # cap
		k.box(Vector3(0.25, 2.33, 0), Vector3(0.56, 0.06, 0.06), LOG)                # the arm
		k.box(Vector3(0.48, 2.25, 0), Vector3(0.02, 0.12, 0.02), STEEL)              # the hanger
		var shade := Color(0.24, 0.32, 0.28)
		k.cyl(Vector3(0.48, 2.12, 0), 0.05, 0.16, shade, 12, up, 0.2)                 # the cone, open below
		k.cyl(Vector3(0.48, 2.035, 0), 0.205, 0.015, shade.darkened(0.25), 12, up)    # its rolled rim
		_bulb(k, Vector3(0.48, 2.02, 0))
	return k.mesh()


## The workshop bench (click it to open the Workshop): a steel desk with a
## bank of drawers each side, a pegboard of tools behind with a shelf of
## cans and jugs, and clutter on top; a bulb hangs under the shelf.
## 1.8 x 0.8, centred; its front (the drawers) faces +z.
static func _workbench() -> ArrayMesh:
	var k := _kit(0.35, 95)
	var up := Vector3(PI / 2, 0, 0)
	var green := Color(0.29, 0.35, 0.33)
	var face := green.lightened(0.08)
	var steel := Color(0.62, 0.63, 0.62)
	k.box(Vector3(0, 0.86, 0), Vector3(1.8, 0.06, 0.82), green)                  # the top
	k.box(Vector3(0, 0.86, 0.41), Vector3(1.82, 0.065, 0.02), steel.darkened(0.3))   # worn front edge
	for x in [-0.62, 0.62]:
		k.box(Vector3(x, 0.42, 0), Vector3(0.5, 0.82, 0.74), green)              # a bank of drawers
		for d in 3:
			var y := 0.16 + d * 0.24
			k.box(Vector3(x, y, 0.375), Vector3(0.44, 0.21, 0.02), face)
			k.box(Vector3(x, y + 0.04, 0.392), Vector3(0.16, 0.02, 0.02), steel)   # handle
	k.box(Vector3(0, 0.45, -0.34), Vector3(0.74, 0.8, 0.03), green.darkened(0.25))   # back panel
	k.box(Vector3(0, 0.12, 0.0), Vector3(0.74, 0.03, 0.03), steel.darkened(0.2))     # foot rail
	# The pegboard and its shelf.
	for x in [-0.78, 0.78]:
		k.box(Vector3(x, 1.33, -0.37), Vector3(0.05, 0.92, 0.05), STEEL)
	k.box(Vector3(0, 1.35, -0.38), Vector3(1.5, 0.74, 0.03), steel)
	for r in 5:
		for c in 12:
			k.box(Vector3(-0.66 + c * 0.12, 1.07 + r * 0.14, -0.364), Vector3(0.018, 0.018, 0.004), DARK)
	k.box(Vector3(0, 1.77, -0.3), Vector3(1.62, 0.03, 0.2), steel.darkened(0.1))
	# Tools on the board: a saw, two spanners, a pipe wrench, a square.
	k.box(Vector3(-0.52, 1.28, -0.355), Vector3(0.11, 0.5, 0.01), Color(0.82, 0.82, 0.8))
	k.box(Vector3(-0.52, 1.58, -0.355), Vector3(0.15, 0.11, 0.025), Color(0.5, 0.35, 0.2))
	for i in 2:
		k.box(Vector3(-0.2 + i * 0.09, 1.36 - i * 0.03, -0.355), Vector3(0.03, 0.26, 0.012), steel.darkened(0.15))
	k.box(Vector3(0.18, 1.3, -0.355), Vector3(0.05, 0.36, 0.025), Color(0.62, 0.16, 0.12))
	k.box(Vector3(0.18, 1.46, -0.35), Vector3(0.1, 0.05, 0.03), Color(0.62, 0.16, 0.12))
	k.box(Vector3(0.52, 1.46, -0.355), Vector3(0.22, 0.035, 0.012), Color(0.55, 0.4, 0.22))
	k.box(Vector3(0.425, 1.35, -0.355), Vector3(0.035, 0.22, 0.012), Color(0.55, 0.4, 0.22))
	# On the shelf: spray cans, a jug, a tin, an oil tray.
	k.cyl(Vector3(-0.66, 1.87, -0.3), 0.04, 0.17, Color(0.2, 0.5, 0.25), 8, up)
	k.box(Vector3(-0.52, 1.87, -0.3), Vector3(0.1, 0.17, 0.08), Color(0.15, 0.35, 0.75))
	k.cyl(Vector3(-0.1, 1.85, -0.3), 0.06, 0.13, DARK, 10, up)
	k.box(Vector3(0.38, 1.83, -0.3), Vector3(0.18, 0.08, 0.11), Color(0.8, 0.42, 0.12))
	k.box(Vector3(0.58, 1.84, -0.3), Vector3(0.1, 0.1, 0.07), Color(0.15, 0.35, 0.75))
	# On the bench: a red toolbox, a cutting board, a saw blade, a tin, a tray.
	k.box(Vector3(-0.58, 0.96, 0.02), Vector3(0.38, 0.14, 0.2), Color(0.6, 0.12, 0.1))
	k.box(Vector3(-0.58, 1.035, 0.02), Vector3(0.16, 0.02, 0.03), steel)
	k.box(Vector3(0.02, 0.895, 0.1), Vector3(0.5, 0.012, 0.32), Color(0.72, 0.58, 0.4))
	k.cyl(Vector3(-0.7, 0.895, 0.28), 0.14, 0.008, steel, 16, up)
	k.cyl(Vector3(0.28, 0.95, -0.18), 0.05, 0.12, RUST, 10, up)
	k.box(Vector3(0.56, 0.92, 0.02), Vector3(0.22, 0.06, 0.14), Color(0.8, 0.42, 0.12))
	k.cyl(Vector3(0.8, 0.98, -0.22), 0.035, 0.18, Color(0.2, 0.5, 0.25), 8, up)
	k.box(Vector3(0.0, 1.66, -0.2), Vector3(0.01, 0.2, 0.01), DARK)
	_bulb(k, Vector3(0.0, 1.53, -0.2))
	return k.mesh()


## The research desk (click it to open Research): a drafting table, its board
## tilted up on a braced X of steel legs, a blueprint pinned to it, a hand
## wheel to set the tilt and a lamp on an arm with a magnifier ring.
## About 1.2 x 0.9, centred; the board tilts up toward -z (its ledge at +z).
static func _drafting_table() -> ArrayMesh:
	var k := _kit(0.35, 96)
	var up := Vector3(PI / 2, 0, 0)
	var frame := Color(0.2, 0.25, 0.32)
	var steel := Color(0.55, 0.56, 0.55)
	# Legs: an X each side, feet along z, a stretcher between.
	for x in [-0.5, 0.5]:
		k.box(Vector3(x, 0.03, 0), Vector3(0.08, 0.06, 0.8), frame)
		k.box(Vector3(x, 0.42, 0), Vector3(0.06, 0.06, 0.95), frame, Vector3(0.95, 0, 0))
		k.box(Vector3(x, 0.42, 0), Vector3(0.06, 0.06, 0.95), frame, Vector3(-0.95, 0, 0))
		k.box(Vector3(x, 0.78, 0.0), Vector3(0.07, 0.07, 0.3), frame)
	k.box(Vector3(0, 0.3, 0), Vector3(1.0, 0.05, 0.05), frame)
	k.box(Vector3(0, 0.3, 0), Vector3(1.0, 0.03, 0.03), frame, Vector3(0.6, 0, 0))
	# The board: tilted toward the back, wood under a blueprint.
	var tilt := Vector3(0.42, 0, 0)   # its high edge at the back, the face toward the camera
	k.box(Vector3(0, 0.95, 0), Vector3(1.2, 0.05, 0.85), Color(0.42, 0.34, 0.26), tilt)
	k.box(Vector3(0, 0.98, 0.02), Vector3(0.95, 0.01, 0.62), Color(0.2, 0.42, 0.72), tilt)
	var b := Basis.from_euler(tilt)
	for i in 4:   # a blueprint's pale lines
		k.box(Vector3(0, 0.95, 0) + b * Vector3(-0.2 + i * 0.12, 0.044, 0.0), Vector3(0.014, 0.006, 0.5), Color(0.75, 0.85, 0.95), tilt)
	k.box(Vector3(0, 0.95, 0) + b * Vector3(0.0, 0.044, 0.12), Vector3(0.7, 0.006, 0.014), Color(0.75, 0.85, 0.95), tilt)
	k.box(Vector3(0, 0.95, 0) + b * Vector3(0.0, 0.03, 0.44), Vector3(1.22, 0.04, 0.04), steel.darkened(0.2), tilt)   # the ledge
	# The tilt wheel on the right side.
	k.cyl(Vector3(0.62, 0.72, 0.1), 0.16, 0.04, steel.darkened(0.3), 14, Vector3(0, PI / 2, 0))
	k.cyl(Vector3(0.62, 0.72, 0.1), 0.06, 0.06, steel, 10, Vector3(0, PI / 2, 0))
	# The lamp arm, from the back corner over the board, with its ring.
	k.box(Vector3(-0.55, 1.35, -0.3), Vector3(0.04, 0.6, 0.04), steel)
	k.box(Vector3(-0.32, 1.62, -0.18), Vector3(0.5, 0.035, 0.035), steel, Vector3(0, 0.5, 0.3))
	k.cyl(Vector3(-0.1, 1.5, -0.05), 0.12, 0.03, steel.darkened(0.2), 16, Vector3(1.0, 0, 0))
	k.cyl(Vector3(-0.1, 1.5, -0.05), 0.1, 0.032, Color(0.7, 0.85, 0.9), 16, Vector3(1.0, 0, 0))
	return k.mesh()


# --- Each base's landmark (bases.gd EXTRAS) ---------------------------------------
static var _extra_cache := {}

## The mesh for a landmark kind, made once.
static func extra(kind: String) -> ArrayMesh:
	if not _extra_cache.has(kind):
		var m: ArrayMesh
		match kind:
			"water_tower": m = _x_water_tower()
			"boxcar": m = _x_boxcar()
			"watchtower": m = _x_watchtower()
			"sandbags": m = _x_sandbags()
			"mast": m = _x_mast()
			"wreck": m = _x_wreck()
			"tyres": m = _x_tyres()
			"logs": m = _x_logs()
			"duckboards": m = _x_duckboards()
			_: m = _x_antlers()
		_extra_cache[kind] = m
	return _extra_cache[kind]


## A farm's water tower: four legs braced, a round wooden tank, a cone roof.
static func _x_water_tower() -> ArrayMesh:
	var k := _kit(0.4, 201)
	var up := Vector3(PI / 2, 0, 0)
	for sx in [-0.6, 0.6]:
		for sz in [-0.6, 0.6]:
			k.box(Vector3(sx, 1.3, sz), Vector3(0.1, 2.6, 0.1), LOG.darkened(0.1))
	for h in [0.8, 1.8]:
		k.box(Vector3(0, h, -0.6), Vector3(1.3, 0.06, 0.06), LOG)
		k.box(Vector3(0, h, 0.6), Vector3(1.3, 0.06, 0.06), LOG)
		k.box(Vector3(-0.6, h, 0), Vector3(0.06, 0.06, 1.3), LOG)
		k.box(Vector3(0.6, h, 0), Vector3(0.06, 0.06, 1.3), LOG)
	k.cyl(Vector3(0, 3.1, 0), 0.82, 1.0, PLANK, 14, up)
	for h in [2.75, 3.1, 3.45]:
		k.cyl(Vector3(0, h, 0), 0.84, 0.05, STEEL, 14, up)
	k.cyl(Vector3(0, 3.85, 0), 0.05, 0.5, OLD_PLANK, 14, up, 0.92)
	k.box(Vector3(0.7, 1.7, 0.7), Vector3(0.05, 2.4, 0.05), STEEL)   # ladder rails
	k.box(Vector3(0.85, 1.7, 0.55), Vector3(0.05, 2.4, 0.05), STEEL)
	return k.mesh()


## A rusted railway boxcar, off its wheels, its door slid half open.
static func _x_boxcar() -> ArrayMesh:
	var k := _kit(0.7, 202)
	var red := Color(0.42, 0.18, 0.12)
	k.box(Vector3(0, 1.05, 0), Vector3(3.3, 1.5, 1.3), red)
	k.box(Vector3(0, 1.84, 0), Vector3(3.36, 0.08, 1.36), red.darkened(0.25))
	for i in 9:
		k.box(Vector3(-1.6 + i * 0.4, 1.05, 0.66), Vector3(0.05, 1.5, 0.03), red.darkened(0.2))   # ribs
	k.box(Vector3(0.2, 0.95, 0.68), Vector3(0.9, 1.2, 0.04), red.lightened(0.08))                    # the door
	k.box(Vector3(-0.35, 0.95, 0.67), Vector3(0.2, 1.2, 0.02), DARK)                                  # the gap
	k.box(Vector3(0, 0.25, 0), Vector3(3.0, 0.2, 1.0), DARK)                                          # the frame
	for sx in [-1.1, 1.1]:
		for sz in [-0.45, 0.45]:
			k.cyl(Vector3(sx, 0.18, sz), 0.18, 0.12, STEEL, 10)
	return k.mesh()


## A watchtower: four posts, a railed platform, a little tin roof.
static func _x_watchtower() -> ArrayMesh:
	var k := _kit(0.4, 203)
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			k.box(Vector3(sx, 1.7, sz), Vector3(0.1, 3.4, 0.1), LOG)
	k.box(Vector3(0, 2.4, 0), Vector3(1.25, 0.08, 1.25), PLANK)
	for sz in [-0.58, 0.58]:
		k.box(Vector3(0, 2.85, sz), Vector3(1.2, 0.05, 0.05), LOG)
		k.box(Vector3(sz, 2.85, 0), Vector3(0.05, 0.05, 1.2), LOG)
	k.box(Vector3(0, 3.45, 0), Vector3(1.5, 0.05, 1.5), TIN, Vector3(0.12, 0, 0))
	k.box(Vector3(0.35, 1.2, 0.55), Vector3(0.05, 2.4, 0.05), STEEL)   # ladder
	return k.mesh()


## Two rows of sandbags, a low wall to duck behind.
static func _x_sandbags() -> ArrayMesh:
	var k := _kit(0.2, 204)
	for row in 3:
		for i in 6 - row % 2:
			var c := SANDBAG.lerp(SANDBAG.darkened(0.2), k.rng.randf())
			k.box(Vector3(-1.15 + i * 0.46 + (row % 2) * 0.23, 0.11 + row * 0.2, 0), Vector3(0.44, 0.2, 0.55), c, Vector3(0, k.rng.randf_range(-0.08, 0.08), 0))
	return k.mesh()


## A radio mast: a tall lattice, an aerial and guy wires to the ground.
static func _x_mast() -> ArrayMesh:
	var k := _kit(0.3, 205)
	var up := Vector3(PI / 2, 0, 0)
	for sx in [-0.18, 0.18]:
		for sz in [-0.18, 0.18]:
			k.box(Vector3(sx, 2.4, sz), Vector3(0.05, 4.8, 0.05), STEEL)
	for i in 12:
		k.box(Vector3(0, 0.2 + i * 0.4, 0.18), Vector3(0.38, 0.03, 0.03), STEEL, Vector3(0, 0, 0.6 if i % 2 == 0 else -0.6))
		k.box(Vector3(0.18, 0.2 + i * 0.4, 0), Vector3(0.03, 0.03, 0.38), STEEL, Vector3(0.6 if i % 2 == 0 else -0.6, 0, 0))
	k.cyl(Vector3(0, 5.3, 0), 0.02, 1.0, STEEL, 6, up)
	k.box(Vector3(0, 4.9, 0), Vector3(0.5, 0.04, 0.04), Color(0.7, 0.15, 0.1))
	return k.mesh()


## A burnt-out car: blackened body and cab, no wheels left.
static func _x_wreck() -> ArrayMesh:
	var k := _kit(0.8, 206)
	var burnt := Color(0.16, 0.14, 0.13)
	k.box(Vector3(0, 0.45, 0), Vector3(2.4, 0.5, 1.15), burnt)
	k.box(Vector3(-0.15, 0.9, 0), Vector3(1.2, 0.45, 1.05), burnt.lightened(0.05))
	k.box(Vector3(-0.15, 0.9, 0), Vector3(1.22, 0.3, 0.9), DARK)   # empty windows
	for sx in [-0.8, 0.8]:
		for sz in [-0.55, 0.55]:
			k.cyl(Vector3(sx, 0.14, sz), 0.14, 0.1, RUST, 8)
	return k.mesh()


## A stack of old tyres.
static func _x_tyres() -> ArrayMesh:
	var k := _kit(0.1, 207)
	var up := Vector3(PI / 2, 0, 0)
	for i in 4:
		k.cyl(Vector3(k.rng.randf_range(-0.04, 0.04), 0.12 + i * 0.22, k.rng.randf_range(-0.04, 0.04)), 0.4, 0.2, Color(0.08, 0.08, 0.09), 14, up)
	k.cyl(Vector3(0, 0.9, 0), 0.2, 0.02, DARK, 10, up)
	return k.mesh()


## Big logs from the mill, stacked between stakes.
static func _x_logs() -> ArrayMesh:
	var k := _kit(0.2, 208)
	for row in 2:
		for i in 3 - row:
			k.cyl(Vector3(0, 0.22 + row * 0.38, -0.4 + i * 0.4 + row * 0.2), 0.2, 2.2, LOG.lerp(PLANK, k.rng.randf() * 0.4), 9, Vector3(0, PI / 2, 0))
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx, 0.45, 0.5), Vector3(0.07, 0.9, 0.07), LOG.darkened(0.2))
		k.box(Vector3(sx, 0.45, -0.5), Vector3(0.07, 0.9, 0.07), LOG.darkened(0.2))
	return k.mesh()


## Duckboards over the marsh mud: planks on two runners, flat on the ground.
static func _x_duckboards() -> ArrayMesh:
	var k := _kit(0.3, 209)
	for sx in [-0.3, 0.3]:
		k.box(Vector3(sx, 0.03, 0), Vector3(0.06, 0.05, 3.0), OLD_PLANK.darkened(0.2))
	for i in 15:
		k.box(Vector3(0, 0.07, -1.4 + i * 0.2), Vector3(0.8, 0.03, 0.15), OLD_PLANK.lerp(PLANK, k.rng.randf() * 0.5), Vector3(0, k.rng.randf_range(-0.05, 0.05), 0))
	return k.mesh()


## A pair of antlers over the lodge's door.
static func _x_antlers() -> ArrayMesh:
	var k := _kit(0.1, 210)
	var bone := Color(0.78, 0.72, 0.6)
	k.box(Vector3(0, 1.75, 0), Vector3(0.24, 0.3, 0.06), PLANK.darkened(0.2))   # the plaque
	k.box(Vector3(0, 1.78, 0.06), Vector3(0.1, 0.12, 0.1), bone)
	for side in [-1.0, 1.0]:
		k.box(Vector3(side * 0.16, 1.92, 0.08), Vector3(0.03, 0.3, 0.03), bone, Vector3(0, 0, -side * 0.7))
		k.box(Vector3(side * 0.3, 2.08, 0.08), Vector3(0.025, 0.22, 0.025), bone, Vector3(0, 0, -side * 0.2))
		k.box(Vector3(side * 0.22, 2.1, 0.08), Vector3(0.02, 0.16, 0.02), bone, Vector3(0, 0, side * 0.3))
	return k.mesh()


## Split logs stacked between two stakes.
static func _woodpile() -> ArrayMesh:
	var k := _kit(0.2, 97)
	for row in 3:
		for i in 5 - row:
			var c := LOG.lerp(PLANK, k.rng.randf_range(0.0, 0.5))
			k.cyl(Vector3(-0.5 + i * 0.24 + row * 0.12, 0.12 + row * 0.21, 0), 0.11, 0.7, c, 7, Vector3.ZERO)
	for sx in [-0.7, 0.7]:
		k.box(Vector3(sx, 0.4, 0), Vector3(0.06, 0.8, 0.06), LOG.darkened(0.2))
	return k.mesh()


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


# --- The gate to the pass (posts 3.4 m apart, beam at 3.1 m: the army truck fits) ---
static func _gate() -> ArrayMesh:
	var k := _kit(0.4, 61)
	var up := Vector3(PI / 2, 0, 0)
	for sx in [-1, 1]:
		k.cyl(Vector3(sx * 1.7, 1.6, 0), 0.14, 3.3, LOG, 8, up)
		k.cyl(Vector3(sx * 1.7, 3.27, 0), 0.12, 0.06, LOG.darkened(0.2), 8, up)
		k.box(Vector3(sx * 1.45, 2.75, 0), Vector3(0.6, 0.09, 0.09), LOG.lightened(0.05), Vector3(0, 0, sx * 0.75))
	k.cyl(Vector3(0, 3.1, 0), 0.12, 4.0, LOG, 8, Vector3(0, PI / 2, 0))
	# A plank sign hung on ropes.
	for sx in [-0.45, 0.45]:
		k.box(Vector3(sx, 2.9, 0.05), Vector3(0.02, 0.3, 0.02), ROPE)
	k.box(Vector3(0, 2.7, 0.06), Vector3(1.2, 0.22, 0.04), PLANK)
	k.box(Vector3(0, 2.7, 0.085), Vector3(0.9, 0.05, 0.01), Color(0.75, 0.2, 0.12))
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
