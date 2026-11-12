# An auto-turret on a timber tower, high enough to fire over the wall. Built in
# code: the tower, and on it an old water-cooled machine gun on a motorised
# swivel base, that turns to aim, kicks back and flashes. Its look grows with
# the turret research (heavier muzzle, an ammo can and belt, a sensor camera).
extends Node3D

const Guns = preload("res://scenes/actors/guns.gd")
const TOWER_H := 1.5

var head: Node3D
var barrel: MeshInstance3D
var flash: MeshInstance3D
var light: OmniLight3D
var ammo_box: MeshInstance3D
var scope: MeshInstance3D


func _ready() -> void:
	# A tripod: three steel legs splayed out to the ground, braced, meeting in
	# a collar under the gun's swivel.
	var k := _kit(0.45, 17)
	var collar := Vector3(0, TOWER_H - 0.12, 0)
	for i in 3:
		var a := TAU * i / 3.0 + PI / 6.0
		var foot := Vector3(cos(a) * 0.75, 0.0, sin(a) * 0.75)
		var mid := (foot + collar) / 2.0
		var d := collar - foot
		var len := d.length()
		# A tube along the leg: pitch it over from upright toward the foot.
		var basis := Basis.looking_at(d.normalized(), Vector3(cos(a), 0, sin(a)).cross(Vector3.UP))
		k.cyl(mid, 0.045, len, IRON, 8, basis.get_euler())
		k.box(foot + Vector3(0, 0.03, 0), Vector3(0.22, 0.06, 0.22), IRON.darkened(0.3), Vector3(0, -a, 0))   # foot plate
		# A brace to the next leg, a third of the way up.
		var a2 := TAU * (i + 1) / 3.0 + PI / 6.0
		var p1 := foot.lerp(collar, 0.35)
		var p2 := Vector3(cos(a2) * 0.75, 0, sin(a2) * 0.75).lerp(collar, 0.35)
		var bd := p2 - p1
		k.cyl((p1 + p2) / 2.0, 0.025, bd.length(), STEEL.darkened(0.2), 6, Basis.looking_at(bd.normalized(), Vector3.UP).get_euler())
	k.cyl(collar, 0.16, 0.24, PAINT.darkened(0.1), 12, Vector3(PI / 2, 0, 0))
	k.cyl(collar + Vector3(0, 0.15, 0), 0.24, 0.06, IRON, 14, Vector3(PI / 2, 0, 0))
	_mesh(self, k.mesh(), Guns.material(), Vector3.ZERO)
	head = Node3D.new()
	head.position = Vector3(0, TOWER_H + 0.06, 0)
	add_child(head)
	var mat := Guns.material()
	_mesh(head, _gun_body(), mat, Vector3.ZERO)
	barrel = _mesh(head, _gun_barrel(), mat, Vector3(0, BORE_Y - 0.03, BARREL_Z))
	ammo_box = _mesh(head, _gun_ammo(), mat, Vector3.ZERO)
	scope = _mesh(head, _gun_sensor(), mat, Vector3.ZERO)
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.45)
	flash = _mesh(head, fm, fmat, Vector3(0, BORE_Y, MUZZLE_Z + 0.08))
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.8, 0.45)
	light.omni_range = 5.0
	light.light_energy = 0.0
	light.position = flash.position
	head.add_child(light)
	_make_bar()


# --- The gun: an old water-cooled machine gun, salvaged and motorised --------
# Built from the guns' Kit (guns.gd), weathered: rust and faded paint.

const BORE_Y := 0.44       # bore height above the head
const BARREL_Z := 0.62     # where the barrel's muzzle boss sits (it kicks back)
const MUZZLE_Z := 0.8
const PAINT := Color(0.47, 0.52, 0.4)
const IRON := Color(0.42, 0.34, 0.29)
const RUST := Color(0.45, 0.27, 0.17)
const STEEL := Color(0.55, 0.55, 0.56)


static func _kit(wear: float, seed_value: int) -> Guns.Kit:
	var k := Guns.Kit.new()
	k.wear = wear
	k.rng.seed = seed_value
	return k


