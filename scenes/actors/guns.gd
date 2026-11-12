# The guns, built in code from low-poly blocks and tubes with flat faces and
# their colours baked in: one mesh per gun, made once and shared by everyone
# who carries one. Each gun points down +z, with its grip at the origin and
# the bore along y = 0; it's scaled so it's barrel_length (in its .tres) long.
#
# The Kit below is also what the turret (turret.gd) is built from.
extends RefCounted

const STEEL := Color(0.2, 0.21, 0.22)
const BLACK := Color(0.1, 0.1, 0.11)
const POLY := Color(0.14, 0.14, 0.15)
const GREY := Color(0.44, 0.47, 0.49)
const WOOD := Color(0.55, 0.32, 0.19)
const DARK_WOOD := Color(0.42, 0.24, 0.14)
const OLIVE := Color(0.34, 0.38, 0.25)

static var _cache := {}
static var _material: StandardMaterial3D


## Where the grip sits from the gun pivot in survivor.gd (just under the hands).
const HOLD := Vector3(-0.01, 0.13, 0.34)


## The gun for a weapon key: {"mesh", "scale", "muzzle"} (the muzzle's z once scaled).
static func get_gun(key: String, length: float) -> Dictionary:
	if not _cache.has(key):
		var k := Kit.new()
		var ends: Vector2
		match key:
			"smg": ends = _smg(k)
			"shotgun": ends = _shotgun(k)
			"rifle": ends = _rifle(k)
			"launcher": ends = _launcher(k)
			_: ends = _pistol(k)
		_cache[key] = {"mesh": k.mesh(), "ends": ends}
	var g: Dictionary = _cache[key]
	var ends: Vector2 = g["ends"]
	var s := length / (ends.y - ends.x)
	return {"mesh": g["mesh"], "scale": s, "muzzle": ends.y * s}


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.6
		_material.metallic = 0.15
	return _material


# Each returns its (rear, muzzle) z.

static func _pistol(k: Kit) -> Vector2:
	k.box(Vector3(0, 0.012, 0.075), Vector3(0.028, 0.032, 0.19), STEEL)          # slide
	for i in 5:                                                                  # grip serrations
		k.box(Vector3(0, 0.014, -0.012 + i * 0.008), Vector3(0.0296, 0.024, 0.003), BLACK)
	k.box(Vector3(0, 0.0292, 0.06), Vector3(0.016, 0.002, 0.04), GREY)           # ejection port
	k.box(Vector3(0, 0.031, -0.012), Vector3(0.016, 0.006, 0.006), BLACK)        # sights
	k.box(Vector3(0, 0.031, 0.16), Vector3(0.006, 0.006, 0.006), BLACK)
	k.box(Vector3(0, -0.012, 0.07), Vector3(0.026, 0.018, 0.16), POLY)           # frame
	k.box(Vector3(0, 0.012, 0.1705), Vector3(0.01, 0.01, 0.002), Color(0.03, 0.03, 0.03))  # bore
	k.box(Vector3(0, -0.058, -0.008), Vector3(0.026, 0.09, 0.036), POLY, Vector3(0.28, 0, 0))   # grip
	k.box(Vector3(0, -0.103, -0.022), Vector3(0.03, 0.008, 0.042), BLACK, Vector3(0.28, 0, 0))  # magazine base
	k.box(Vector3(0, -0.036, 0.045), Vector3(0.009, 0.006, 0.048), POLY)         # trigger guard
	k.box(Vector3(0, -0.028, 0.068), Vector3(0.009, 0.022, 0.006), POLY)
	k.box(Vector3(0, -0.024, 0.04), Vector3(0.006, 0.018, 0.005), BLACK, Vector3(0.3, 0, 0))   # trigger
	return Vector2(-0.02, 0.171)


