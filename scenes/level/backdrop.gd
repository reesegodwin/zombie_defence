# What lies behind the base where there are no mountains (the biome's "back",
# D.BIOMES): a barrier that keeps the dead from coming round the back, with an
# opening where the road leaves through the gate, and the country beyond it.
#   "fence"    (the farmlands): a tall corrugated metal fence, and fields with
#              barns, silos and hay bales beyond it.
#   "wreckage" (the wastes): concrete wall panels and car pile-ups, and the
#              shells of ruined buildings beyond.
# Some bases add a landmark of their own out there (LANDMARKS): Harvest Farm's
# old Victorian farmhouse, Tank Farm's great fuel tanks. Everything is low
# close behind the base, so it never hides the yard from the camera. Built in
# code from the same Kit as the other props (guns.gd), one mesh per kind.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Guns = preload("res://scenes/actors/guns.gd")
const Culvert = preload("res://scenes/level/culvert.gd")
const Mountains = preload("res://scenes/level/mountains.gd")
const BaseProps = preload("res://scenes/level/base_props.gd")

const SPAN := Vector2(-70.0, 92.0)   # x range the barrier runs across
const ROAD_HALF := 2.2              # the opening for the road out (metres either side of it)

## Each base's own landmark behind it: [kind, x, z, yaw].
const LANDMARKS := {
	"farm": [["farmhouse", 1.0, 38.0, 0.35]],
	"fueldepot": [["fuel_tanks", -14.0, 40.0, 0.3]],
}

var kind := ""
var _base := ""


## Builds the backdrop for a biome's back ("fence", "wreckage"; anything
## else: nothing, the mountains are there instead) and the base's landmark.
func build(back: String, base_key: String) -> void:
	if back == kind and base_key == _base:
		return
	kind = back
	_base = base_key
	for c in get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(back)
	if back in ["fence", "wreckage"]:
		_add(_road())
	match back:
		"fence":
			_add(_fence_line(rng))
			_add(_scatter(rng, ["barn", "silo", "bales", "bales", "tree"], 26))
		"wreckage":
			_add(_wall_line(rng))
			_add(_scatter(rng, ["ruin", "ruin", "wreck", "pileup", "wall_piece"], 30))
	for lm in LANDMARKS.get(base_key, []):
		var mi := _add(_landmark(lm[0]))
		mi.position = Vector3(lm[1], Terrain.sample(lm[1], lm[2]), lm[2])
		mi.rotation.y = lm[3]


