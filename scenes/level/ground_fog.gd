# Thick, rolling ground fog, like a fog machine's: banks of it up to the dead's
# knees. Mostly soft cloud puffs standing on the ground (fog_puff.gdshader),
# overlapping into banks with thinner gaps, each drifting slowly, swelling
# and churning; under them a few thin layers following the land fill in the
# gaps at ground level (ground_fog.gdshader). It lies in the lanes and the
# yard and thins out up the hillsides.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")
const SHADER := preload("res://assets/shaders/ground_fog.gdshader")
const PUFF_SHADER := preload("res://assets/shaders/fog_puff.gdshader")

# The puffs.
const PUFF_SPACING := 1.0                # metres between puffs (before jitter)
const PUFF_WIDTH := Vector2(2.4, 3.6)
const PUFF_HEIGHT := Vector2(0.9, 1.3)   # the thick part is the bottom 2/3 or so
const PUFF_DENSITY := 0.42
const FOREST_SPACING := 1.9            # puffs in the woods are this much further apart
const FOREST_SIZE := 1.5               # and this much bigger
const YARD := 0.3                        # the yard gets this share of the lanes' fog

const AREA := Rect2(-30, -24, 84, 64)   # the lanes, the base and around (x, z)
const CELL := 1.0                        # grid spacing, metres
const LAYERS := 2
const TOP := 0.2                         # the highest base layer
const BOTTOM := 0.03
const DENSITY := 0.14                    # opacity of the bottom layer at its thickest
const HILL := Vector2(0.7, 2.2)          # fog thins out between these ground heights

var layers: Array[MeshInstance3D] = []
var puffs: MultiMeshInstance3D

## How much fog to draw (Options: Fog): "High" as designed, "Medium" half the
## puffs (bigger and a touch thicker, so it looks much the same), "Low" just
## the thin layers on the ground (thicker), "Off" none.
const QUALITIES := ["Off", "Low", "Medium", "High"]
var quality := "High"
var _spacing := PUFF_SPACING
var _size_mul := 1.0
var _puff_density := PUFF_DENSITY
var _layer_mul := 1.0
var _night := 0.0


func _ready() -> void:
	set_quality(quality)


## Rebuilds the fog at a quality level (see QUALITIES).
func set_quality(q: String) -> void:
	quality = q if q in QUALITIES else "High"
	for c in get_children():
		c.queue_free()
	layers.clear()
	puffs = null
	match quality:
		"Off":
			return
		"Low":
			_layer_mul = 1.8
		"Medium":
			_spacing = PUFF_SPACING * 1.45
			_size_mul = 1.2
			_puff_density = PUFF_DENSITY * 1.2
			_layer_mul = 1.0
		_:
			_spacing = PUFF_SPACING
			_size_mul = 1.0
			_puff_density = PUFF_DENSITY
			_layer_mul = 1.0
	if quality != "Low":
		_build_puffs()
	_build_layers()
	set_night(_night)


## The thin layers under the puffs: one patch per lane and the yard (where the
## fog lies), not a sheet over the whole map, so the woods and hills cost no
## fog drawing at all.
func _build_layers() -> void:
	for l in LAYERS:
		var f := float(l) / maxf(1.0, LAYERS - 1)
		var lift := lerpf(BOTTOM, TOP, f)
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		for area in _areas():
			var side: int = area[0]
			var r: Rect2 = area[1].grow(1.0)
			var nu := int(r.size.x / CELL) + 1
			var nv := int(r.size.y / CELL) + 1
			var base := verts.size()
			for jv in nv:
				for iu in nu:
					var a := r.position + Vector2(iu * CELL, jv * CELL)
					var p: Vector2 = a
					if side >= 0:
						var L: Dictionary = D.LANES[side]
						p = Vector2(L["o"]) + L["t"] * a.x + L["n"] * a.y
					var h := Terrain.sample(p.x, p.y)
					verts.append(Vector3(p.x, h + lift, p.y))
					norms.append(Vector3.UP)
					var x := float(iu) / (nu - 1)
					var z := float(jv) / (nv - 1)
					var edge := smoothstep(0.0, 0.12, minf(minf(x, 1.0 - x), minf(z, 1.0 - z)))
					cols.append(Color(1, 1, 1, (1.0 - smoothstep(HILL.x, HILL.y, h)) * edge))
			for jv in nv - 1:
				for iu in nu - 1:
					var a := base + jv * nu + iu
					idx.append_array([a, a + 1, a + nu, a + 1, a + nu + 1, a + nu])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("density", (DENSITY * pow(1.0 - f, 1.4) + 0.02) * _layer_mul)
		mat.set_shader_parameter("seed", float(l) * 0.37)
		mat.render_priority = l    # bottom layer first, so they stack from below
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		layers.append(mi)