static func _smg(k: Kit) -> Vector2:
	k.box(Vector3(0, 0.0, 0.08), Vector3(0.04, 0.048, 0.3), BLACK)               # receiver
	k.cyl(Vector3(0, 0.022, 0.08), 0.021, 0.3, BLACK, 8)
	k.box(Vector3(0.0205, 0.018, 0.16), Vector3(0.002, 0.006, 0.12), GREY)        # cocking slot
	k.box(Vector3(0, -0.006, 0.27), Vector3(0.044, 0.05, 0.12), POLY)            # handguard
	for i in 4:
		k.box(Vector3(0, -0.032, 0.23 + i * 0.026), Vector3(0.046, 0.006, 0.012), BLACK)
	k.cyl(Vector3(0, 0.022, 0.29), 0.012, 0.16, BLACK, 8)                        # cocking tube
	k.cyl(Vector3(0, 0.006, 0.37), 0.009, 0.08, STEEL, 8)                        # barrel
	k.cyl(Vector3(0, 0.006, 0.405), 0.013, 0.035, STEEL, 8)                      # flash hider
	k.box(Vector3(0, 0.05, 0.345), Vector3(0.014, 0.075, 0.016), BLACK)          # front sight post
	k.box(Vector3(0, 0.05, -0.045), Vector3(0.026, 0.024, 0.026), BLACK)         # rear sight drum
	k.box(Vector3(0, 0.0, -0.075), Vector3(0.046, 0.056, 0.02), POLY)            # end cap
	k.box(Vector3(0, -0.036, 0.13), Vector3(0.032, 0.03, 0.042), BLACK)          # magazine well
	for i in 6:                                                                  # curved magazine
		var a := -0.12 - i * 0.075
		k.box(Vector3(0, -0.06 - i * 0.026, 0.13 + i * 0.006 + i * i * 0.0026), Vector3(0.022, 0.04, 0.032), POLY, Vector3(a, 0, 0))
	k.box(Vector3(0, -0.064, -0.012), Vector3(0.03, 0.085, 0.042), POLY, Vector3(0.3, 0, 0))   # grip
	k.box(Vector3(0, -0.046, 0.04), Vector3(0.01, 0.006, 0.06), BLACK)           # trigger guard
	k.box(Vector3(0, -0.032, 0.03), Vector3(0.006, 0.02, 0.005), STEEL, Vector3(0.3, 0, 0))
	for sx in [-0.014, 0.014]:                                                   # sliding stock
		k.cyl(Vector3(sx, 0.0, -0.15), 0.005, 0.15, STEEL, 6)
	k.box(Vector3(0, -0.022, -0.235), Vector3(0.036, 0.09, 0.024), POLY, Vector3(-0.1, 0, 0))
	return Vector2(-0.247, 0.423)


static func _shotgun(k: Kit) -> Vector2:
	k.cyl(Vector3(0, 0.02, 0.3), 0.013, 0.6, GREY, 8)                            # barrel
	k.cyl(Vector3(0, -0.009, 0.25), 0.011, 0.5, GREY.darkened(0.15), 8)          # magazine tube
	k.box(Vector3(0, 0.006, 0.52), Vector3(0.012, 0.034, 0.02), GREY.darkened(0.2))   # barrel clamp
	k.box(Vector3(0, -0.002, 0.2), Vector3(0.038, 0.036, 0.17), WOOD)            # pump
	for i in 5:
		k.box(Vector3(0, -0.002, 0.14 + i * 0.03), Vector3(0.04, 0.03, 0.006), DARK_WOOD)
	k.box(Vector3(0, 0.006, -0.04), Vector3(0.038, 0.062, 0.13), GREY)           # receiver
	k.box(Vector3(0.0195, 0.012, -0.03), Vector3(0.002, 0.018, 0.05), BLACK)     # ejection port
	k.box(Vector3(0, -0.036, -0.045), Vector3(0.008, 0.014, 0.04), GREY.darkened(0.3))   # trigger guard
	k.box(Vector3(0, -0.018, -0.14), Vector3(0.032, 0.042, 0.1), WOOD, Vector3(0.25, 0, 0))    # wrist
	k.box(Vector3(0, -0.038, -0.255), Vector3(0.036, 0.075, 0.17), WOOD, Vector3(0.1, 0, 0))   # stock
	k.box(Vector3(0, -0.054, -0.25), Vector3(0.0365, 0.03, 0.16), DARK_WOOD, Vector3(0.1, 0, 0))
	k.box(Vector3(0, -0.047, -0.345), Vector3(0.038, 0.085, 0.014), BLACK, Vector3(0.1, 0, 0))  # butt pad
	return Vector2(-0.352, 0.6)


static func _rifle(k: Kit) -> Vector2:
	k.cyl(Vector3(0, 0.014, 0.33), 0.0085, 0.54, STEEL, 8)                       # barrel
	k.box(Vector3(0, -0.006, 0.17), Vector3(0.03, 0.03, 0.42), WOOD)             # fore-stock
	k.box(Vector3(0, 0.012, -0.02), Vector3(0.026, 0.032, 0.13), STEEL)          # receiver
	k.box(Vector3(0.026, 0.016, -0.05), Vector3(0.03, 0.007, 0.007), STEEL)      # bolt handle
	k.box(Vector3(0.042, 0.016, -0.05), Vector3(0.012, 0.012, 0.012), BLACK)
	k.cyl(Vector3(0, 0.062, 0.0), 0.013, 0.2, BLACK, 8)                          # scope
	k.cyl(Vector3(0, 0.062, 0.105), 0.02, 0.05, BLACK, 8)
	k.cyl(Vector3(0, 0.062, -0.09), 0.017, 0.04, BLACK, 8)
	k.box(Vector3(0, 0.081, 0.0), Vector3(0.008, 0.008, 0.012), BLACK)          # turret knob
	for z in [-0.05, 0.05]:
		k.box(Vector3(0, 0.038, z), Vector3(0.016, 0.026, 0.014), BLACK)
	k.box(Vector3(0, -0.032, -0.03), Vector3(0.008, 0.016, 0.045), STEEL)        # trigger guard
	k.box(Vector3(0, -0.028, -0.13), Vector3(0.028, 0.05, 0.1), WOOD, Vector3(0.22, 0, 0))     # wrist
	k.box(Vector3(0, -0.045, -0.25), Vector3(0.034, 0.08, 0.16), WOOD, Vector3(0.08, 0, 0))    # stock
	k.box(Vector3(0, -0.034, -0.24), Vector3(0.035, 0.02, 0.11), DARK_WOOD, Vector3(0.08, 0, 0))   # cheek rest
	k.box(Vector3(0, -0.052, -0.335), Vector3(0.036, 0.09, 0.014), BLACK, Vector3(0.08, 0, 0))     # recoil pad
	return Vector2(-0.342, 0.6)


