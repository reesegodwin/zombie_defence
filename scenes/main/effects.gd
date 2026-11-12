# Draws the simulation's short-lived things: debris and sparks, bullet tracers,
# grenades and firebombs in flight (all MultiMesh, one draw call each), plus
# fires, explosions and blood marks on the ground (scenes and decals).
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")

@export var fire_scene: PackedScene
@export var explosion_scene: PackedScene
@export var blood_textures: Array[Texture2D] = []
## Blood marks kept on the ground before the oldest are recycled.
@export var max_blood := 90
## Pixel heights in the simulation become metres at this scale.
@export var height_scale := 0.06

@onready var debris: MultiMeshInstance3D = $Debris
@onready var sparks: MultiMeshInstance3D = $Sparks
@onready var tracers: MultiMeshInstance3D = $Tracers
@onready var projectiles: MultiMeshInstance3D = $Projectiles
@onready var blood_root: Node3D = $Blood
@onready var fire_root: Node3D = $Fires

var fires := {}           # fire id -> fire node
var _blood: Array[Decal] = []


func bind(g) -> void:
	g.exploded.connect(_on_exploded)
	g.zombie_died.connect(_on_zombie_died)


func clear() -> void:
	for f in fires.values():
		f.queue_free()
	fires.clear()
	for b in _blood:
		b.queue_free()
	_blood.clear()


func sync(g) -> void:
	_sync_parts(g.parts)
	_sync_tracers(g.bullets)
	_sync_projectiles(g.shots)
	_sync_fires(g.fires)


func _sync_parts(parts: Array) -> void:
	var a: MultiMesh = debris.multimesh
	var b: MultiMesh = sparks.multimesh
	var na := 0
	var nb := 0
	for p in parts:
		var glow: bool = p["glow"]
		var mm := b if glow else a
		var i := nb if glow else na
		if i >= mm.instance_count:
			continue
		var s: float = p["size"] * 0.032
		var life: float = clampf(p["life"] / p["max"] * 1.5, 0.0, 1.0)
		if glow:
			s *= 0.6 + 0.4 * life
		var basis := Basis(Vector3(p["vx"], 1.0, p["vy"]).normalized(), p["life"] * 9.0).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p["x"], p["z"] * height_scale + s * 0.5 + Terrain.sample(p["x"], p["y"]), p["y"])))
		var c: Color = p["color"]
		c.a = life
		mm.set_instance_color(i, c)
		if glow:
			nb += 1
		else:
			na += 1
	a.visible_instance_count = na
	b.visible_instance_count = nb


## Bullets in flight, drawn as short glowing streaks trailing back toward
## the gun they came from.
func _sync_tracers(list: Array) -> void:
	var mm: MultiMesh = tracers.multimesh
	var n := 0
	for b in list:
		if n >= mm.instance_count:
			break
		var tail: float = minf(STREAK, b["flown"])
		if tail < 0.05:
			tail = 0.05
		var head := Vector3(b["x"], b["h"] + Terrain.sample(b["x"], b["y"]), b["y"])
		var bx: float = b["x"] - b["dx"] * tail
		var by: float = b["y"] - b["dy"] * tail
		var back := Vector3(bx, b["h"] - b["drop"] * tail + Terrain.sample(bx, by), by)
		var dir := head - back
		var length := dir.length()
		var w: float = b["w"] * 0.045
		var basis := Basis.looking_at(dir / length, Vector3.UP) * Basis.from_scale(Vector3(w, w, length))
		mm.set_instance_transform(n, Transform3D(basis, (head + back) * 0.5))
		mm.set_instance_color(n, Color(1.0, 0.78, 0.38, 1.0))
		n += 1
	mm.visible_instance_count = n


const STREAK := 1.2   # metres of glowing streak behind each bullet


func _sync_projectiles(shots: Array) -> void:
	var mm: MultiMesh = projectiles.multimesh
	var n := 0
	for sh in shots:
		if n >= mm.instance_count:
			break
		var k: float = clampf(sh["t"] / sh["dur"], 0.0, 1.0)
		var h: float = sh.get("h0", 1.7) * (1.0 - k) + sin(k * PI) * 3.2
		var pos := Vector3(lerpf(sh["x0"], sh["x1"], k), h + Terrain.sample(sh["x1"], sh["y1"]) * k, lerpf(sh["y0"], sh["y1"], k))
		var spin := Basis(Vector3.RIGHT, k * 14.0).scaled(Vector3.ONE * 0.13)
		mm.set_instance_transform(n, Transform3D(spin, pos))
		var molotov: bool = sh["kind"] == "molotov"
		mm.set_instance_color(n, Color(1.0, 0.55, 0.15) if molotov else Color(0.25, 0.3, 0.18))
		n += 1
	mm.visible_instance_count = n


func _sync_fires(list: Array) -> void:
	var alive := {}
	for f in list:
		var id: int = f["id"]
		alive[id] = true
		if not fires.has(id):
			var node: Node3D = fire_scene.instantiate()
			node.radius = f["r"]
			fire_root.add_child(node)
			node.position = Vector3(f["x"], 0.02 + Terrain.sample(f["x"], f["y"]), f["y"])
			fires[id] = node
		var fn = fires[id]
		fn.fade = clampf(f["life"] / 0.8, 0.0, 1.0)
	for id in fires.keys():
		if not alive.has(id):
			fires[id].burn_out()
			fires.erase(id)


func _on_exploded(x: float, y: float, _radius: float) -> void:
	var e: Node3D = explosion_scene.instantiate()
	add_child(e)
	e.position = Vector3(x, 0.02 + Terrain.sample(x, y), y)


func _on_zombie_died(x: float, y: float, type: String) -> void:
	if blood_textures.is_empty():
		return
	var d: Decal
	if _blood.size() >= max_blood:
		d = _blood.pop_front()
	else:
		d = Decal.new()
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.cull_mask = 1
		blood_root.add_child(d)
	d.texture_albedo = blood_textures.pick_random()
	var s: float = D.ZTYPES[type]["scale"] * randf_range(0.9, 1.5)
	d.size = Vector3(s, 0.6, s)
	var bx := x + randf_range(-0.15, 0.15)
	var bz := y + randf_range(0.0, 0.4)
	d.position = Vector3(bx, Terrain.sample(bx, bz), bz)
	d.rotation.y = randf() * TAU
	d.modulate = Color(1, 1, 1, randf_range(0.75, 1.0))
	_blood.append(d)
