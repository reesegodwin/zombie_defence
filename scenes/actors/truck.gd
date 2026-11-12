# The army truck that comes at the dawn after the last night: a six-wheeled
# olive lorry with a long bonnet, a grille guard and a canvas-covered back.
# It backs down the mountain pass into the yard, waits while the crew climb in
# at the tailgate, then drives off up the pass. Its position comes from the
# game's evac clocks, so it also turns up right in a run loaded halfway
# through (see at()).
extends Node3D

const D = preload("res://scripts/defs.gd")
const Game = preload("res://scripts/game.gd")
const Guns = preload("res://scenes/actors/guns.gd")
const Terrain = preload("res://scripts/terrain.gd")

const OLIVE := Color(0.27, 0.33, 0.19)
const CANVAS := Color(0.5, 0.5, 0.32)
const TYRE := Color(0.06, 0.06, 0.06)
const HUB := Color(0.55, 0.56, 0.55)
const GLASS := Color(0.32, 0.36, 0.38)
const DARK := Color(0.08, 0.08, 0.07)
const WHEEL_R := 0.55
const START := Vector2(12.1, 56.0)   # where it starts out, round the bend up the pass
const LOOK := 1.6                    # how far ahead it steers (metres)

var wheels: Array[MeshInstance3D] = []
var lamp: SpotLight3D


func _ready() -> void:
	var k := Guns.Kit.new()
	k.wear = 0.3
	k.rng.seed = 5
	var olive_dk := OLIVE.darkened(0.25)
	# Chassis rails, front (-z) to back.
	for sx in [-0.45, 0.45]:
		k.box(Vector3(sx, 0.78, 0.0), Vector3(0.16, 0.22, 5.9), DARK)
	# The long bonnet, sloping down to the grille.
	k.box(Vector3(0, 1.32, -2.3), Vector3(1.5, 0.62, 1.35), OLIVE)
	k.box(Vector3(0, 1.66, -2.2), Vector3(1.36, 0.1, 1.2), OLIVE.lightened(0.04), Vector3(-0.12, 0, 0))
	k.box(Vector3(0, 1.73, -2.55), Vector3(0.28, 0.08, 0.3), OLIVE.darkened(0.1))   # the vent on top
	# Grille, bars and a guard frame in front of it.
	k.box(Vector3(0, 1.25, -2.99), Vector3(1.3, 0.78, 0.04), DARK)
	for i in 7:
		k.box(Vector3(-0.54 + i * 0.18, 1.25, -3.02), Vector3(0.05, 0.72, 0.04), Color(0.2, 0.21, 0.19))
	for sx in [-0.72, 0.72]:
		k.box(Vector3(sx, 1.2, -3.1), Vector3(0.07, 0.95, 0.07), DARK)
	k.box(Vector3(0, 1.66, -3.1), Vector3(1.5, 0.07, 0.07), DARK)
	k.box(Vector3(0, 0.78, -3.12), Vector3(2.1, 0.22, 0.18), Color(0.12, 0.12, 0.11))   # bumper
	for sx in [-0.8, 0.8]:
		k.box(Vector3(sx, 0.68, -3.24), Vector3(0.12, 0.1, 0.12), DARK)   # tow hooks
		k.cyl(Vector3(sx * 1.02, 1.2, -2.9), 0.1, 0.1, Color(1.0, 0.93, 0.7), 8)   # headlamps
		k.box(Vector3(sx * 1.08, 1.75, -2.85), Vector3(0.02, 0.5, 0.02), DARK, Vector3(0.15, 0, 0))   # whip aerials
	# Big flared front fenders over the front wheels.
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx, 1.33, -2.05), Vector3(0.5, 0.1, 1.15), OLIVE)
		k.box(Vector3(sx, 1.13, -2.78), Vector3(0.5, 0.1, 0.5), OLIVE, Vector3(-0.75, 0, 0))
		k.box(Vector3(sx, 1.15, -1.35), Vector3(0.5, 0.1, 0.45), OLIVE, Vector3(0.7, 0, 0))
		k.box(Vector3(sx * 1.1, 0.95, -1.05), Vector3(0.28, 0.08, 0.35), olive_dk)   # step
	# The cab: windscreen in two panes, side windows, mirrors on arms, a star on each door.
	k.box(Vector3(0, 1.85, -1.08), Vector3(2.0, 1.45, 1.25), OLIVE)
	k.box(Vector3(0, 2.6, -1.08), Vector3(1.9, 0.07, 1.18), OLIVE.darkened(0.08))
	for sx in [-0.43, 0.43]:
		k.box(Vector3(sx, 2.15, -1.71), Vector3(0.74, 0.55, 0.02), GLASS)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.005, 2.15, -1.0), Vector3(0.02, 0.5, 0.65), GLASS)
		k.box(Vector3(sx * 1.005, 1.6, -1.0), Vector3(0.02, 0.32, 0.32), Color(0.85, 0.85, 0.8), Vector3(PI / 4, 0, 0))
		k.box(Vector3(sx * 1.15, 2.2, -1.62), Vector3(0.3, 0.04, 0.04), DARK)
		k.box(Vector3(sx * 1.28, 2.2, -1.62), Vector3(0.06, 0.3, 0.16), DARK)
		# Behind the cab: louvred radiator box and the fuel tank.
		k.box(Vector3(sx * 0.95, 1.25, -0.2), Vector3(0.18, 0.75, 0.6), olive_dk)
		for i in 6:
			k.box(Vector3(sx * 1.05, 0.98 + i * 0.1, -0.2), Vector3(0.02, 0.04, 0.54), DARK)
		k.cyl(Vector3(sx * 0.82, 0.78, 0.35), 0.24, 0.8, DARK, 10)
	# The bed: floor, slatted sides, tailgate.
	var bed_z := 1.38
	var bed_l := 3.4
	k.box(Vector3(0, 1.17, bed_z), Vector3(2.2, 0.16, bed_l), olive_dk)
	for sx in [-1.08, 1.08]:
		k.box(Vector3(sx, 1.55, bed_z), Vector3(0.06, 0.6, bed_l), OLIVE)
		for i in 6:
			k.box(Vector3(sx * 1.02, 1.55, bed_z - bed_l / 2 + 0.12 + i * 0.63), Vector3(0.06, 0.6, 0.08), olive_dk)
		k.box(Vector3(sx * 1.03, 1.86, bed_z), Vector3(0.06, 0.06, bed_l), olive_dk)
		k.box(Vector3(sx * 0.98, 0.98, 2.42), Vector3(0.36, 0.42, 0.04), DARK)   # mud flaps
	k.box(Vector3(0, 1.55, bed_z - bed_l / 2), Vector3(2.2, 0.6, 0.06), OLIVE)
	k.box(Vector3(0, 1.4, bed_z + bed_l / 2), Vector3(2.2, 0.32, 0.06), OLIVE)   # tailgate
	# The canvas: straight sides, a rounded top, ropes along it.
	k.box(Vector3(0, 2.32, bed_z), Vector3(2.12, 0.95, bed_l - 0.08), CANVAS)
	k.box(Vector3(0, 2.92, bed_z), Vector3(1.4, 0.3, bed_l - 0.08), CANVAS.lightened(0.04))
	for sx in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.82, 2.8, bed_z), Vector3(0.5, 0.3, bed_l - 0.08), CANVAS.lightened(0.02), Vector3(0, 0, sx * -0.65))
	for i in 5:
		k.box(Vector3(0, 2.6, bed_z - bed_l / 2 + 0.4 + i * 0.65), Vector3(2.15, 0.7, 0.04), CANVAS.darkened(0.12))
	k.box(Vector3(0, 2.25, bed_z + bed_l / 2 - 0.02), Vector3(1.6, 1.0, 0.03), Color(0.05, 0.05, 0.04))   # the open back
	var mat := Guns.material()
	var body := MeshInstance3D.new()
	body.mesh = k.mesh()
	body.material_override = mat
	add_child(body)
	# Six big wheels, which turn as it drives.
	var wk := Guns.Kit.new()
	wk.cyl(Vector3.ZERO, WHEEL_R, 0.42, TYRE, 14, Vector3(0, PI / 2, 0))
	wk.cyl(Vector3.ZERO, 0.3, 0.44, HUB, 10, Vector3(0, PI / 2, 0))
	wk.box(Vector3.ZERO, Vector3(0.46, 0.08, 0.36), DARK)
	wk.box(Vector3.ZERO, Vector3(0.46, 0.36, 0.08), DARK)
	var wmesh := wk.mesh()
	for z in [-2.05, 1.0, 2.15]:
		for sx in [-0.92, 0.92]:
			var w := MeshInstance3D.new()
			w.mesh = wmesh
			w.material_override = mat
			w.position = Vector3(sx, WHEEL_R, z)
			add_child(w)
			wheels.append(w)
	# Headlights on the way out (cheap: no shadows).
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 1.3, -3.2)
	lamp.light_color = Color(1.0, 0.92, 0.72)
	lamp.light_energy = 3.0
	lamp.spot_range = 14.0
	lamp.spot_angle = 32.0
	lamp.spot_attenuation = 0.6
	lamp.rotation.x = -0.12
	add_child(lamp)


