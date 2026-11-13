# The wall across the lane. Built from one block per tile so damage, flashes and
# the final collapse can happen block by block. Each block has three looks, one
# per wall tier (fence, wooden wall, stone wall), and shows the current one.
# One script serves all three walls: "side" picks the lane (0 front, 1 west,
# 2 east). The node sits in the lane's frame, so locally x runs along the wall
# and z towards the base. Runs in the editor too (@tool).
@tool
extends Node3D

const D = preload("res://scripts/defs.gd")

## Which wall this is: 0 front, 1 west, 2 east (see D.LANES).
@export_range(0, 2) var side := 0:
	set(v):
		side = v
		if is_inside_tree():
			_build()
## Build a walkway behind it (the front one is part of the level).
@export var build_walkway := false
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
var _fallen: Array[bool] = []   # per block: toppled with its broken section
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
	# Sit in the lane's frame: local x along the wall, local z towards the base.
	var L: Dictionary = D.LANES[side]
	var n: Vector2 = L["n"]
	transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(L["o"].x, 0, L["o"].y))
	var u0: float = L["u0"]
	var u1: float = L["u1"]
	blocks.clear()
	_fallen.clear()
	hurt_until.clear()
	wire_rows.clear()
	_wear.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var body := BoxMesh.new()
	body.size = Vector3(1.0, height, thickness)
	var stone_body := BoxMesh.new()
	stone_body.size = Vector3(1.0, height * 1.15, thickness * 1.1)
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.36, 0.26, thickness)
	var picket := BoxMesh.new()
	picket.size = Vector3(0.16, 0.95, 0.1)
	var rail := BoxMesh.new()
	rail.size = Vector3(1.0, 0.08, 0.06)
	if build_walkway:
		# Planks on posts, like the front walkway (base_props.gd).
		var deck := MeshInstance3D.new()
		deck.mesh = load("res://scenes/level/base_props.gd")._walkway(u1 - u0)
		deck.material_override = load("res://scenes/level/culvert.gd")._material()
		deck.position = Vector3((u0 + u1) / 2, D.DECK_H / 2, D.WALK_Y + 0.05)
		add_child(deck)
	for i in int(u1 - u0):
		var b := Node3D.new()
		b.name = "Block%d" % i
		# Pivot at the inner bottom edge, so a block topples into the base.
		b.position = Vector3(u0 + i + 0.5, 0, D.WALL_Y + thickness)
		add_child(b)
		# Tier 0: a fence of pickets on two rails. The first child of each
		# look stays up; the rest fall away as the wall gets battered.
		var fence := Node3D.new()
		fence.name = "Fence"
		b.add_child(fence)
		for y in [0.3, 0.7]:
			_part(fence, rail, timber_material, Vector3(0, y, -thickness * 0.5 - 0.06))
		for k in 3:
			_part(fence, picket, timber_material, Vector3(-0.33 + k * 0.33, 0.475, -thickness * 0.5)).rotation.z = rng.randf_range(-0.06, 0.06)
		# Tier 1: the wooden wall, and tier 2: stone, both with merlons.
		for t in 2:
			var look := Node3D.new()
			look.name = "Wood" if t == 0 else "Stone"
			b.add_child(look)
			var mat: Material = timber_material if t == 0 else stone_material
			var h := height if t == 0 else height * 1.15
			_part(look, body if t == 0 else stone_body, mat, Vector3(0, h / 2, -thickness / 2))
			for k in 2:
				_part(look, merlon, mat, Vector3(-0.25 + k * 0.5, h + 0.13, -thickness / 2))
		blocks.append(b)
		_fallen.append(false)
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
		strand.height = u1 - u0 - 0.2
		strand.radial_segments = 4
		var s := MeshInstance3D.new()
		s.mesh = strand
		s.material_override = wire_material
		s.rotation.z = PI / 2
		s.position = Vector3((u0 + u1) / 2.0, 0.3 + r * 0.25, D.WALL_Y - 0.35 - r * 0.08)
		row.add_child(s)
		var barb := BoxMesh.new()
		barb.size = Vector3(0.1, 0.02, 0.02)
		for k in int(u1 - u0) * 3:
			var bm := MeshInstance3D.new()
			bm.mesh = barb
			bm.material_override = wire_material
			bm.position = Vector3(u0 + 0.2 + k / 3.0, s.position.y, s.position.z)
			bm.rotation = Vector3(0, 0, PI / 4 if k % 2 == 0 else -PI / 4)
			row.add_child(bm)
		wire_rows.append(row)
	_stage = -1
	_apply_stage(0)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _apply_stage(stage: int) -> void:
	if stage == _stage:
		return
	_stage = stage
	for b in blocks:
		for t in 3:
			b.get_child(t).visible = t == stage


