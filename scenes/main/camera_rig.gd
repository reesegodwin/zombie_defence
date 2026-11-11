# Isometric camera: orthographic, fixed angle, pans over the ground and zooms.
extends Node3D

@export var yaw_degrees := 45.0
@export var pitch_degrees := -35.264
@export var distance := 40.0
## Orthographic view height, in metres. Smaller is closer.
@export var zoom := 15.0
@export var min_zoom := 7.0
@export var max_zoom := 26.0
@export var pan_speed := 14.0
## The rig stays within this ground rectangle (x, z, width, depth).
@export var bounds := Rect2(0, -2, 22, 26)

@onready var cam: Camera3D = $Camera3D

var home_position: Vector3
var home_zoom: float
var shake := 0.0


func _ready() -> void:
	home_position = position
	home_zoom = zoom
	_apply()


func _apply() -> void:
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0)
	cam.position = Vector3(0, 0, distance)
	cam.size = zoom


func reset() -> void:
	position = home_position
	zoom = home_zoom
	_apply()


func _process(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 2.5)
	cam.h_offset = randf_range(-1, 1) * shake * 0.35
	cam.v_offset = randf_range(-1, 1) * shake * 0.35


## Drags the ground under the cursor from one screen point to another.
func drag(from: Vector2, to: Vector2) -> void:
	var a := screen_to_ground(from)
	var b := screen_to_ground(to)
	_move(Vector3(a.x - b.x, 0, a.y - b.y))


## Moves the view with keys: dir.x right, dir.y up the screen.
func pan_keys(dir: Vector2, dt: float) -> void:
	var fwd := Vector3(-global_basis.z.x, 0, -global_basis.z.z).normalized()
	var r := Vector3(global_basis.x.x, 0, global_basis.x.z).normalized()
	_move((r * dir.x + fwd * dir.y) * pan_speed * dt * zoom / home_zoom)


func _move(v: Vector3) -> void:
	position += v
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func zoom_by(factor: float) -> void:
	zoom = clampf(zoom / factor, min_zoom, max_zoom)
	cam.size = zoom


## Where a screen point lands on a horizontal plane at height h (x, z).
func screen_to_ground(p: Vector2, h := 0.0) -> Vector2:
	var o := cam.project_ray_origin(p)
	var n := cam.project_ray_normal(p)
	if absf(n.y) < 1e-4:
		return Vector2(o.x, o.z)
	var t := (h - o.y) / n.y
	var hit := o + n * t
	return Vector2(hit.x, hit.z)


func world_to_screen(v: Vector3) -> Vector2:
	return cam.unproject_position(v)