## The road through the pass: from round the bend down to where it parks.
static func route() -> Array:
	var pts: Array = [START]
	for i in range(D.PASS_PATH.size() - 1, 0, -1):
		pts.append(D.PASS_PATH[i])
	pts.append(Game.TRUCK_STOP)
	return pts


static func _length(pts: Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


static func _point(pts: Array, d: float) -> Vector2:
	if d <= 0.0:
		return pts[0] + (pts[0] - pts[1]).normalized() * -d
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if d <= seg:
			return pts[i - 1].lerp(pts[i], d / seg)
		d -= seg
	return pts[-1] + (pts[-1] - pts[-2]).normalized() * d


## Places it for the evac clocks: evac (seconds since it was called) backing
## down the pass into the yard, then parked; go (seconds since it pulled away,
## -1 before) driving forward up the pass and out of sight.
func at(evac: float, go: float) -> void:
	var pts := route()
	var total := _length(pts)
	var d: float
	var facing: Vector2
	if go < 0.0:
		var f := clampf(evac / Game.TRUCK_ARRIVES, 0.0, 1.0)
		d = total * (1.0 - pow(1.0 - f, 2.2))   # slows as it backs up to the stop
		# Reversing: the nose points back the way it came.
		facing = _point(pts, d - LOOK) - _point(pts, d + LOOK)
	else:
		d = total - minf(0.8 * go * go + 0.6 * go, total + 20.0)
		facing = _point(pts, d - LOOK) - _point(pts, d + LOOK)
	var p := _point(pts, d)
	position = Vector3(p.x, Terrain.sample(p.x, p.y), p.y)
	rotation.y = atan2(-facing.x, -facing.y)
	for w in wheels:
		w.rotation.x = d / WHEEL_R
	lamp.visible = go >= 0.0 or evac < Game.TRUCK_ARRIVES