func _add(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Culvert._material()
	add_child(mi)
	return mi


## The road out through the gate (where the mountains have their pass): gravel
## laid along the scavengers' and the truck's way.
func _road() -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.3
	k.rng.seed = 305
	var pts: Array = [Vector2(11.2, D.BASE_Y1 - 0.2)]
	for p in D.PASS_PATH:
		if p.y > D.BASE_Y1:
			pts.append(p)
	pts.append(Vector2(D.PASS_PATH[-1].x, 70.0))
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var mid := (a + b) * 0.5
		var y := Terrain.sample(mid.x, mid.y)
		k.box(Vector3(mid.x, y + 0.012, mid.y), Vector3(2.6, 0.03, a.distance_to(b) + 0.6), Color(0.42, 0.38, 0.33), Vector3(0, atan2(b.x - a.x, b.y - a.y), 0))
	return k.mesh()


## The barrier's line: just behind where the mountains would start.
static func line_z(x: float) -> float:
	return Mountains.start_z(x) + 0.6


## True near the road out through the gate (kept clear).
static func on_road(x: float, z: float) -> bool:
	var pts: Array = D.PASS_PATH
	var best := INF
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var t := clampf((Vector2(x, z) - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, Vector2(x, z).distance_to(a.lerp(b, t)))
	if z > pts[-1].y:
		best = minf(best, absf(x - pts[-1].x))
	return best < ROAD_HALF


## A tall corrugated metal fence on posts, in panels, open where the road goes.
func _fence_line(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.6
	k.rng.seed = 301
	var tin := Color(0.55, 0.56, 0.54)
	var x := SPAN.x
	while x < SPAN.y:
		var x2 := x + 2.4
		var z1 := line_z(x)
		var z2 := line_z(x2)
		var mid := Vector2((x + x2) / 2.0, (z1 + z2) / 2.0)
		if not on_road(mid.x, mid.y):
			var y0 := Terrain.sample(mid.x, mid.y)
			var yaw := -atan2(z2 - z1, x2 - x)
			var c := tin.lerp(Color(0.5, 0.36, 0.26), rng.randf() * 0.5)   # some panels rusted
			var h := 2.2 if mid.y < 34.0 else 2.8
			k.box(Vector3(mid.x, y0 + h / 2.0, mid.y), Vector3(2.45, h, 0.06), c, Vector3(0, yaw, 0))
			for r in 4:   # the corrugations
				var off := Vector3(-0.9 + r * 0.6, 0, 0).rotated(Vector3.UP, yaw)
				k.box(Vector3(mid.x, y0 + h / 2.0, mid.y) + off + Vector3(0, 0, 0.0), Vector3(0.08, h, 0.1), c.darkened(0.15), Vector3(0, yaw, 0))
			k.box(Vector3(x, y0 + h / 2.0 + 0.1, z1), Vector3(0.12, h + 0.2, 0.12), Color(0.3, 0.3, 0.3))   # post
		x = x2
	return k.mesh()


## Concrete wall panels with car pile-ups heaped along them, open where the
## road goes.
func _wall_line(rng: RandomNumberGenerator) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.7
	k.rng.seed = 302
	var concrete := Color(0.52, 0.51, 0.49)
	var x := SPAN.x
	var n := 0
	while x < SPAN.y:
		var x2 := x + 2.6
		var z1 := line_z(x)
		var z2 := line_z(x2)
		var mid := Vector2((x + x2) / 2.0, (z1 + z2) / 2.0)
		if not on_road(mid.x, mid.y):
			var y0 := Terrain.sample(mid.x, mid.y)
			var yaw := -atan2(z2 - z1, x2 - x)
			var h := 2.0 if mid.y < 34.0 else 2.7
			k.box(Vector3(mid.x, y0 + h / 2.0, mid.y), Vector3(2.55, h, 0.3), concrete.darkened(rng.randf() * 0.15), Vector3(0, yaw, rng.randf_range(-0.02, 0.02)))
			k.box(Vector3(mid.x, y0 + 0.15, mid.y), Vector3(2.6, 0.3, 0.6), concrete.darkened(0.2), Vector3(0, yaw, 0))   # footing
			n += 1
			if n % 5 == 2 and mid.y > 31.0:
				# A heap of wrecked cars against the wall, the far side.
				for c in 3:
					var col: Color = [Color(0.42, 0.18, 0.14), Color(0.25, 0.3, 0.38), Color(0.6, 0.58, 0.5), Color(0.2, 0.2, 0.2)][rng.randi() % 4]
					var p := Vector3(mid.x + rng.randf_range(-1.0, 1.0), y0 + 0.45 + (0.8 if c == 2 else 0.0), mid.y + 1.2 + rng.randf_range(-0.3, 0.4))
					var rot := Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
					k.box(p, Vector3(1.9, 0.5, 0.95), col, rot)
					k.box(p + Basis.from_euler(rot) * Vector3(-0.1, 0.4, 0), Vector3(1.0, 0.35, 0.85), col.darkened(0.15), rot)
		x = x2
	return k.mesh()


## The country beyond the barrier: kinds picked from the list, scattered on
## the far side of it, kept off the road and low near the base.
func _scatter(rng: RandomNumberGenerator, kinds: Array, count: int) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.5
	k.rng.seed = 303
	var placed := 0
	var tries := 0
	while placed < count and tries < 600:
		tries += 1
		var x := rng.randf_range(-40.0, 62.0)
		var z := line_z(x) + rng.randf_range(4.0, 22.0)
		if on_road(x, z) or absf(x - D.PASS_PATH[-1].x) < 5.0:
			continue
		var what: String = kinds[rng.randi() % kinds.size()]
		# Nothing tall in the camera's line to the yard (it looks from the
		# south-east, so behind and to the right of the base).
		var near_base := z < D.BASE_Y1 + 16.0 and x > D.BASE_X0 - 8.0 and x < D.BASE_X1 + 16.0
		if near_base and what in ["barn", "silo", "ruin", "tree"]:
			continue
		_piece(k, what, Vector3(x, Terrain.sample(x, z), z), rng.randf() * TAU, rng)
		placed += 1
	return k.mesh()


static func _piece(k: Guns.Kit, what: String, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r := Vector3(0, yaw, 0)
	match what:
		"barn":
			var red := Color(0.5, 0.17, 0.12)
			k.box(at + Vector3(0, 1.5, 0), Vector3(4.0, 3.0, 3.2) * Vector3(1, 1, 1), red, r)
			k.box(at + b * Vector3(0, 3.35, -0.85), Vector3(4.1, 0.12, 1.9), Color(0.3, 0.3, 0.3), Vector3(0.62, yaw, 0))
			k.box(at + b * Vector3(0, 3.35, 0.85), Vector3(4.1, 0.12, 1.9), Color(0.3, 0.3, 0.3), Vector3(-0.62, yaw, 0))
			k.box(at + b * Vector3(0, 1.1, 1.62), Vector3(1.6, 2.2, 0.04), Color(0.85, 0.82, 0.75), r)   # the big doors' white frame
			k.box(at + b * Vector3(0, 1.1, 1.64), Vector3(1.4, 2.0, 0.04), red.darkened(0.25), r)
		"silo":
			var up := Vector3(PI / 2, 0, 0)
			k.cyl(at + Vector3(0, 3.0, 0), 1.0, 6.0, Color(0.68, 0.68, 0.66), 14, up)
			k.cyl(at + Vector3(0, 6.3, 0), 1.0, 0.6, Color(0.6, 0.6, 0.58), 14, up, 0.15)
			for h in [1.5, 3.0, 4.5]:
				k.cyl(at + Vector3(0, h, 0), 1.02, 0.06, Color(0.45, 0.45, 0.43), 14, up)
		"bales":
			for i in 3:
				var p := at + b * Vector3(-1.2 + i * 1.2, 0.55, rng.randf_range(-0.3, 0.3))
				k.cyl(p, 0.55, 1.1, Color(0.78, 0.65, 0.35).darkened(rng.randf() * 0.15), 12, Vector3(0, yaw + PI / 2, 0))
		"tree":
			k.box(at + Vector3(0, 1.0, 0), Vector3(0.25, 2.0, 0.25), Color(0.3, 0.22, 0.15))
			k.cyl(at + Vector3(0, 2.6, 0), 1.3, 1.6, Color(0.55, 0.32, 0.12).lerp(Color(0.65, 0.5, 0.15), rng.randf()), 8, Vector3(PI / 2, 0, 0), 0.35)
		"ruin":
			var grey := Color(0.48, 0.46, 0.44)
			var w := rng.randf_range(4.0, 6.0)
			var h := rng.randf_range(3.0, 5.0)
			k.box(at + b * Vector3(0, h / 2.0, -1.6), Vector3(w, h, 0.25), grey, r)            # back wall
			k.box(at + b * Vector3(-w / 2.0, h * 0.35, 0), Vector3(0.25, h * 0.7, 3.2), grey.darkened(0.08), r)   # side, broken down
			k.box(at + b * Vector3(w / 2.0, h * 0.5, 0), Vector3(0.25, h, 3.2), grey.darkened(0.04), r)
			for i in 3:
				k.box(at + b * Vector3(-w / 2.0 + 1.0 + i * (w - 2.0) / 2.0, h * 0.62, -1.47), Vector3(0.6, 0.8, 0.04), Color(0.06, 0.06, 0.07), r)   # windows
			k.box(at + b * Vector3(0.5, 0.25, 0.6), Vector3(1.6, 0.5, 1.2), grey.darkened(0.2), Vector3(0.2, yaw + 0.5, 0.1))   # rubble
		"wreck":
			var c: Color = [Color(0.42, 0.18, 0.14), Color(0.25, 0.3, 0.38), Color(0.2, 0.2, 0.2)][rng.randi() % 3]
			k.box(at + Vector3(0, 0.45, 0), Vector3(2.0, 0.5, 1.0), c, r)
			k.box(at + b * Vector3(-0.15, 0.85, 0), Vector3(1.0, 0.35, 0.9), c.darkened(0.15), r)
		"pileup":
			for i in 3:
				var c2: Color = [Color(0.42, 0.18, 0.14), Color(0.25, 0.3, 0.38), Color(0.6, 0.58, 0.5)][i]
				var rot := Vector3(rng.randf_range(-0.4, 0.4), yaw + i * 0.7, rng.randf_range(-0.3, 0.3))
				k.box(at + Vector3(i * 0.5 - 0.5, 0.45 + (0.8 if i == 2 else 0.0), 0), Vector3(1.9, 0.5, 0.95), c2, rot)
		"wall_piece":
			k.box(at + Vector3(0, 1.0, 0), Vector3(2.6, 2.0, 0.3), Color(0.5, 0.49, 0.47), Vector3(0.05, yaw, 0.12))


## A base's own landmark behind it.
static func _landmark(what: String) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.6
	k.rng.seed = 304
	match what:
		"farmhouse":
			_farmhouse(k)
		"fuel_tanks":
			_fuel_tanks(k)
	return k.mesh()


## The old Victorian farmhouse: two storeys of grey-green clapboard on a
## concrete footing, a wraparound porch on turned posts, steep gables and a
## rusty red tin roof, two chimneys.
static func _farmhouse(k: Guns.Kit) -> void:
	var siding := Color(0.55, 0.6, 0.55)
	var trim := Color(0.86, 0.85, 0.8)
	var roof := Color(0.5, 0.2, 0.13)
	var concrete := Color(0.5, 0.5, 0.48)
	k.box(Vector3(0, 0.3, 0), Vector3(7.4, 0.6, 6.2), concrete)                     # footing and porch floor
	k.box(Vector3(0, 2.2, -0.6), Vector3(5.0, 3.2, 4.2), siding)                    # ground floor
	k.box(Vector3(0, 4.9, -0.6), Vector3(4.6, 2.2, 3.8), siding.darkened(0.05))     # upstairs
	for i in 12:   # the clapboard lines
		k.box(Vector3(0, 0.9 + i * 0.45, 1.52), Vector3(5.02, 0.03, 0.01), siding.darkened(0.15))
	# The gable roof, its ridge across, a front gable.
	k.box(Vector3(0, 6.6, -1.6), Vector3(5.2, 0.12, 2.6), roof, Vector3(0.72, 0, 0))
	k.box(Vector3(0, 6.6, 0.4), Vector3(5.2, 0.12, 2.6), roof, Vector3(-0.72, 0, 0))
	k.box(Vector3(-1.2, 6.1, 1.25), Vector3(1.8, 1.6, 0.12), trim, Vector3(0, 0, 0))   # the front gable's face
	k.box(Vector3(-1.2, 6.5, 1.2), Vector3(1.0, 0.12, 1.4), roof, Vector3(0, 0, 0.75))
	k.box(Vector3(-1.2, 6.5, 1.2), Vector3(1.0, 0.12, 1.4), roof, Vector3(0, 0, -0.75))
	# The wraparound porch: a tin roof on turned white posts.
	k.box(Vector3(0, 3.95, 2.05), Vector3(7.2, 0.1, 1.8), roof.darkened(0.1), Vector3(-0.15, 0, 0))
	for i in 6:
		var x := -3.4 + i * 1.36
		k.box(Vector3(x, 2.2, 2.85), Vector3(0.14, 3.2, 0.14), trim)
	k.box(Vector3(0, 3.7, 2.85), Vector3(7.0, 0.12, 0.08), trim)                    # the gingerbread rail
	# Windows and the door.
	for x in [-1.6, 1.6]:
		k.box(Vector3(x, 2.4, 1.52), Vector3(0.9, 1.5, 0.04), trim)
		k.box(Vector3(x, 2.4, 1.54), Vector3(0.7, 1.3, 0.04), Color(0.08, 0.09, 0.1))
		k.box(Vector3(x, 4.9, 1.32), Vector3(0.8, 1.1, 0.04), trim)
		k.box(Vector3(x, 4.9, 1.34), Vector3(0.6, 0.9, 0.04), Color(0.08, 0.09, 0.1))
	k.box(Vector3(0, 2.0, 1.53), Vector3(0.9, 2.0, 0.04), Color(0.35, 0.27, 0.2))
	for x in [-1.8, 1.4]:
		k.box(Vector3(x, 7.4, -0.8), Vector3(0.5, 1.4, 0.5), Color(0.45, 0.45, 0.44))   # chimneys
	k.box(Vector3(2.9, 0.35, 3.4), Vector3(1.0, 0.3, 0.8), concrete.darkened(0.1))      # the steps


## Tank Farm's great tanks: two round tanks with domed tops on a walled
## concrete pad, a pipe between them and a little control hut.
static func _fuel_tanks(k: Guns.Kit) -> void:
	var up := Vector3(PI / 2, 0, 0)
	# (Built at 80% scale: big, but not a wall in front of the camera.)
	var tank := Color(0.72, 0.71, 0.66)
	var pad := Color(0.45, 0.45, 0.43)
	k.box(Vector3(0, 0.15, 0), Vector3(14.0, 0.3, 7.5), pad)
	for side in [Vector3(0, 0.6, 3.7), Vector3(0, 0.6, -3.7)]:
		k.box(side, Vector3(14.0, 0.9, 0.25), pad.darkened(0.15))
	for side in [Vector3(7.0, 0.6, 0), Vector3(-7.0, 0.6, 0)]:
		k.box(side, Vector3(0.25, 0.9, 7.5), pad.darkened(0.15))
	for x in [-3.3, 3.3]:
		k.cyl(Vector3(x, 2.6, 0), 3.0, 4.6, tank, 24, up)
		k.cyl(Vector3(x, 5.15, 0), 3.0, 0.5, tank.lightened(0.05), 24, up, 2.2)   # the domed top
		k.cyl(Vector3(x, 5.5, 0), 2.2, 0.3, tank.lightened(0.08), 24, up, 0.9)
		for h in [1.2, 2.6, 4.0]:
			k.cyl(Vector3(x, h, 0), 3.03, 0.06, tank.darkened(0.15), 24, up)
	k.cyl(Vector3(0, 1.0, 0), 0.18, 1.4, Color(0.3, 0.3, 0.3), 8, Vector3(0, PI / 2, 0))   # the pipe
	k.box(Vector3(6.2, 1.3, 2.9), Vector3(1.4, 1.6, 1.2), Color(0.8, 0.78, 0.72))   # control hut
	k.box(Vector3(6.2, 2.15, 2.9), Vector3(1.6, 0.1, 1.4), Color(0.3, 0.3, 0.3))
	k.box(Vector3(6.9, 1.5, 2.9), Vector3(0.02, 0.4, 0.4), Color(0.85, 0.7, 0.15))   # its warning sign
