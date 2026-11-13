# Shared look for placed traps: a wear bar, a highlight ring when you hover it
# with storage open, and a little animation per kind.
extends Node3D

const Terrain = preload("res://scripts/terrain.gd")
const D = preload("res://scripts/defs.gd")
const Guns = preload("res://scenes/actors/guns.gd")

static var _meshes := {}   # kind -> the strip traps' shared mesh

@export_enum("spikes", "beartrap", "mine", "slick", "wire") var kind := "spikes"

@onready var bar_fill: Node3D = $WearBar/Fill
@onready var bar: Node3D = $WearBar
@onready var highlight: MeshInstance3D = $Highlight

var uid := -1
var _slick_mat: StandardMaterial3D


func setup(t: Dictionary) -> void:
	uid = t["uid"]
	rotation.y = randf() * TAU
	if D.TRAP_SIZE.has(kind):
		_build_strip()
	if kind == "slick":
		_slick_mat = $Pool.get_surface_override_material(0).duplicate()
		$Pool.set_surface_override_material(0, _slick_mat)
	sync(t, false)


func sync(t: Dictionary, hovered: bool) -> void:
	position = Vector3(t["x"], Terrain.sample(t["x"], t["y"]), t["y"])
	if D.TRAP_SIZE.has(kind):
		var a: Vector2 = t.get("dir", Vector2.RIGHT)
		rotation.y = atan2(-a.y, a.x)   # lying along the wall, across the lane
	highlight.visible = hovered
	var frac: float = clampf(t["uses"] / t["max"], 0.0, 1.0)
	bar.visible = kind != "mine"
	bar_fill.scale.x = maxf(0.001, frac)
	bar_fill.position.x = -0.3 * (1.0 - frac)
	var cam := get_viewport().get_camera_3d()
	if cam:
		bar.global_basis = cam.global_basis
	match kind:
		"beartrap":
			var shut: bool = t["hold"] >= 0
			var target := 1.35 if shut else 0.0
			$JawA.rotation.x = lerpf($JawA.rotation.x, target, 0.4)
			$JawB.rotation.x = lerpf($JawB.rotation.x, -target, 0.4)
		"mine":
			var on := fmod(t["t"], 1.0) < 0.25
			$Bulb.visible = on
			$Blink.light_energy = 1.2 if on else 0.0
		"slick":
			_slick_mat.albedo_color.a = clampf(t["uses"] / 15.0, 0.15, 0.9)


# --- Strip traps (spike strip, wire coil), built in code -------------------------
## Replaces the scene's round look with a strip laid across the lane, the
## size the game uses for it (D.TRAP_SIZE).
func _build_strip() -> void:
	for c in get_children():
		if c.name.begins_with("Spike") or c.name == "Board":
			c.queue_free()
	var size: Vector2 = D.TRAP_SIZE[kind]
	if not _meshes.has(kind):
		_meshes[kind] = _spike_mesh(size) if kind == "spikes" else _wire_mesh(size)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	mi.material_override = Guns.material()
	add_child(mi)
	# The hover ring, stretched round the strip.
	highlight.scale = Vector3((size.x * 0.5 + 0.15) / 0.66, 0.3, (size.y * 0.5 + 0.2) / 0.66)


## A board studded with rows of spikes.
static func _spike_mesh(size: Vector2) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.5
	k.rng.seed = 11
	k.box(Vector3(0, 0.025, 0), Vector3(size.x, 0.05, size.y), Color(0.16, 0.16, 0.15))
	for edge in [-1, 1]:
		k.box(Vector3(0, 0.03, edge * size.y * 0.5), Vector3(size.x, 0.06, 0.04), Color(0.3, 0.29, 0.26))
	var cols := int(size.x / 0.2)
	for i in cols:
		for j in 3:
			var x := -size.x * 0.5 + 0.1 + i * (size.x - 0.2) / maxf(cols - 1, 1) + (0.05 if j == 1 else 0.0)
			var z := (j - 1) * size.y * 0.3
			k.cyl(Vector3(x, 0.15, z), 0.035, 0.22, Color(0.6, 0.62, 0.64), 5, Vector3(-PI / 2, 0, 0), 0.0)
	return k.mesh()


## A coil of barbed wire, one loop high, rolling along the strip like a
## stretched spring, barbs all along it, held down by two stakes.
static func _wire_mesh(size: Vector2) -> ArrayMesh:
	var k := Guns.Kit.new()
	k.wear = 0.4
	k.rng.seed = 23
	var steel := Color(0.4, 0.41, 0.4)
	var r := size.y * 0.5          # the loops' radius
	var loops := int(size.x / 0.2)  # a loop every 20 cm
	var per := 14
	var n := loops * per
	var prev := Vector3.ZERO
	for i in n + 1:
		var a := TAU * i / per
		var x := -size.x * 0.5 + size.x * i / n
		var p := Vector3(x + sin(a) * 0.05, r + cos(a) * r * 0.92, sin(a) * r)
		if i > 0:
			var d := p - prev
			var b := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
			k.cyl((p + prev) * 0.5, 0.009, d.length() + 0.004, steel, 4, b.get_euler())
			if i % 5 == 0:   # a barb: two short crossed spikes
				k.box(p, Vector3(0.006, 0.006, 0.07), steel.darkened(0.15), Vector3(0.6, a, 0.0))
				k.box(p, Vector3(0.07, 0.006, 0.006), steel.darkened(0.15), Vector3(0.0, a, 0.6))
		prev = p
	for sx in [-1, 1]:   # stakes
		k.box(Vector3(sx * (size.x * 0.5 - 0.15), r, 0), Vector3(0.04, r * 2.2, 0.04), Color(0.35, 0.25, 0.15))
	return k.mesh()
