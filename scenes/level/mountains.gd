# The mountains behind the base, opposite the tree line the dead come from, with
# one narrow pass that scavengers walk through. Generated from a seed with
# MultiMesh, and shown in the editor too. Change the seed in the Inspector to
# re-roll the peaks; the pass always follows the route in scripts/defs.gd.
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")

@export var seed_value := 7:
	set(v):
		seed_value = v
		if is_inside_tree():
			_build()
@export var rock_material: Material
@export var snow_material: Material
@export var path_material: Material
## How wide the pass stays clear, in metres either side of the path.
@export var pass_half_width := 1.3


func _ready() -> void:
	_build()


func _dist_to_path(p: Vector2) -> float:
	var pts: Array = D.PASS_PATH
	var best := INF
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a.lerp(b, t)))
	# Beyond the last point the pass keeps going straight on.
	if p.y > pts[-1].y:
		best = minf(best, absf(p.x - pts[-1].x))
	return best


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var peaks: Array = []    # [position, radius, height, yaw]
	var y := D.BASE_Y1 + 1.6
	while y < D.BASE_Y1 + 30.0:
		var x := -16.0
		while x < 40.0:
			var px := x + rng.randf_range(-0.8, 0.8)
			var pz := y + rng.randf_range(-0.6, 0.6)
			var depth := pz - (D.BASE_Y1 + 1.0)
			var h := clampf(depth * 0.55, 1.4, 10.0) * rng.randf_range(0.7, 1.2)
			# Keep the slopes right behind the base low, so they don't hide it.
			if px > D.BASE_X0 and px < D.BASE_X1 and pz < D.BASE_Y1 + 5.0:
				h = minf(h, 2.6)
			var r := h * rng.randf_range(0.6, 0.85) + 0.8
			var clear := _dist_to_path(Vector2(px, pz))
			# Peaks on the camera side of the trail stay lower near it.
			if px > 12.0 and clear < 8.0:
				h = minf(h, 1.5 + clear * 0.6)
			if clear > pass_half_width + 0.4:
				# Squash peaks next to the pass so they lean away from it.
				r = minf(r, (clear - pass_half_width) * 1.6 + 0.6)
				if r > 0.6:
					peaks.append([Vector3(px, Terrain.sample(px, pz) - 0.3, pz), r, h, rng.randf() * TAU])
			x += rng.randf_range(2.2, 3.4)
		y += rng.randf_range(1.6, 2.6)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var rocks := _multimesh(cone, rock_material, peaks.size(), true)
	var snowy: Array = []
	for i in peaks.size():
		var p: Vector3 = peaks[i][0]
		var r: float = peaks[i][1]
		var h: float = peaks[i][2]
		var basis := Basis(Vector3.UP, peaks[i][3]).scaled(Vector3(r, h, r * rng.randf_range(0.75, 1.0)))
		rocks.multimesh.set_instance_transform(i, Transform3D(basis, p + Vector3(0, h * 0.5, 0)))
		var c := Color(0.27, 0.24, 0.21).lerp(Color(0.4, 0.35, 0.3), rng.randf())
		rocks.multimesh.set_instance_color(i, c)
		if h > 6.0:
			snowy.append(i)
	var snow := _multimesh(cone, snow_material, snowy.size(), true)
	for k in snowy.size():
		var i: int = snowy[k]
		var p: Vector3 = peaks[i][0]
		var r: float = peaks[i][1]
		var h: float = peaks[i][2]
		var cap := 0.3
		var basis := Basis(Vector3.UP, peaks[i][3]).scaled(Vector3(r * cap * 1.04, h * cap, r * cap * 1.04))
		snow.multimesh.set_instance_transform(k, Transform3D(basis, p + Vector3(0, h * (1.0 - cap * 0.5) + 0.02, 0)))
		snow.multimesh.set_instance_color(k, Color.WHITE)

	# Boulders and cliff faces lining the pass make it feel narrow.
	var boulder := SphereMesh.new()
	boulder.radius = 1.0
	boulder.height = 1.4
	boulder.radial_segments = 6
	boulder.rings = 3
	var pts: Array = D.PASS_PATH
	var lining: Array = []
	for i in range(2, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var steps := int(a.distance_to(b) / 0.9)
		for k in steps:
			var c: Vector2 = a.lerp(b, (k + rng.randf()) / steps)
			for sgn in [-1.0, 1.0]:
				var off := pass_half_width + rng.randf_range(0.3, 0.9)
				lining.append([c + side * sgn * off, rng.randf_range(0.5, 1.1), rng.randf_range(0.8, 2.4) + (c.y - D.BASE_Y1 - 1.0) * 0.12])
	var bm := _multimesh(boulder, rock_material, lining.size(), true)
	for i in lining.size():
		var p2: Vector2 = lining[i][0]
		var r2: float = lining[i][1]
		var h2: float = lining[i][2]
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r2, h2, r2 * 1.2))
		bm.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p2.x, h2 * 0.25 + Terrain.sample(p2.x, p2.y), p2.y)))
		bm.multimesh.set_instance_color(i, Color(0.3, 0.27, 0.24).lerp(Color(0.44, 0.4, 0.35), rng.randf()))

	# The trail itself, from the back of the base up into the pass.
	var trail := BoxMesh.new()
	trail.size = Vector3(1, 1, 1)
	var segs: Array = [Vector2(11.2, D.BASE_Y1 - 0.2)]
	for p in pts:
		if p.y > D.BASE_Y1:
			segs.append(p)
	for i in range(1, segs.size()):
		var a: Vector2 = segs[i - 1]
		var b: Vector2 = segs[i]
		var m := MeshInstance3D.new()
		m.mesh = trail
		m.material_override = path_material
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + 0.6
		m.transform = Transform3D(Basis(Vector3.UP, atan2(b.x - a.x, b.y - a.y)).scaled(Vector3(1.4, 0.02, length)), Vector3(mid.x, 0.012, mid.y))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)


func _multimesh(mesh: Mesh, mat: Material, count: int, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
	return mi
