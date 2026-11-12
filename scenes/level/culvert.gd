# The end of a lane: a concrete headwall in an earth bank, with big sewer pipes
# through it that the dead come shambling out of. Built in code: the wall with
# its coping and angled wing walls, the bank behind, each pipe's thick concrete
# ring and dark throat with a grate (bent and broken in the middle, where they
# push through), ivy and weeds over the concrete, a cracked apron, rubble, and
# a burning barrel. One per lane (see level.gd), facing down the lane.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Guns = preload("res://scenes/actors/guns.gd")
const Terrain = preload("res://scripts/terrain.gd")
const FIRE := preload("res://scenes/fx/fire.tscn")

const CONCRETE := Color(0.5, 0.49, 0.52)
const DARK_CONCRETE := Color(0.37, 0.36, 0.4)
const EARTH := Color(0.33, 0.36, 0.22)
const IVY := [Color(0.24, 0.42, 0.2), Color(0.3, 0.5, 0.22), Color(0.2, 0.35, 0.18), Color(0.36, 0.52, 0.26)]
const WALL_H := 2.9        # headwall height
const BANK := 4.5          # how far back the earth bank runs
const THROAT_Z := -0.62    # where the black of a pipe's throat starts (behind the wall face)

var side := 0
var plug: MeshInstance3D    # bricks and boards over the pipes, for a level where this lane is shut

static var _mat: StandardMaterial3D
static var _void: StandardMaterial3D


## Builds the culvert for lane s, in this node's parent's space (the level).
func build(s: int) -> void:
	side = s
	var L: Dictionary = D.LANES[s]
	var u0: float = L["u0"] - 2.0
	var u1: float = L["u1"] + 2.0
	# This node sits on the headwall's face line, at the lane's middle, facing
	# down the lane (+z here is toward the wall).
	var mid := (u0 + u1) / 2.0
	var at := _lane(mid, D.PIPE_V)
	var n: Vector2 = L["n"]
	var ground := Terrain.sample(at.x, at.y)
	transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(at.x, ground - 0.15, at.y))
	var half := (u1 - u0) / 2.0
	# Local x runs across the lane; the lane's u axis may point either way.
	var t: Vector2 = L["t"]
	var flip := 1.0 if Vector2(n.y, -n.x).dot(t) > 0.0 else -1.0
	var pipes: Array = []
	for pu in D.PIPES[s]:
		pipes.append((pu - mid) * flip)

	var k := Guns.Kit.new()
	k.rng.seed = 7 + s * 31
	k.wear = 0.6
	k.stain = Color(0.36, 0.38, 0.3)    # damp grime
	k.fade = Color(0.75, 0.74, 0.7)     # sun-bleached
	_headwall(k, half, pipes)
	_bank(k, half)
	_apron(k, half, pipes)
	for px in pipes:
		_pipe(k, px)
	_ivy(k, half, pipes)
	_mesh(k.mesh(), _material())
	# Each pipe's dark throat: unlit, so it reads as a black hole at any hour.
	# The dead step out of it (they appear just in front, behind the grate).
	var throat := Guns.Kit.new()
	for px in pipes:
		throat.cyl(Vector3(px, D.PIPE_R - 0.05, THROAT_Z), D.PIPE_R + 0.02, 0.1, Color(0.02, 0.02, 0.025), 18, Vector3.ZERO)
	_mesh(throat.mesh(), _void_material(), false)
	# Bricked up and boarded over: shown when this lane stays shut (see sealed()).
	var pk := Guns.Kit.new()
	pk.rng.seed = 300 + s
	pk.wear = 0.5
	pk.stain = Color(0.3, 0.3, 0.28)
	for px in pipes:
		var r: float = D.PIPE_R
		var cy := r - 0.05
		var rows := int((r * 2.0) / 0.22)
		for row in rows:
			var y := cy - r + 0.11 + row * 0.22
			var half_w := sqrt(maxf(0.0, r * r - pow(y - cy, 2.0)))
			var x: float = px - half_w + (0.15 if row % 2 else 0.0)
			while x < px + half_w - 0.05:
				var bw: float = minf(0.4, px + half_w - x)
				var c := CONCRETE.lerp(Color(0.55, 0.38, 0.3), pk.rng.randf_range(0.0, 0.6))
				pk.box(Vector3(x + bw / 2.0, y, -0.25), Vector3(bw - 0.03, 0.19, 0.3), c)
				x += bw
		for b in 3:   # boards nailed across
			var y := cy - 0.5 + b * 0.5
			pk.box(Vector3(px, y, 0.02), Vector3(r * 2.2, 0.16, 0.05), Color(0.4, 0.3, 0.2) * pk.rng.randf_range(0.8, 1.05), Vector3(0, 0, pk.rng.randf_range(-0.2, 0.2)))
	plug = MeshInstance3D.new()
	plug.mesh = pk.mesh()
	plug.material_override = _material()
	plug.visible = false
	add_child(plug)
	# A burning barrel by the first pipe, as in someone's last stand.
	var bx: float = pipes[0] - D.PIPE_R - 1.1
	var barrel := Guns.Kit.new()
	barrel.wear = 0.8
	barrel.rng.seed = 99 + s
	barrel.cyl(Vector3(bx, 0.55, 0.9), 0.28, 0.9, Color(0.25, 0.24, 0.24), 10, Vector3(PI / 2, 0, 0))
	for y in [0.3, 0.8]:
		barrel.cyl(Vector3(bx, y, 0.9), 0.295, 0.05, Color(0.18, 0.17, 0.17), 10, Vector3(PI / 2, 0, 0))
	_mesh(barrel.mesh(), _material())
	var fire: Node3D = FIRE.instantiate()
	fire.radius = 0.22
	fire.scorch = false
	fire.light_energy = 1.8
	fire.position = Vector3(bx, 1.02, 0.9)
	add_child(fire)