static func _launcher(k: Kit) -> Vector2:
	k.cyl(Vector3(0, 0.012, 0.2), 0.032, 0.38, OLIVE, 10)                       # barrel
	k.cyl(Vector3(0, 0.012, 0.39), 0.036, 0.02, OLIVE.darkened(0.25), 10)
	k.cyl(Vector3(0, 0.012, 0.401), 0.022, 0.004, Color(0.03, 0.03, 0.03), 10)   # bore
	for z in [0.08, 0.3]:
		k.cyl(Vector3(0, 0.012, z), 0.035, 0.015, OLIVE.darkened(0.25), 10)
	k.box(Vector3(0, 0.0, -0.025), Vector3(0.054, 0.075, 0.1), POLY)             # receiver
	k.box(Vector3(0, 0.06, 0.08), Vector3(0.022, 0.035, 0.006), BLACK)           # ladder sight
	k.box(Vector3(0, -0.06, 0.13), Vector3(0.026, 0.07, 0.032), POLY, Vector3(-0.1, 0, 0))      # front grip
	k.box(Vector3(0, -0.07, -0.045), Vector3(0.03, 0.085, 0.04), POLY, Vector3(0.3, 0, 0))      # grip
	k.box(Vector3(0, -0.04, 0.0), Vector3(0.01, 0.006, 0.05), BLACK)             # trigger guard
	k.cyl(Vector3(0, 0.005, -0.16), 0.009, 0.2, STEEL, 6)                        # stock tube
	k.box(Vector3(0, -0.02, -0.265), Vector3(0.04, 0.09, 0.026), POLY)           # butt
	return Vector2(-0.278, 0.403)


## Builds one mesh from boxes and tubes, each face flat, colours per vertex.
## wear (0..1) mottles the faces with rust and faded paint, for old metal.
class Kit:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var wear := 0.0
	var stain := Color(0.46, 0.27, 0.16)   # what wear streaks faces with (rust)
	var fade := Color(0.6, 0.62, 0.53)     # and what it fades them toward
	var rng := RandomNumberGenerator.new()

	## One flat face of a convex piece around centre, turned to face outwards
	## (clockwise seen from outside, as Godot expects).
	func _face(pts: Array, col: Color, centre: Vector3) -> void:
		var nrm: Vector3 = (pts[2] - pts[0]).cross(pts[1] - pts[0]).normalized()
		var mid := Vector3.ZERO
		for p in pts:
			mid += p
		if nrm.dot(mid / pts.size() - centre) < 0.0:
			pts.reverse()
			nrm = -nrm
		var fc := col
		if wear > 0.0:
			fc = col * rng.randf_range(1.0 - wear * 0.25, 1.0 + wear * 0.1)
			var r := rng.randf()
			if r < wear * 0.3:
				fc = fc.lerp(stain, rng.randf_range(0.3, 0.7))
			elif r < wear * 0.5:
				fc = fc.lerp(fade, rng.randf_range(0.15, 0.35))
			fc.a = 1.0
		for i in range(1, pts.size() - 1):
			for p in [pts[0], pts[i], pts[i + 1]]:
				v.append(p)
				n.append(nrm)
				c.append(fc)

	## A flat polygon (convex, its points in order), facing away from centre.
	func poly(pts: Array, col: Color, centre: Vector3) -> void:
		_face(pts.duplicate(), col, centre)

	## A box centred on pos, turned by rot (Euler angles).
	func box(pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		var b := Basis.from_euler(rot)
		var h := size / 2.0
		var p := []
		for i in 8:
			p.append(pos + b * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
		for f in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
			_face([p[f[0]], p[f[1]], p[f[2]], p[f[3]]], col, pos)

	## A tube along z (or turned by rot), capped at both ends.
	func cyl(pos: Vector3, r: float, length: float, col: Color, seg := 8, rot := Vector3.ZERO, r2 := -1.0) -> void:
		if r2 < 0.0:
			r2 = r
		var b := Basis.from_euler(rot)
		var back := []
		var front := []
		for i in seg:
			var a := TAU * (i + 0.5) / seg
			back.append(pos + b * Vector3(cos(a) * r, sin(a) * r, -length / 2))
			front.append(pos + b * Vector3(cos(a) * r2, sin(a) * r2, length / 2))
		for i in seg:
			var j := (i + 1) % seg
			_face([back[i], front[i], front[j], back[j]], col, pos)
		_face(front, col.darkened(0.1), pos)
		_face(back, col.darkened(0.1), pos)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
