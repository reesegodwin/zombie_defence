# Low-poly pine woods on both sides of the lane, so the only way in is the front.
# Generated from a seed with MultiMesh (one draw call per part), and shown in the
# editor too. Change the seed or density in the Inspector to re-roll it.
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")

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
	for y in range(-6, D.N + 6):
		for x in range(-8, D.N + 8):
			if x >= D.X0 - 1 and x <= D.X1 and y <= D.WALL_Y + 0.5:
				continue  # the lane and the rocks by the wall
			if x >= D.X0 and x < D.X1:
				continue  # behind the wall: the base
			var near := x == D.X0 - 2 or x == D.X1 + 1 or x == D.X0 - 1 or x == D.X1
			var p := (0.9 if near else 0.6) if y <= D.WALL_Y else (0.45 if near else 0.3)
			if rng.randf() < p * density:
				spots.append(Vector3(x + 0.5 + rng.randf_range(-0.3, 0.3), 0, y + 0.5 + rng.randf_range(-0.3, 0.3)))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08
	trunk.bottom_radius = 0.12
	trunk.height = 0.8
	trunk.radial_segments = 6
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.7
	cone.height = 1.1
	cone.radial_segments = 7
	var trunks := _multimesh(trunk, trunk_material, spots.size(), false)
	var cones := _multimesh(cone, needle_material, spots.size() * 3, true)
	for i in spots.size():
		var s := rng.randf_range(0.8, 1.35)
		var yaw := rng.randf() * TAU
		var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), spots[i])
		trunks.multimesh.set_instance_transform(i, base.translated_local(Vector3(0, 0.4, 0)))
		var tint := Color(0.09, 0.2, 0.11).lerp(Color(0.17, 0.3, 0.13), rng.randf())
		for k in 3:
			var ks := 1.0 - k * 0.24
			var t := Transform3D(Basis(Vector3.UP, yaw + k).scaled(Vector3(ks, 1.0, ks) * s), spots[i] + Vector3(0, (0.95 + k * 0.62) * s, 0))
			cones.multimesh.set_instance_transform(i * 3 + k, t)
			cones.multimesh.set_instance_color(i * 3 + k, tint.lightened(k * 0.08))


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
