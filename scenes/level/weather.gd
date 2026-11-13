# What falls from the sky in some country (bases.gd PALETTES "weather"):
# snowflakes drifting down on the snowy levels, flakes of ash on the burnt
# ones. A box of particles over the patch of ground the camera is looking at,
# following it about. Off on Very Low graphics; fewer on Low.
extends Node3D

const AMOUNT := {"snow": 1000, "ash": 450}
var _p: CPUParticles3D
var _kind := ""
var _quality := "High"


func _ready() -> void:
	_p = CPUParticles3D.new()
	_p.emitting = false
	_p.lifetime = 7.0
	_p.preprocess = 7.0
	_p.local_coords = false
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = Vector3(26.0, 0.5, 26.0)
	_p.direction = Vector3(0.15, -1.0, 0.1)
	_p.spread = 12.0
	_p.gravity = Vector3(0.25, -0.6, 0.15)
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	q.material = m
	_p.mesh = q
	_p.position = Vector3(0, 11.0, 0)
	add_child(_p)


## "snow", "ash" or "" (nothing falling).
func set_kind(kind: String) -> void:
	_kind = kind
	_apply()


func set_quality(q: String) -> void:
	_quality = q
	_apply()


func _apply() -> void:
	if _p == null:
		return
	var on := _kind in AMOUNT and _quality != "Very Low"
	_p.emitting = on
	visible = on
	if not on:
		return
	_p.amount = int(AMOUNT[_kind] * (0.5 if _quality == "Low" else 1.0))
	if _kind == "snow":
		_p.color = Color(0.95, 0.97, 1.0, 0.9)
		_p.initial_velocity_min = 0.6
		_p.initial_velocity_max = 1.2
		_p.scale_amount_min = 0.8
		_p.scale_amount_max = 1.6
	else:   # ash: dark grey flakes, slower, tumbling
		_p.color = Color(0.22, 0.21, 0.2, 0.85)
		_p.initial_velocity_min = 0.2
		_p.initial_velocity_max = 0.6
		_p.scale_amount_min = 0.6
		_p.scale_amount_max = 1.3
	_p.restart()


## Keeps the snow falling over wherever the camera is looking.
func follow(at: Vector3) -> void:
	global_position = Vector3(at.x, 0.0, at.z)