## Where the fog banks lie: the lanes (from their pipes to their walls) and the
## yard. Rect2s in each lane's (u, v) frame, the yard's in (x, z).
func _areas() -> Array:
	var out := []
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		out.append([side, Rect2(L["u0"] - 1.5, D.PIPE_V + 0.6, L["u1"] - L["u0"] + 3.0, D.WALL_Y - 0.4 - D.PIPE_V - 0.6)])
	out.append([-1, Rect2(D.BASE_X0 + 0.4, D.WALK_Y + 0.9, D.BASE_X1 - D.BASE_X0 - 0.8, D.BASE_Y1 - D.WALK_Y - 1.4)])
	return out


func _build_puffs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var banks := FastNoiseLite.new()   # where the fog lies thick, and where it thins
	banks.seed = 77
	banks.frequency = 0.09
	var spots := []
	for area in _areas():
		var side: int = area[0]
		var r: Rect2 = area[1]
		var u := r.position.x
		while u < r.end.x:
			var v := r.position.y
			while v < r.end.y:
				var pu := u + rng.randf_range(-0.5, 0.5) * _spacing
				var pv := v + rng.randf_range(-0.5, 0.5) * _spacing
				var p: Vector2
				if side >= 0:
					var L: Dictionary = D.LANES[side]
					p = Vector2(L["o"]) + L["t"] * pu + L["n"] * pv
				else:
					p = Vector2(pu, pv)
				v += _spacing
				var thick := banks.get_noise_2dv(p) * 0.5 + 0.5
				if side < 0:
					thick *= YARD
				if thick < 0.2 or rng.randf() > 0.45 + thick:
					continue    # a thinner patch
				var h := Terrain.sample(p.x, p.y)
				if h > 0.8:
					continue    # it doesn't climb the hills
				var blocked := false
				for blk in D.BLOCKERS:
					if blk.grow(0.3).has_point(p):
						blocked = true
				if blocked:
					continue
				spots.append([Vector3(p.x, h - 0.02, p.y), thick, 1.0])
			u += _spacing
	# And through the woods all round: fewer, bigger puffs (cheaper for the same
	# cover), thinning out up the hills.
	var fs := _spacing * FOREST_SPACING
	var x := AREA.position.x
	while x < AREA.end.x:
		var z := AREA.position.y
		while z < AREA.end.y:
			var p := Vector2(x + rng.randf_range(-0.5, 0.5) * fs, z + rng.randf_range(-0.5, 0.5) * fs)
			z += fs
			if _in_areas(p) or (p.x > D.BASE_X0 - 1.0 and p.x < D.BASE_X1 + 1.0 and p.y > D.WALL_Y - 1.0 and p.y < D.BASE_Y1 + 1.5):
				continue    # the lanes and the yard have their own
			var h := Terrain.sample(p.x, p.y)
			var thick := (banks.get_noise_2dv(p) * 0.5 + 0.5) * (1.0 - smoothstep(HILL.x, HILL.y + 0.6, h))
			if thick < 0.18 or rng.randf() > 0.5 + thick:
				continue
			spots.append([Vector3(p.x, h - 0.02, p.y), thick, FOREST_SIZE])
		x += fs
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)   # standing on its bottom edge
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = spots.size()
	for i in spots.size():
		var w: float = rng.randf_range(PUFF_WIDTH.x, PUFF_WIDTH.y) * _size_mul * spots[i][2]
		var hgt: float = rng.randf_range(PUFF_HEIGHT.x, PUFF_HEIGHT.y) * lerpf(0.8, 1.15, spots[i][1]) * lerpf(1.0, spots[i][2], 0.5)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(w, hgt, 1.0)), spots[i][0]))
		mm.set_instance_custom_data(i, Color(rng.randf(), lerpf(0.4, 1.0, spots[i][1]), rng.randf(), 0.0))
	var mat := ShaderMaterial.new()
	mat.shader = PUFF_SHADER
	mat.set_shader_parameter("density", _puff_density)
	mat.render_priority = LAYERS + 1   # over the flat base layers
	puffs = MultiMeshInstance3D.new()
	puffs.multimesh = mm
	puffs.material_override = mat
	puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One big bounding box, or the camera could cull drifting puffs.
	puffs.custom_aabb = AABB(Vector3(AREA.position.x, -2, AREA.position.y), Vector3(AREA.size.x, 6, AREA.size.y))
	add_child(puffs)


## True inside a lane's or the yard's fog area (see _areas()).
func _in_areas(p: Vector2) -> bool:
	for area in _areas():
		var side: int = area[0]
		var q := p
		if side >= 0:
			var L: Dictionary = D.LANES[side]
			var d: Vector2 = p - Vector2(L["o"])
			q = Vector2(d.dot(L["t"]), d.dot(L["n"]))
		if area[1].grow(0.8).has_point(q):
			return true
	return false


## Fog a little thicker at night (k: 0 day .. 1 deep night).
func set_night(k: float) -> void:
	_night = k
	if puffs != null:
		puffs.material_override.set_shader_parameter("density", _puff_density * lerpf(1.0, 1.25, k))
	for l in layers.size():
		var f := float(l) / (LAYERS - 1)
		var m: ShaderMaterial = layers[l].material_override
		m.set_shader_parameter("density", (DENSITY * lerpf(1.0, 1.35, k) * pow(1.0 - f, 1.4) + 0.02) * _layer_mul)
