# The look of one survivor: on the walkway they turn to aim, recoil and flash
# the muzzle; when sent scavenging they walk down off the walkway, out through
# the pass, and vanish until they come back.
extends Node3D

const D = preload("res://scripts/defs.gd")

## Light energy of the muzzle flash.
@export var flash_energy := 6.0
## Leg swing while walking, in radians.
@export var stride := 0.6

@onready var upper: Node3D = $Upper
@onready var legs: Node3D = $Legs
@onready var leg_l: Node3D = $Legs/LegL
@onready var leg_r: Node3D = $Legs/LegR
@onready var gun: MeshInstance3D = $Upper/Gun
@onready var muzzle: Node3D = $Upper/Muzzle
@onready var flash_mesh: MeshInstance3D = $Upper/Muzzle/Flash
@onready var flash_light: OmniLight3D = $Upper/Muzzle/Light
@onready var label: Label3D = $NameLabel
@onready var ring: MeshInstance3D = $Ring
@onready var arm_r: MeshInstance3D = $Upper/ArmR

var hovered := false

var _weapon := ""
var _height := D.DECK_H
var _heading := 0.0
var _last := Vector2.ZERO
var _phase := 0.0


func setup(s: Dictionary) -> void:
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = s["jacket"]
	jacket.roughness = 0.9
	$Upper/Torso.material_override = jacket
	var skin := StandardMaterial3D.new()
	skin.albedo_color = s["skin"]
	for n in [$Upper/Head, $Upper/ArmL, $Upper/ArmR]:
		n.material_override = skin
	label.text = s["name"]
	ring.visible = s["is_player"]
	_last = Vector2(s["x"], s["y"])
	_height = _ground_height(s)
	sync(s, 0.0)


func _ground_height(s: Dictionary) -> float:
	var on_walkway: bool = s["y"] >= D.WALL_Y + D.WALL_T and s["y"] <= D.WALK_Y + 0.7
	return D.DECK_H if on_walkway else 0.0


func sync(s: Dictionary, dt: float) -> void:
	var state: String = s["state"]
	visible = state != "away"
	if not visible:
		_last = Vector2(s["x"], s["y"])
		return
	var pos := Vector2(s["x"], s["y"])
	_height = move_toward(_height, _ground_height(s), dt * 2.5)
	position = Vector3(pos.x, _height, pos.y)
	if s["weapon"] != _weapon:
		_set_weapon(s["weapon"])

	var walking := state != "wall"
	if walking:
		var step := pos - _last
		if step.length() > 0.0005:
			_heading = atan2(step.x, step.y)
		_phase += dt * 9.0
		leg_l.rotation.x = sin(_phase) * stride
		leg_r.rotation.x = -sin(_phase) * stride
		upper.rotation.y = lerp_angle(upper.rotation.y, _heading, 0.3)
		upper.position = Vector3(0, 0.78 + absf(cos(_phase)) * 0.03, 0)
		legs.rotation.y = upper.rotation.y
		flash_mesh.visible = false
		flash_light.light_energy = 0.0
		# Fade out as they disappear up the pass, and in as they come back.
		label.modulate.a = 0.8 * clampf((1.0 - s["path_t"]) * 8.0, 0.0, 1.0)
	elif s.get("repairing", false):
		# Turn to the wall, crouch, put the gun away and hammer.
		_phase += dt * 11.0
		leg_l.rotation.x = 0.5
		leg_r.rotation.x = -0.2
		legs.rotation.y = PI
		upper.rotation.y = PI
		upper.position = Vector3(0, 0.62, 0.05)
		gun.visible = false
		arm_r.rotation.x = -0.9 + absf(sin(_phase)) * 1.3
		flash_mesh.visible = false
		flash_light.light_energy = 0.0
		label.text = s["name"] + " · repairing"
		label.modulate = Color(1.0, 0.85, 0.45, 1.0)
	else:
		leg_l.rotation.x = 0.0
		leg_r.rotation.x = 0.0
		legs.rotation.y = 0.0
		gun.visible = true
		arm_r.rotation.x = 0.0
		label.text = s["name"] + ("  ·  click to repair" if hovered else "")
		label.modulate = Color(1.0, 0.9, 0.6, 1.0) if hovered else Color(1, 1, 1, 0.8)
		# Sim angle is in the ground plane (x, y) -> world (x, z).
		var ang: float = s["aim"]
		upper.rotation.y = atan2(cos(ang), sin(ang))
		var recoil: float = s["recoil"] * 0.9
		upper.position = Vector3(0, 0.78, 0) - Vector3(cos(ang), 0, sin(ang)) * recoil
		var firing: bool = s["flash"] > 0
		flash_mesh.visible = firing
		flash_light.light_energy = flash_energy if firing else 0.0
		if firing:
			flash_mesh.rotation.z = randf() * TAU
			flash_mesh.scale = Vector3.ONE * randf_range(0.8, 1.3)
	_last = pos


func _set_weapon(key: String) -> void:
	_weapon = key
	var w: Dictionary = D.WEAPONS[key]
	var length: float = w["len"]
	var thick := 0.11 if key in ["shotgun", "launcher"] else 0.08
	var box := BoxMesh.new()
	box.size = Vector3(thick, thick + 0.02, length)
	gun.mesh = box
	gun.position = Vector3(0.1, 0.45, 0.32 + length * 0.5)
	muzzle.position = Vector3(0.1, 0.47, 0.34 + length)