## The pedestal, yoke, water jacket and receiver.
static func _gun_body() -> ArrayMesh:
	var k := _kit(0.5, 3)
	var up := Vector3(PI / 2, 0, 0)    # turns a tube to stand upright
	var side := Vector3(0, PI / 2, 0)  # turns a tube to lie across
	# Swivel base: a drum with a lip.
	k.cyl(Vector3(0, 0.07, 0), 0.3, 0.14, PAINT, 14, up)
	k.cyl(Vector3(0, 0.15, 0), 0.24, 0.04, IRON, 14, up)
	# Yoke plates and the gear on the elevation axle.
	for sx in [-0.15, 0.15]:
		k.box(Vector3(sx, 0.3, -0.06), Vector3(0.035, 0.28, 0.3), IRON, Vector3(0.15, 0, 0))
	k.cyl(Vector3(0.2, 0.36, -0.06), 0.075, 0.05, IRON, 12, side)
	k.cyl(Vector3(0.235, 0.36, -0.06), 0.03, 0.04, STEEL, 8, side)
	for i in 8:   # the gear's knurled rim
		var a := TAU * i / 8.0
		k.box(Vector3(0.2, 0.36 + sin(a) * 0.08, -0.06 + cos(a) * 0.08), Vector3(0.05, 0.02, 0.02), IRON, Vector3(a, 0, 0))
	# The traverse motor: a yellow can by the yoke.
	k.cyl(Vector3(0.22, 0.2, 0.04), 0.06, 0.18, Color(0.76, 0.62, 0.2), 10)
	k.cyl(Vector3(0.22, 0.2, 0.14), 0.035, 0.03, STEEL, 8)
	# Water jacket: the big cooling tube, its end caps and the filler cap.
	k.cyl(Vector3(0, BORE_Y, 0.27), 0.13, 0.62, PAINT, 14)
	for z in [-0.04, 0.58]:
		k.cyl(Vector3(0, BORE_Y, z), 0.138, 0.04, PAINT.darkened(0.15), 14)
	k.cyl(Vector3(0, BORE_Y + 0.13, 0.32), 0.055, 0.03, IRON, 10, up)
	k.box(Vector3(0, BORE_Y + 0.15, 0.32), Vector3(0.09, 0.012, 0.02), IRON)
	# Front sight: a fork on a post.
	k.box(Vector3(0, BORE_Y + 0.16, 0.5), Vector3(0.016, 0.07, 0.016), IRON)
	for sx in [-0.035, 0.035]:
		k.box(Vector3(sx, BORE_Y + 0.22, 0.5), Vector3(0.012, 0.07, 0.012), RUST, Vector3(0, 0, -sx * 7.0))
	# Receiver at the back, the crank drum on its side and the spade grips.
	k.box(Vector3(0, BORE_Y, -0.18), Vector3(0.22, 0.2, 0.28), IRON)
	k.cyl(Vector3(0.14, BORE_Y - 0.02, -0.18), 0.07, 0.08, IRON.darkened(0.1), 12, side)
	k.box(Vector3(0.14, BORE_Y + 0.05, -0.12), Vector3(0.06, 0.04, 0.12), IRON)
	k.box(Vector3(0, BORE_Y + 0.02, -0.34), Vector3(0.18, 0.06, 0.04), IRON)
	for sx in [-0.07, 0.07]:
		k.cyl(Vector3(sx, BORE_Y + 0.02, -0.38), 0.018, 0.12, Color(0.3, 0.22, 0.16), 6, up)
	return k.mesh()


## The muzzle boss, which kicks back when it fires (around its own origin).
static func _gun_barrel() -> ArrayMesh:
	var k := _kit(0.5, 5)
	k.cyl(Vector3(0, 0, 0.0), 0.065, 0.12, STEEL.darkened(0.3), 12)
	k.cyl(Vector3(0, 0, 0.1), 0.04, 0.1, STEEL, 10)
	k.cyl(Vector3(0, 0, 0.155), 0.03, 0.012, Color(0.05, 0.05, 0.05), 10)
	return k.mesh()


## Belt feed (research): an ammo can on the left and its belt.
static func _gun_ammo() -> ArrayMesh:
	var k := _kit(0.5, 7)
	k.box(Vector3(-0.24, BORE_Y - 0.08, -0.16), Vector3(0.14, 0.18, 0.26), Color(0.36, 0.42, 0.26))
	k.box(Vector3(-0.24, BORE_Y + 0.02, -0.16), Vector3(0.05, 0.02, 0.1), STEEL)
	for i in 5:
		k.box(Vector3(-0.15 + i * 0.008, BORE_Y + 0.02 - i * 0.01, -0.16), Vector3(0.012, 0.03, 0.08), Color(0.72, 0.55, 0.22))
	return k.mesh()


