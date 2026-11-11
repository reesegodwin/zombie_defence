# The look of one survivor on the walkway: turns to aim, recoils, and flashes
# the muzzle when the simulation says it fired.
extends Node3D

const D = preload("res://scripts/defs.gd")

## Light energy of the muzzle flash.
@export var flash_energy := 6.0

@onready var upper: Node3D = $Upper
@onready var gun: MeshInstance3D = $Upper/Gun
@onready var muzzle: Node3D = $Upper/Muzzle
@onready var flash_mesh: MeshInstance3D = $Upper/Muzzle/Flash
@onready var flash_light: OmniLight3D = $Upper/Muzzle/Light
@onready var label: Label3D = $NameLabel
@onready var ring: MeshInstance3D = $Ring

var _weapon := ""


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
	sync(s, 0.0)


func sync(s: Dictionary, _dt: float) -> void:
	position = Vector3(s["x"], D.DECK_H, s["y"])
	if s["weapon"] != _weapon:
		_set_weapon(s["weapon"])
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
