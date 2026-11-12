# The radio station: a small hut with a lattice mast, a whip antenna and a red
# light blinking at the top. Built in code.
extends Node3D

const MAST_H := 3.2

var light: OmniLight3D
var bulb: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	var wood := _mat(Color("5e452c"))
	var metal := _mat(Color("7b8389"), 0.5, 0.7)
	var hut := BoxMesh.new()
	hut.size = Vector3(1.1, 0.8, 0.9)
	_mesh(hut, wood, Vector3(-0.15, 0.4, 0.1))
	var roof := BoxMesh.new()
	roof.size = Vector3(1.25, 0.08, 1.05)
	_mesh(roof, _mat(Color("3a3f44")), Vector3(-0.15, 0.84, 0.1))
	# The mast: four legs tapering up, with cross braces.
	var leg := BoxMesh.new()
	leg.size = Vector3(0.05, MAST_H, 0.05)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var m := _mesh(leg, metal, Vector3(0.45 + sx * 0.12, MAST_H / 2, -0.35 + sz * 0.12))
			m.rotation = Vector3(-sz * 0.035, 0, sx * 0.035)
	var brace := BoxMesh.new()
	brace.size = Vector3(0.24, 0.03, 0.03)
	for k in 6:
		var y := 0.4 + k * 0.48
		for sz in [-1, 1]:
			_mesh(brace, metal, Vector3(0.45, y, -0.35 + sz * 0.12 * (1.0 - y / MAST_H * 0.6)))
	var whip := CylinderMesh.new()
	whip.top_radius = 0.01
	whip.bottom_radius = 0.02
	whip.height = 1.0
	_mesh(whip, metal, Vector3(0.45, MAST_H + 0.5, -0.35))
	var dish := CylinderMesh.new()
	dish.top_radius = 0.22
	dish.bottom_radius = 0.05
	dish.height = 0.08
	var d := _mesh(dish, metal, Vector3(0.62, MAST_H * 0.7, -0.35))
	d.rotation.z = -PI / 2.5
	var bm := SphereMesh.new()
	bm.radius = 0.06
	bm.height = 0.12
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.2, 0.15)
	bulb = _mesh(bm, red, Vector3(0.45, MAST_H + 1.02, -0.35))
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.2)
	light.omni_range = 3.0
	light.position = bulb.position
	add_child(light)


func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _process(dt: float) -> void:
	_t += dt
	var on := fmod(_t, 1.4) < 0.25
	bulb.visible = on
	light.light_energy = 1.5 if on else 0.0
