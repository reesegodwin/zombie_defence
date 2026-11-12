# The stake fence round the sides and back of the base, with a gap for the gate
# to the mountain pass. The wall itself closes the front. Generated in code
# from the base's size in scripts/defs.gd, and shown in the editor too.
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")

@export var seed_value := 21:
	set(v):
		seed_value = v
		if is_inside_tree():
			_build()
## Gap left in the back fence for the gate, centred on the trail (metres).
@export var gate_width := 3.8


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var front := D.WALL_Y + 0.25
	var gate_x: float = D.PASS_PATH[0].x
	var back := D.BASE_Y1
	# Each run of fence: from, to.
	# The side walls (D.LANES 1 and 2) fill the middle of each side.
	var w_lo: float = -D.LANES[1]["u1"]
	var w_hi: float = -D.LANES[1]["u0"]
	var e_lo: float = D.LANES[2]["u0"]
	var e_hi: float = D.LANES[2]["u1"]
	var runs := [
		[Vector2(D.X0 - 0.1, front), Vector2(D.BASE_X0, front)],
		[Vector2(D.BASE_X0, front), Vector2(D.BASE_X0, w_lo)],
		[Vector2(D.BASE_X0, w_hi), Vector2(D.BASE_X0, back)],
		[Vector2(D.BASE_X0, back), Vector2(gate_x - gate_width / 2, back)],
		[Vector2(gate_x + gate_width / 2, back), Vector2(D.BASE_X1, back)],
		[Vector2(D.BASE_X1, back), Vector2(D.BASE_X1, e_hi)],
		[Vector2(D.BASE_X1, e_lo), Vector2(D.BASE_X1, front)],
		[Vector2(D.BASE_X1, front), Vector2(D.X1 + 0.1, front)],
	]
	var stakes: Array = []
	var rails: Array = []
	for r in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var n := maxi(1, int(a.distance_to(b) / 0.32))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			stakes.append([p, rng.randf_range(1.0, 1.35), rng.randf_range(-0.07, 0.07)])
		for h in [0.35, 0.8]:
			rails.append([a, b, h])

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5e452c")
	wood.roughness = 0.95
	var stake := CylinderMesh.new()
	stake.top_radius = 0.02
	stake.bottom_radius = 0.09
	stake.height = 1.0
	stake.radial_segments = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stake
	mm.instance_count = stakes.size()
	for i in stakes.size():
		var p: Vector2 = stakes[i][0]
		var h: float = stakes[i][1]
		var basis := Basis(Vector3(1, 0, 0), stakes[i][2]).rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, h, 1))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, h * 0.5, p.y)))
		mm.set_instance_color(i, Color(0.8, 0.8, 0.8).lerp(Color(1.1, 1.05, 1.0), rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = wood
	add_child(mi)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(1, 0.06, 0.06)
	for r in rails:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var m := MeshInstance3D.new()
		m.mesh = rail_mesh
		m.material_override = wood
		var mid := (a + b) * 0.5
		m.transform = Transform3D(Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x)).scaled(Vector3(a.distance_to(b), 1, 1)), Vector3(mid.x, r[2], mid.y))
		add_child(m)
