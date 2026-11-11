# Shared look for placed traps: a wear bar, a highlight ring when you hover it
# with storage open, and a little animation per kind.
extends Node3D

@export_enum("spikes", "beartrap", "mine", "slick") var kind := "spikes"

@onready var bar_fill: Node3D = $WearBar/Fill
@onready var bar: Node3D = $WearBar
@onready var highlight: MeshInstance3D = $Highlight

var uid := -1
var _slick_mat: StandardMaterial3D


func setup(t: Dictionary) -> void:
	uid = t["uid"]
	rotation.y = randf() * TAU
	if kind == "slick":
		_slick_mat = $Pool.get_surface_override_material(0).duplicate()
		$Pool.set_surface_override_material(0, _slick_mat)
	sync(t, false)


func sync(t: Dictionary, hovered: bool) -> void:
	position = Vector3(t["x"], 0.0, t["y"])
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