## Optics (research): a sensor camera on a bracket, with a cable.
static func _gun_sensor() -> ArrayMesh:
	var k := _kit(0.4, 9)
	k.box(Vector3(0, BORE_Y + 0.16, -0.2), Vector3(0.025, 0.12, 0.025), IRON)
	k.box(Vector3(0, BORE_Y + 0.25, -0.18), Vector3(0.16, 0.09, 0.14), IRON.darkened(0.2))
	k.box(Vector3(0, BORE_Y + 0.25, -0.1), Vector3(0.12, 0.07, 0.02), Color(0.15, 0.15, 0.16))
	k.cyl(Vector3(-0.03, BORE_Y + 0.25, -0.09), 0.026, 0.02, Color(0.35, 0.6, 0.9), 10)   # lens
	k.cyl(Vector3(-0.03, BORE_Y + 0.25, -0.082), 0.012, 0.01, Color(0.75, 0.9, 1.0), 8)
	k.box(Vector3(0.04, BORE_Y + 0.25, -0.092), Vector3(0.03, 0.03, 0.012), Color(0.5, 0.45, 0.35))
	for i in 4:   # the cable down to the receiver
		k.box(Vector3(0.09 + i * 0.012, BORE_Y + 0.22 - i * 0.04, -0.22 + i * 0.01), Vector3(0.01, 0.05, 0.01), Color(0.7, 0.68, 0.45))
	return k.mesh()


# --- Health and being torn down -------------------------------------------------

var _bar: Node3D
var _bar_fill: MeshInstance3D
var _hurt_on := false
static var _hit: StandardMaterial3D


func _make_bar() -> void:
	_bar = Node3D.new()
	_bar.position = Vector3(0, TOWER_H + 1.25, 0)
	add_child(_bar)
	for fill in [false, true]:
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 0.08)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 2 if fill else 1
		m.albedo_color = Color(0.9, 0.55, 0.15) if fill else Color(0.05, 0.05, 0.06, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bar.add_child(mi)
		if fill:
			_bar_fill = mi
	_bar.visible = false


static func _hit_mat() -> StandardMaterial3D:
	if _hit == null:
		_hit = StandardMaterial3D.new()
		_hit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit.albedo_color = Color(1.0, 0.85, 0.7, 0.45)
		_hit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _hit


func _set_overlay(m: Material) -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		if n != flash and n.get_parent() != _bar:
			n.material_overlay = m


## Torn down: the tower buckles and tips over, sinks, and is gone.
func collapse() -> void:
	_bar.visible = false
	_set_overlay(null)
	flash.visible = false
	light.light_energy = 0.0
	var dir := randf() * TAU
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "rotation", Vector3(cos(dir) * 1.2, randf_range(-0.4, 0.4), sin(dir) * 1.2), 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(head, "position:y", TOWER_H * 0.6, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", -2.5, 2.0).set_delay(1.6)
	tw.chain().tween_callback(queue_free)


func _mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


## t: the turret's state from the game; g: the game, for its upgrades.
func sync(t: Dictionary, g) -> void:
	position = Vector3(t["x"], 0, t["y"])
	# Health, once the dead have been at it; a flash when struck.
	var frac: float = clampf(t.get("hp", 1.0) / t.get("max_hp", 1.0), 0.0, 1.0)
	_bar.visible = frac < 0.999
	if _bar.visible:
		_bar_fill.scale.x = maxf(0.001, frac)
		_bar_fill.position.x = -0.4 * (1.0 - frac)
	var hurt: bool = t.get("hurt", 0.0) > 0.0
	if hurt != _hurt_on:
		_hurt_on = hurt
		_set_overlay(_hit_mat() if hurt else null)
	var ang: float = t["aim"]
	head.rotation.y = atan2(cos(ang), sin(ang))
	barrel.position.z = BARREL_Z - t["recoil"] * 0.8
	var heavy: bool = g.researched.has("turret_ammo")
	barrel.scale = Vector3(1.3, 1.3, 1.15) if heavy else Vector3.ONE
	ammo_box.visible = g.researched.has("turret_feed")
	scope.visible = g.researched.has("turret_optics")
	var firing: bool = t["flash"] > 0
	flash.visible = firing
	light.light_energy = 5.0 if firing else 0.0
	if firing:
		flash.scale = Vector3.ONE * randf_range(0.7, 1.3)