## Shows the pipes bricked up (true) or open.
func sealed(on: bool) -> void:
	if plug != null:
		plug.visible = on


func _lane(u: float, v: float) -> Vector2:
	return Vector2(D.LANES[side]["o"]) + D.LANES[side]["t"] * u + D.LANES[side]["n"] * v


func _mesh(m: Mesh, mat: Material, shadows := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The wall: slabs between and around the pipes (leaving round-ish holes),
## a coping strip on top, panel seams, and wing walls angled back.
func _headwall(k: Guns.Kit, half: float, pipes: Array) -> void:
	var r: float = D.PIPE_R + 0.22
	var xs := [-half]
	for px in pipes:
		xs.append(px - r)
		xs.append(px + r)
	xs.append(half)
	# Solid stretches between the pipes.
	for i in range(0, xs.size(), 2):
		var a: float = xs[i]
		var b: float = xs[i + 1]
		k.box(Vector3((a + b) / 2, WALL_H / 2, -0.25), Vector3(b - a, WALL_H, 0.5), CONCRETE)
	# Over and under each pipe: the wall closes in around its ring.
	for px in pipes:
		var top := D.PIPE_R * 2.0 + 0.1
		k.box(Vector3(px, (top + WALL_H) / 2, -0.25), Vector3(r * 2.0, WALL_H - top, 0.5), CONCRETE)
		for sx in [-1, 1]:   # the corners the ring doesn't fill
			k.box(Vector3(px + sx * r * 0.82, D.PIPE_R * 1.75, -0.25), Vector3(r * 0.4, D.PIPE_R * 0.6, 0.5), CONCRETE)
			k.box(Vector3(px + sx * r * 0.82, D.PIPE_R * 0.22, -0.25), Vector3(r * 0.4, D.PIPE_R * 0.5, 0.5), CONCRETE)
	# Coping along the top, and vertical seams between cast panels.
	k.box(Vector3(0, WALL_H + 0.08, -0.2), Vector3(half * 2.0 + 0.3, 0.2, 0.75), DARK_CONCRETE.lightened(0.15))
	var x := -half + 1.6
	while x < half - 0.5:
		var clear := true
		for px in pipes:
			if absf(x - px) < r + 0.2:
				clear = false
		if clear:
			k.box(Vector3(x, WALL_H / 2, 0.005), Vector3(0.04, WALL_H - 0.1, 0.02), DARK_CONCRETE)
		x += 1.6
	# Wing walls, sloping down as they angle back into the bank.
	for sxi in [-1, 1]:
		var sx := float(sxi)
		var base := Vector3(sx * half, 0, 0)
		var dirv := Vector3(sx * 0.55, 0, 0.85).normalized()
		var len := 3.2
		var c := base + dirv * len * 0.5
		var w := Vector3(-dirv.z, 0, dirv.x) * 0.25 * sx
		var centre := c + Vector3(0, WALL_H * 0.3, 0)
		var a0 := base + w
		var a1 := base - w
		var b0 := base + dirv * len + w
		var b1 := base + dirv * len - w
		var a0t := a0 + Vector3(0, WALL_H, 0)
		var a1t := a1 + Vector3(0, WALL_H, 0)
		var b0t := b0 + Vector3(0, 0.4, 0)
		var b1t := b1 + Vector3(0, 0.4, 0)
		k.poly([a0, b0, b0t, a0t], CONCRETE, centre)
		k.poly([a1, b1, b1t, a1t], CONCRETE, centre)
		k.poly([a0t, b0t, b1t, a1t], DARK_CONCRETE.lightened(0.15), centre)
		k.poly([b0, b1, b1t, b0t], CONCRETE, centre)
		k.poly([a0, a1, a1t, a0t], CONCRETE, centre)


## The earth bank behind the wall, rising to its top and rolling back.
func _bank(k: Guns.Kit, half: float) -> void:
	var w := half + 3.5
	var h := WALL_H + 0.25
	var rows := [[-0.5, h], [-2.0, h + 0.3], [-BANK, h - 0.2], [-BANK - 3.0, 0.0]]
	var segs := 8
	for i in rows.size() - 1:
		for j in segs:
			var xa := -w + 2.0 * w * j / segs
			var xb := -w + 2.0 * w * (j + 1) / segs
			var za: float = rows[i][0]
			var zb: float = rows[i + 1][0]
			var ha: float = rows[i][1] + sin(xa * 1.3 + i) * 0.15
			var hb: float = rows[i + 1][1] + sin(xa * 0.9 + i * 2.0) * 0.2
			var hc: float = rows[i + 1][1] + sin(xb * 0.9 + i * 2.0) * 0.2
			var hd: float = rows[i][1] + sin(xb * 1.3 + i) * 0.15
			k.poly([Vector3(xa, ha, za), Vector3(xa, hb, zb), Vector3(xb, hc, zb), Vector3(xb, hd, za)],
				EARTH.lerp(IVY[(i + j) % IVY.size()], 0.35), Vector3((xa + xb) / 2, -5.0, (za + zb) / 2))
	# The bank's ends, sloping down to the ground beside the wing walls.
	for sx in [-1, 1]:
		var x0: float = sx * w
		k.poly([Vector3(x0, 0, -0.5), Vector3(x0, h, -0.5), Vector3(x0, h - 0.2, -BANK), Vector3(x0, 0, -BANK - 3.0)],
			EARTH, Vector3(0, h / 2, -BANK / 2))
		k.poly([Vector3(x0, 0, -0.5), Vector3(sx * (half + 2.3), 0, 2.6), Vector3(x0, h, -0.5)],
			EARTH.darkened(0.1), Vector3(sx * (half - 2.0), 0.5, 0.0))


## A cracked concrete apron in front, with rubble scattered on it.
func _apron(k: Guns.Kit, half: float, pipes: Array) -> void:
	var slabs := int(ceil(half * 2.0 / 1.5))
	for i in slabs:
		for j in 2:
			var x := -half + (i + 0.5) * (half * 2.0 / slabs)
			var tilt := Vector3(k.rng.randf_range(-0.02, 0.02), 0, k.rng.randf_range(-0.02, 0.02))
			k.box(Vector3(x, 0.12, 0.6 + j * 1.25), Vector3(half * 2.0 / slabs - 0.05, 0.18, 1.2), CONCRETE.darkened(0.08), tilt)
	for i in 14:
		var px: float = pipes[k.rng.randi() % pipes.size()]
		var p := Vector3(px + k.rng.randf_range(-2.4, 2.4), 0.24, k.rng.randf_range(0.3, 2.8))
		var sz := k.rng.randf_range(0.08, 0.22)
		k.box(p, Vector3(sz, sz * 0.6, sz * 0.9), DARK_CONCRETE, Vector3(0, k.rng.randf() * TAU, k.rng.randf_range(-0.4, 0.4)))


## A pipe: a thick concrete ring standing out of the wall, its bore running
## back into the bank, and a grate of bars, the middle ones bent or gone.
func _pipe(k: Guns.Kit, px: float) -> void:
	var r: float = D.PIPE_R
	var cy := r - 0.05
	var segs := 18
	var thick := 0.22
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var am := (a0 + a1) / 2
		var mid := Vector3(px + cos(am) * (r + thick / 2), cy + sin(am) * (r + thick / 2), -0.1)
		var len := 2.0 * (r + thick) * sin(PI / segs) + 0.02
		var col := CONCRETE.lightened(0.08) if i % 5 else CONCRETE.darkened(0.05)
		k.box(mid, Vector3(len, thick, 1.15), col, Vector3(0, 0, am + PI / 2))
		# A lip around the mouth.
		var lip := Vector3(px + cos(am) * (r + thick + 0.05), cy + sin(am) * (r + thick + 0.05), 0.42)
		k.box(lip, Vector3(len + 0.03, 0.12, 0.12), CONCRETE.lightened(0.12), Vector3(0, 0, am + PI / 2))
	# The grate, set a little way in.
	var bars := 7
	for b in bars:
		var bxp := px + (b - (bars - 1) / 2.0) * (r * 2.0 / (bars + 1))
		var h := sqrt(maxf(0.0, r * r - pow(bxp - px, 2.0))) * 2.0 - 0.05
		var middle := absf(b - (bars - 1) / 2.0) <= 1.0
		var bar_col := Color(0.2, 0.18, 0.17)
		if middle and b != (bars - 1) / 2:
			# Bent out and down, wrenched loose.
			k.box(Vector3(bxp, cy - h * 0.25, -0.15), Vector3(0.06, h * 0.45, 0.06), bar_col)
			k.box(Vector3(bxp + (bxp - px) * 0.6, cy - 0.25, 0.35), Vector3(0.06, 0.06, h * 0.55), bar_col, Vector3(0.5, (bxp - px) * 0.8, 0))
		elif middle:
			continue    # torn out altogether
		else:
			k.box(Vector3(bxp, cy, -0.35), Vector3(0.07, h, 0.07), bar_col)
	k.box(Vector3(px, cy + r * 0.55, -0.35), Vector3(r * 1.7, 0.07, 0.07), Color(0.2, 0.18, 0.17))


## Ivy hanging down the wall and over the pipes, and weeds at its foot.
func _ivy(k: Guns.Kit, half: float, pipes: Array) -> void:
	var rng := k.rng
	# Curtains spilling over the coping.
	for c in 9:
		var cx := rng.randf_range(-half + 0.4, half - 0.4)
		var drop := rng.randf_range(0.6, 1.9)
		var n := int(drop / 0.12)
		for i in n:
			var y := WALL_H + 0.1 - i * 0.12
			for j in 3:
				var p := Vector3(cx + rng.randf_range(-0.35, 0.35) * (1.0 - float(i) / n * 0.5), y + rng.randf_range(-0.05, 0.05), 0.05 + rng.randf_range(0.0, 0.08))
				var s := rng.randf_range(0.09, 0.16)
				k.box(p, Vector3(s, s * 0.8, 0.04), IVY[rng.randi() % IVY.size()], Vector3(0, 0, rng.randf() * TAU))
	# Tufts along the top of the bank and the coping.
	for i in 40:
		var p := Vector3(rng.randf_range(-half - 2.0, half + 2.0), WALL_H + 0.25 + rng.randf_range(0.0, 0.2), rng.randf_range(-2.5, -0.1))
		var s := rng.randf_range(0.2, 0.45)
		k.box(p, Vector3(s, s * 0.6, s), IVY[rng.randi() % IVY.size()], Vector3(rng.randf() * 0.5, rng.randf() * TAU, 0))
	# Weeds and shrubs along the foot of the wall, thick at the corners.
	for i in 34:
		var x := rng.randf_range(-half - 1.5, half + 1.5)
		var clear := false
		for px in pipes:
			if absf(x - px) < D.PIPE_R * 0.9:
				clear = true   # the dead have trampled the pipe mouths bare
		if clear:
			continue
		var s := rng.randf_range(0.15, 0.5)
		k.box(Vector3(x, s * 0.4, rng.randf_range(0.05, 0.7)), Vector3(s, s * 0.8, s), IVY[rng.randi() % IVY.size()].darkened(0.1),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		for b in 3:   # grass blades
			var bx := x + rng.randf_range(-0.2, 0.2)
			k.box(Vector3(bx, 0.3, rng.randf_range(0.1, 0.6)), Vector3(0.03, rng.randf_range(0.3, 0.6), 0.03), IVY[1].lightened(0.1),
				Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.95
	return _mat


static func _void_material() -> StandardMaterial3D:
	if _void == null:
		_void = StandardMaterial3D.new()
		_void.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_void.albedo_color = Color(0.015, 0.015, 0.02)
		_void.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _void
