# Low-poly pine woods on both sides of the lane, so the only way in is the front.
# Generated from a seed with MultiMesh (one draw call per part), and shown in the
# editor too. Change the seed or density in the Inspector to re-roll it.
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Mountains = preload("res://scenes/level/mountains.gd")

## Where the trees go (the whole ground), and the part round the lanes and
## the base where they grow thick.
const AREA := Rect2(-96, -96, 232, 217)
const NEAR := Rect2(-25, -22, 72, 53)

@export var seed_value := 1337:
	set(v):
		seed_value = v
		if is_inside_tree():
			_build()
@export_range(0.0, 1.0) var density := 0.75:
	set(v):
		density = v
		if is_inside_tree():
			_build()
@export var trunk_material: Material
@export var needle_material: Material


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots: Array = []
	var side_spots := {1: [], 2: []}   # woods over a side lane, for levels that never use it
	for y in range(int(AREA.position.y), int(AREA.end.y)):
		for x in range(int(AREA.position.x), int(AREA.end.x)):
			var cp := Vector2(x + 0.5, y + 0.5)
			if y > Mountains.start_z(cp.x) + 2.5:
				continue  # the mountains behind the base
			# Out past where the game is played: fewer, bigger trees, all the way
			# to the edge of the map.
			var far := maxf(maxf(NEAR.position.x - cp.x, cp.x - NEAR.end.x), maxf(NEAR.position.y - cp.y, cp.y - NEAR.end.y))
			if far > 0.0 and rng.randf() > lerpf(0.55, 0.3, clampf(far / 40.0, 0.0, 1.0)):
				continue
			var lane := _side_lane_of(cp)
			if lane < 0:
				lane = _culvert_of(cp)
				if lane == 0:
					continue  # the front lane's sewer
			if lane > 0:
				# The west or east lane (or its sewer): kept clear for the dead, but
				# wooded over on levels where it's never used, up to its wall.
				if _wall_v(lane, cp) < D.WALL_Y - 1.3 and rng.randf() < 0.62 * density:
					var sp := cp + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
					side_spots[lane].append(Vector3(sp.x, Terrain.sample(sp.x, sp.y), sp.y))
				continue
			if x >= D.X0 - 1 and x <= D.X1 and y <= D.WALL_Y + 0.5:
				continue  # the lane and the rocks by the wall
			if x >= D.X0 and x < D.X1 and y <= D.WALL_Y:
				continue  # the lane
			if x >= D.BASE_X0 - 1 and x <= D.BASE_X1 and y >= D.WALL_Y - 1 and y <= D.BASE_Y1 + 1:
				continue  # the base and a strip of cleared ground round its fence
			var near := x == D.X0 - 2 or x == D.X1 + 1 or x == D.X0 - 1 or x == D.X1
			var p := (0.9 if near else 0.6) if y <= D.WALL_Y else (0.45 if near else 0.3)
			if far > 0.0:
				p = 0.85
			if rng.randf() < p * density:
				var tx := x + 0.5 + rng.randf_range(-0.3, 0.3)
				var tz := y + 0.5 + rng.randf_range(-0.3, 0.3)
				var th := Terrain.sample(tx, tz)
				# Bald hilltops and open glades, so the lie of the land shows (only
				# the very tops of the bigger hills further out).
				var bald := smoothstep(1.6, 3.6, th) * 0.85 if far <= 0.0 else smoothstep(5.0, 8.5, th) * 0.6
				if rng.randf() < bald:
					continue
				spots.append(Vector3(tx, th, tz) if far <= 0.0 else Vector4(tx, th, tz, 1.0 + minf(far / 35.0, 0.7)))
	# The far woods: simpler trees that cast no shadows (too far to notice).
	var near_spots := spots.filter(func(sp): return sp is Vector3)
	var far_spots := spots.filter(func(sp): return sp is Vector4)
	_plant(self, near_spots, rng)
	var far_node := Node3D.new()
	far_node.name = "FarWoods"
	add_child(far_node)
	_plant(far_node, far_spots, rng, true)
	for side in [1, 2]:
		var woods := Node3D.new()
		woods.name = "SideWoods%d" % side
		woods.visible = false
		add_child(woods)
		_plant(woods, side_spots[side], rng)


## Shows the woods over a side lane (true: that lane's never used this level).
func set_wooded(side: int, on: bool) -> void:
	var n := get_node_or_null("SideWoods%d" % side)
	if n:
		n.visible = on


func _plant(parent: Node3D, spots: Array, rng: RandomNumberGenerator, far := false) -> void:
	if spots.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.12
	trunk.height = 0.8
	trunk.radial_segments = 6
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.7
	cone.height = 1.1
	cone.radial_segments = 5 if far else 7
	cone.rings = 1
	cone.cap_bottom = not far
	if far:
		trunk.radial_segments = 4
	var trunks := _multimesh(trunk, trunk_material, spots.size(), false, parent)
	var cones := _multimesh(cone, needle_material, spots.size() * 3, true, parent)
	if far:
		trunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in spots.size():
		var s := rng.randf_range(0.8, 1.35)
		if spots[i] is Vector4:   # a far tree: bigger
			s *= spots[i].w
			spots[i] = Vector3(spots[i].x, spots[i].y, spots[i].z)
		var yaw := rng.randf() * TAU
		var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), spots[i])
		trunks.multimesh.set_instance_transform(i, base.translated_local(Vector3(0, 0.4, 0)))
		var tint := Color(0.1, 0.19, 0.13).lerp(Color(0.16, 0.25, 0.15), rng.randf())   # deep evergreen
		for k in 3:
			var ks := 1.0 - k * 0.24
			var t := Transform3D(Basis(Vector3.UP, yaw + k).scaled(Vector3(ks, 1.0, ks) * s), spots[i] + Vector3(0, (0.95 + k * 0.62) * s, 0))
			cones.multimesh.set_instance_transform(i * 3 + k, t)
			cones.multimesh.set_instance_color(i * 3 + k, tint.lightened(k * 0.04))


## Inside the open ground of a side lane (in front of the west or east wall)?
## True on the footprint of a lane's culvert (scenes/level/culvert.gd).
func _at_culvert(p: Vector2) -> bool:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] - 6.5 and u <= L["u1"] + 6.5 and v >= D.PIPE_V - 6.0 and v <= D.PIPE_V + 3.0:
			return true
	return false


## Which side lane's open ground (1 west, 2 east) holds p, or -1.
func _side_lane_of(p: Vector2) -> int:
	for side in [1, 2]:
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] - 0.8 and u <= L["u1"] + 0.8 and v >= D.LANE_START - 4.0 and v <= D.WALL_Y + 0.5:
			return side
	return -1


## Which lane's culvert footprint holds p (0, 1, 2), or -1.
func _culvert_of(p: Vector2) -> int:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] - 6.5 and u <= L["u1"] + 6.5 and v >= D.PIPE_V - 6.0 and v <= D.PIPE_V + 3.0:
			return side
	return -1


## How far down a lane p is (v: the wall is at D.WALL_Y).
func _wall_v(side: int, p: Vector2) -> float:
	var L: Dictionary = D.LANES[side]
	return (p - Vector2(L["o"])).dot(L["n"])


func _in_side_lane(p: Vector2) -> bool:
	for side in [1, 2]:
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] - 0.8 and u <= L["u1"] + 0.8 and v >= D.LANE_START - 4.0 and v <= D.WALL_Y + 0.5:
			return true
	return false


func _multimesh(mesh: Mesh, mat: Material, count: int, colors: bool, parent: Node3D = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	(parent if parent != null else self).add_child(mi)
	return mi
