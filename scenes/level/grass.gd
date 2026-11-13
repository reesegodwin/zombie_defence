# Low-poly grass: tufts of tapered blades (straw at the roots, green at the
# tips) on the forest floor and along the lanes' edges, off the trodden dirt,
# the yard and the mountains. One tuft shape, scattered from a seed with
# MultiMesh in square tiles of the map (so tiles off screen aren't drawn).
# Low graphics draws half of them; Very Low none.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Ground = preload("res://scenes/level/ground.gd")
const Mountains = preload("res://scenes/level/mountains.gd")
const SHADER := preload("res://assets/shaders/grass.gdshader")

const AREA := Rect2(-42, -38, 108, 92)   # around the lanes and the base: what the camera sees
const SPACING := 0.42                    # metres between tufts (before jitter and gaps): small tufts, lots of them
const CHUNK := 16.0
const BLADES := 8

var _tiles: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	_build()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mesh := _tuft_mesh(rng)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var patches := FastNoiseLite.new()   # grass grows in patches, thicker and thinner
	patches.seed = 7
	patches.frequency = 0.08
	var tiles := {}
	var y := AREA.position.y
	while y < AREA.end.y:
		var x := AREA.position.x
		while x < AREA.end.x:
			var p := Vector2(x + rng.randf_range(-0.4, 0.4) * SPACING, y + rng.randf_range(-0.4, 0.4) * SPACING)
			x += SPACING
			var keep := 0.3 + 0.45 * patches.get_noise_2dv(p)
			var w := Ground._dirt_weights(p)
			var dirt := maxf(maxf(w.x, w.y), w.z * 1.4)
			keep += 0.5 * smoothstep(0.0, 0.12, dirt)   # thickest along the edge of the dirt...
			keep *= 1.0 - smoothstep(0.2, 0.5, dirt)     # ...but not on the trodden dirt or in the yard
			if p.y > Mountains.start_z(p.x) - 0.5 or rng.randf() > keep:
				continue
			var h := Terrain.sample(p.x, p.y)
			var s := rng.randf_range(0.7, 1.25)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s)), Vector3(p.x, h - 0.02, p.y))
			var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
			if not tiles.has(key):
				tiles[key] = []
			tiles[key].append(xf)
		y += SPACING
	for key in tiles:
		var list: Array = tiles[key]
		list.shuffle()   # so drawing only the first half (Low) thins them evenly
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tiles.append(mi)


## Graphics: "High"/"Medium" all of it, "Low" half, "Very Low" none.
func set_quality(q: String) -> void:
	visible = q != "Very Low"
	for mi in _tiles:
		var n := mi.multimesh.instance_count
		mi.multimesh.visible_instance_count = n / 2 if q == "Low" else -1


## A tuft: blades fanning out from a small clump, each a tapered strip bent
## outward (two segments to the tip), straw at the root, green at the tip.
static func _tuft_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var root_col := Color(0.5, 0.44, 0.24)
	for b in BLADES:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.1)
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var hgt := rng.randf_range(0.22, 0.42)
		var lean := rng.randf_range(0.04, 0.15)
		var wid := rng.randf_range(0.018, 0.03)
		var tip_col := Color(0.42, 0.55, 0.2).lerp(Color(0.62, 0.62, 0.3), rng.randf())
		var mid := base + Vector3(0, hgt * 0.55, 0) + out * lean * 0.35
		var tip := base + Vector3(0, hgt, 0) + out * lean
		var mid_col := root_col.lerp(tip_col, 0.6)
		var pts := [base - side * wid, base + side * wid, mid - side * wid * 0.7, mid + side * wid * 0.7]
		# root to middle: two triangles; middle to tip: one
		for tri in [[0, 1, 2], [1, 3, 2]]:
			for k in tri:
				v.append(pts[k])
				c.append(root_col if k < 2 else mid_col)
		v.append(pts[2]); c.append(mid_col)
		v.append(pts[3]); c.append(mid_col)
		v.append(tip); c.append(tip_col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
