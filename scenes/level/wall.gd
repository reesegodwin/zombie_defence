# The wall across the lane. Built from one block per tile so damage, flashes and
# the final collapse can happen block by block. Runs in the editor too (@tool),
# so you can see it while laying out the level.
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")

@export var height := 1.15
@export var thickness := 0.6
@export_group("Materials")
@export var timber_material: Material
@export var stone_material: Material
@export var steel_material: Material
@export var wire_material: Material

var blocks: Array[Node3D] = []
var hurt_until: Array[float] = []
var wire_rows: Array[Node3D] = []
var _stage := -1
var _fallen := false
var _flash: StandardMaterial3D
var _wear := []


func _ready() -> void:
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.albedo_color = Color(1, 0.95, 0.85, 0.55)
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	blocks.clear()
	hurt_until.clear()
	wire_rows.clear()
	_wear.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var body := BoxMesh.new()
	body.size = Vector3(1.0, height, thickness)
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.36, 0.26, thickness)
	for i in D.X1 - D.X0:
		var b := Node3D.new()
		b.name = "Block%d" % i
		# Pivot at the inner bottom edge, so a block topples into the base.
		b.position = Vector3(D.X0 + i + 0.5, 0, D.WALL_Y + thickness)
		add_child(b)
		var m := MeshInstance3D.new()
		m.name = "Body"
		m.mesh = body
		m.position = Vector3(0, height / 2, -thickness / 2)
		b.add_child(m)
		for k in 2:
			var mm := MeshInstance3D.new()
			mm.name = "Merlon%d" % k
			mm.mesh = merlon
			mm.position = Vector3(-0.25 + k * 0.5, height + 0.13, -thickness / 2)
			b.add_child(mm)
		blocks.append(b)
		hurt_until.append(0.0)
		_wear.append(rng.randf())
	# Barbed wire: posts and three strands along the outside.
	for r in 3:
		var row := Node3D.new()
		row.name = "Wire%d" % r
		row.visible = Engine.is_editor_hint()
		add_child(row)
		var strand := CylinderMesh.new()
		strand.top_radius = 0.012
		strand.bottom_radius = 0.012
		strand.height = D.X1 - D.X0 - 0.2
		strand.radial_segments = 4
		var s := MeshInstance3D.new()
		s.mesh = strand
		s.material_override = wire_material
		s.rotation.z = PI / 2
		s.position = Vector3((D.X0 + D.X1) / 2.0, 0.3 + r * 0.25, D.WALL_Y - 0.35 - r * 0.08)
		row.add_child(s)
		var barb := BoxMesh.new()
		barb.size = Vector3(0.1, 0.02, 0.02)
		for k in (D.X1 - D.X0) * 3:
			var bm := MeshInstance3D.new()
			bm.mesh = barb
			bm.material_override = wire_material
			bm.position = Vector3(D.X0 + 0.2 + k / 3.0, s.position.y, s.position.z)
			bm.rotation = Vector3(0, 0, PI / 4 if k % 2 == 0 else -PI / 4)
			row.add_child(bm)
		wire_rows.append(row)
	_stage = -1
	_apply_stage(0)


func _apply_stage(stage: int) -> void:
	if stage == _stage:
		return
	_stage = stage
	var mat: Material = timber_material
	if stage >= 3:
		mat = steel_material
	elif stage >= 1:
		mat = stone_material
	for b in blocks:
		for m in b.get_children():
			m.material_override = mat


## Called every frame with the game, to match the wall's state.
func sync(g, now: float) -> void:
	_apply_stage(g.wall["stage"])
	var frac: float = g.wall["hp"] / g.wall["max_hp"]
	var hurt: Array = g.wall["hurt"]
	for i in blocks.size():
		if hurt[i] > 0.12:
			hurt_until[i] = now + 0.12
		var b := blocks[i]
		if _fallen:
			continue
		var flash := now < hurt_until[i]
		var overlay: Material = _flash if flash else null
		for m in b.get_children():
			if m.material_overlay != overlay:
				m.material_overlay = overlay
		# Blocks get battered as the wall weakens: they sag, lean and lose merlons.
		var battered: float = clampf((1.0 - frac) * 1.6 - _wear[i], 0.0, 1.0)
		b.rotation.z = (_wear[i] - 0.5) * 0.12 * battered
		b.rotation.x = -0.05 * battered
		b.scale.y = 1.0 - 0.18 * battered
		b.get_child(1).visible = battered < 0.5
		b.get_child(2).visible = battered < 0.8
	var rows := int(ceil(g.mods["wire"] / 8.0))
	for r in wire_rows.size():
		wire_rows[r].visible = r < rows


## The wall gives way: every block topples into the base.
func collapse(at_x: float) -> void:
	_fallen = true
	for i in blocks.size():
		var b := blocks[i]
		var d := absf(b.position.x - at_x)
		var tw := create_tween()
		tw.tween_interval(d * 0.05)
		tw.tween_property(b, "rotation:x", 1.35 + randf() * 0.2, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(b, "rotation:z", randf_range(-0.3, 0.3), 0.5)


func reset() -> void:
	_fallen = false
	for i in blocks.size():
		blocks[i].rotation = Vector3.ZERO
		blocks[i].scale = Vector3.ONE
		for m in blocks[i].get_children():
			m.visible = true
	_stage = -1
	_apply_stage(0)
