# The look of one zombie. The simulation (scripts/game.gd) owns where it is and
# how hurt it is; this script poses the model to match every frame.
extends Node3D

const D = preload("res://scripts/defs.gd")

## Leg and arm swing while walking, in radians.
@export var stride := 0.55
## How far the body leans toward the wall.
@export var lean := 0.22

@onready var body: Node3D = $Body
@onready var leg_l: Node3D = $LegL
@onready var leg_r: Node3D = $LegR
@onready var arm_l: Node3D = $Body/ArmL
@onready var arm_r: Node3D = $Body/ArmR
@onready var head: Node3D = $Body/Head
@onready var bar: Node3D = $HealthBar
@onready var bar_fill: Node3D = $HealthBar/Fill

static var _mats := {}
static var _flash_mat: StandardMaterial3D
static var _burn_mat: StandardMaterial3D

var meshes: Array[MeshInstance3D] = []
var zid := -1
var dying := false
var _overlay = null


func setup(z: Dictionary) -> void:
	zid = z["id"]
	var T: Dictionary = D.ZTYPES[z["type"]]
	scale = Vector3.ONE * T["scale"]
	var shirt: Color = T["shirts"][z["shirt"]]
	_set_mat($Body/Torso, _mat("shirt", shirt))
	var skin := _mat("skin", T["skin"])
	for n in [$Body/Head, $Body/ArmL/Mesh, $Body/ArmR/Mesh]:
		_set_mat(n, skin)
	var eyes := _mat("eyes", T["eyes"], true)
	_set_mat($Body/Head/EyeL, eyes)
	_set_mat($Body/Head/EyeR, eyes)
	for n in find_children("*", "MeshInstance3D", true, false):
		if n.get_parent() != bar:
			meshes.append(n)
	sync(z, 0.0)


static func _mat(kind: String, c: Color, glow := false) -> StandardMaterial3D:
	var key := kind + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		if glow:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 3.0
		_mats[key] = m
	return _mats[key]


func _set_mat(n: MeshInstance3D, m: Material) -> void:
	n.material_override = m


func sync(z: Dictionary, dt: float) -> void:
	position = Vector3(z["x"], 0.0, z["y"])
	var t: float = z["t"]
	var held: bool = z["held"] > 0
	var attacking: bool = z["atk"] > 0
	var moving: bool = not held and not attacking and z["y"] < D.WALL_Y - 0.4
	var spd: float = D.ZTYPES[z["type"]]["speed"] * z["spd"] * z["slow"]
	var phase := t * (3.0 + spd * 5.0)
	if moving:
		leg_l.rotation.x = sin(phase) * stride
		leg_r.rotation.x = -sin(phase) * stride
		body.position.y = 0.78 + absf(cos(phase)) * 0.04
		body.rotation.z = sin(phase) * 0.06
	else:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, 0.2)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, 0.2)
	body.rotation.x = lean + (0.25 if attacking else 0.0)
	# Arms reach toward the wall, and claw at it when attacking.
	var claw := sin(t * 18.0) * 0.6 if attacking else 0.0
	arm_l.rotation.x = 0.1 + sin(phase + 0.5) * 0.12 - claw
	arm_r.rotation.x = 0.1 - sin(phase + 0.5) * 0.12 + claw
	head.rotation.z = sin(t * 1.3 + z["sway"]) * 0.25
	if held:
		rotation.y = sin(t * 30.0) * 0.12
	else:
		rotation.y = sin(t * 0.8 + z["sway"]) * 0.15

	# Flash white when hit, orange while burning.
	var want = null
	if z["hit"] > 0:
		want = _flash()
	elif z["burn"] > 0:
		want = _burn()
	if want != _overlay:
		_overlay = want
		for m in meshes:
			m.material_overlay = want

	# Health bar, only once hurt, always facing the camera.
	var frac: float = clampf(z["hp"] / z["max_hp"], 0.0, 1.0)
	bar.visible = frac < 0.999
	if bar.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			bar.global_basis = cam.global_basis
		bar_fill.scale.x = maxf(0.001, frac)
		bar_fill.position.x = -0.25 * (1.0 - frac)


static func _flash() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1, 1, 1, 0.7)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _flash_mat


static func _burn() -> StandardMaterial3D:
	if _burn_mat == null:
		_burn_mat = StandardMaterial3D.new()
		_burn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_burn_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.45)
		_burn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _burn_mat


## Topples forward, sinks into the ground and frees itself.
func die() -> void:
	dying = true
	bar.visible = false
	for m in meshes:
		m.material_overlay = null
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "rotation:x", 1.45, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:y", -0.6, 1.2).set_delay(0.6)
	tw.chain().tween_callback(queue_free)