## Called every frame with the game, to match the wall's state.
func sync(g, now: float) -> void:
	var w: Dictionary = g.walls[side]
	_apply_stage(w["stage"])
	var segs: Array = w.get("segs", [])
	var hurt: Array = w["hurt"]
	for i in blocks.size():
		if hurt[i] > 0.12:
			hurt_until[i] = now + 0.12
		var b := blocks[i]
		if _fallen[i]:
			continue
		var frac := 1.0
		if not segs.is_empty():
			var sg: Dictionary = segs[_seg_of(i, segs.size())]
			frac = sg["hp"] / sg["max_hp"]
		var flash := now < hurt_until[i]
		var overlay: Material = _flash if flash else null
		var look: Node3D = b.get_child(clampi(_stage, 0, 2))
		for m in look.get_children():
			if m.material_overlay != overlay:
				m.material_overlay = overlay
		# Blocks get battered as the wall weakens: they sag, lean and lose bits.
		var battered: float = clampf((1.0 - frac) * 1.6 - _wear[i], 0.0, 1.0)
		b.rotation.z = (_wear[i] - 0.5) * 0.12 * battered
		b.rotation.x = -0.05 * battered
		b.scale.y = 1.0 - 0.18 * battered
		var n := look.get_child_count()
		for k in range(1, n):
			look.get_child(k).visible = battered < 1.0 - float(k) / n * 0.6
	for r in wire_rows.size():   # (wire is laid on the ground now: see the wire trap)
		wire_rows[r].visible = false


## Which wall section (of n, as the game's seg_at) block i is part of.
func _seg_of(i: int, n: int) -> int:
	var L: Dictionary = D.LANES[side]
	var sl: float = (L["u1"] - L["u0"]) / n
	return clampi(floori((blocks[i].position.x - L["u0"]) / sl), 0, n - 1)


func _seg_count() -> int:
	var L: Dictionary = D.LANES[side]
	return maxi(1, roundi((L["u1"] - L["u0"]) / D.WALL_SEG))


## A section of the wall gives way: the blocks of the section at at_x (along
## the wall, u) topple into the base, leaving a gap; the blocks either side of
## it shake; the rest stands.
func collapse(at_x: float) -> void:
	var n := _seg_count()
	var L: Dictionary = D.LANES[side]
	var gone := clampi(floori((at_x - L["u0"]) / ((L["u1"] - L["u0"]) / n)), 0, n - 1)
	for i in blocks.size():
		var b := blocks[i]
		var k := _seg_of(i, n)
		if _fallen[i]:
			continue
		var d := absf(b.position.x - at_x)
		if k != gone:
			if absf(k - gone) > 1:
				continue
			var shake := create_tween()
			shake.tween_property(b, "rotation:z", randf_range(-0.06, 0.06), 0.15)
			shake.tween_property(b, "rotation:x", randf_range(0.0, 0.08), 0.2)
			continue
		_fallen[i] = true
		var tw := create_tween()
		tw.tween_interval(d * 0.05)
		tw.tween_property(b, "rotation:x", 1.35 + randf() * 0.2, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(b, "rotation:z", randf_range(-0.3, 0.3), 0.5)


## A broken section patched: the blocks of the section at at_x stand again.
func restore(at_x: float) -> void:
	var n := _seg_count()
	var L: Dictionary = D.LANES[side]
	var k := clampi(floori((at_x - L["u0"]) / ((L["u1"] - L["u0"]) / n)), 0, n - 1)
	for i in blocks.size():
		if _seg_of(i, n) == k:
			_fallen[i] = false
			blocks[i].rotation = Vector3.ZERO
			blocks[i].scale = Vector3.ONE


func reset() -> void:
	for i in blocks.size():
		_fallen[i] = false
		blocks[i].rotation = Vector3.ZERO
		blocks[i].scale = Vector3.ONE
		for look in blocks[i].get_children():
			for m in look.get_children():
				m.visible = true
	_stage = -1
	_apply_stage(0)
