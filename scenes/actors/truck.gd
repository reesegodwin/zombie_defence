# The army truck that comes at the dawn after the last night: an olive cab
# and a canvas-covered back on six wheels. It drives down the mountain pass
# into the yard, waits while the crew climb on, and the next level begins.
# Its position comes from the game's evac clock, so it also turns up right in
# a run loaded halfway through (see at()).
extends Node3D

const D = preload("res://scripts/defs.gd")
const Guns = preload("res://scenes/actors/guns.gd")
const Terrain = preload("res://scripts/terrain.gd")

const OLIVE := Color(0.29, 0.33, 0.2)
const CANVAS := Color(0.38, 0.4, 0.27)
const TYRE := Color(0.07, 0.07, 0.07)
const GLASS := Color(0.15, 0.22, 0.26)
const STOP := Vector2(11.2, 24.2)     # where it waits, in the yard past the gate

var wheels: Array[MeshInstance3D] = []


func _ready() -> void:
	var k := Guns.Kit.new()
	k.wear = 0.35
	k.rng.seed = 5
	# Chassis, and the cab at the front (-z, the way it drives).
	k.box(Vector3(0, 0.62, 0.2), Vector3(1.9, 0.16, 4.4), OLIVE.darkened(0.35))
	k.box(Vector3(0, 1.25, -1.45), Vector3(1.95, 1.1, 1.1), OLIVE)                 # cab
	k.box(Vector3(0, 0.95, -2.2), Vector3(1.85, 0.55, 0.5), OLIVE.darkened(0.08))   # bonnet
	k.box(Vector3(0, 0.92, -2.46), Vector3(1.2, 0.42, 0.04), Color(0.12, 0.12, 0.1))   # grille
	for sx in [-0.7, 0.7]:
		k.box(Vector3(sx, 0.98, -2.47), Vector3(0.18, 0.18, 0.04), Color(1.0, 0.92, 0.6))   # lamps
	k.box(Vector3(0, 1.5, -2.005), Vector3(1.7, 0.45, 0.02), GLASS)                # windscreen
	for sx in [-0.981, 0.981]:
		k.box(Vector3(sx, 1.5, -1.45), Vector3(0.02, 0.4, 0.7), GLASS)
	k.box(Vector3(0, 0.62, -2.55), Vector3(2.0, 0.14, 0.12), OLIVE.darkened(0.5))  # bumper
	# A white star on the doors.
	for sx in [-0.99, 0.99]:
		k.box(Vector3(sx, 1.1, -1.35), Vector3(0.02, 0.3, 0.3), Color(0.85, 0.85, 0.8), Vector3(PI / 4, 0, 0))
	# The back: a bed and a canvas cover on hoops.
	k.box(Vector3(0, 0.95, 0.8), Vector3(2.0, 0.5, 3.0), OLIVE.darkened(0.12))
	k.box(Vector3(0, 1.75, 0.8), Vector3(2.0, 1.1, 3.0), CANVAS)
	k.box(Vector3(0, 2.32, 0.8), Vector3(1.7, 0.12, 3.0), CANVAS.lightened(0.05))
	for z in [-0.6, 0.3, 1.2, 2.2]:
		k.box(Vector3(0, 1.75, z), Vector3(2.03, 1.12, 0.05), CANVAS.darkened(0.15))
	k.box(Vector3(0, 1.6, 2.31), Vector3(1.4, 0.9, 0.02), Color(0.06, 0.06, 0.05))  # the open back
	var mat := Guns.material()
	var body := MeshInstance3D.new()
	body.mesh = k.mesh()
	body.material_override = mat
	add_child(body)
	# Wheels, which turn as it drives.
	var wk := Guns.Kit.new()
	wk.cyl(Vector3.ZERO, 0.42, 0.32, TYRE, 12, Vector3(0, PI / 2, 0))
	wk.cyl(Vector3.ZERO, 0.22, 0.34, OLIVE.darkened(0.3), 8, Vector3(0, PI / 2, 0))
	var wmesh := wk.mesh()
	for z in [-1.7, 0.5, 1.6]:
		for sx in [-0.95, 0.95]:
			var w := MeshInstance3D.new()
			w.mesh = wmesh
			w.material_override = mat
			w.position = Vector3(sx, 0.42, z)
			add_child(w)
			wheels.append(w)


## The road in: down the pass to the stop.
static func route() -> Array:
	var pts: Array = []
	for i in range(D.PASS_PATH.size() - 1, 0, -1):
		pts.append(D.PASS_PATH[i])
	pts.append(STOP)
	return pts


## Places it for the evac clock t (seconds since it was called): driving in
## until arrive, then parked.
func at(t: float, arrive: float) -> void:
	var pts := route()
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var f := smoothstep(0.0, 1.0, clampf(t / arrive, 0.0, 1.0))
	var d := total * f
	var p: Vector2 = pts[-1]
	var dir := Vector2(0, -1)
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if d <= seg:
			p = pts[i - 1].lerp(pts[i], d / seg)
			dir = (pts[i] - pts[i - 1]).normalized()
			break
		d -= seg
	position = Vector3(p.x, Terrain.sample(p.x, p.y), p.y)
	rotation.y = atan2(-dir.x, -dir.y)
	for w in wheels:
		w.rotation.x = -total * f / 0.42
