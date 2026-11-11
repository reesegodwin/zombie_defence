# Shows how far your gun reaches: a dashed arc on the ground at your weapon's
# range and, when you're aiming by hand, a marker at the cursor that turns red
# when it's out of range.
extends MeshInstance3D

const D = preload("res://scripts/defs.gd")

@export var range_color := Color(1.0, 0.8, 0.4, 0.8)
@export var marker_color := Color(1.0, 0.9, 0.6, 0.8)
@export var out_of_range_color := Color(1.0, 0.3, 0.22, 0.95)
@export var line_width := 0.09
@export var height := 0.04

var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _quad(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := (b - a)
	if d.length() < 0.001:
		return
	var n := Vector2(-d.y, d.x).normalized() * w * 0.5
	var p := [a + n, a - n, b - n, b + n]
	for i in [0, 1, 2, 0, 2, 3]:
		_im.surface_set_color(col)
		_im.surface_add_vertex(Vector3(p[i].x, height, p[i].y))


func _in_lane(p: Vector2) -> bool:
	return p.x >= D.X0 + 0.05 and p.x <= D.X1 - 0.05 and p.y >= 0.05 and p.y <= D.WALL_Y


## cursor: ground point under the mouse (or null); manual: aiming by hand.
func sync(g, cursor, manual: bool, show: bool) -> void:
	_im.clear_surfaces()
	var you: Dictionary = g.crew[0]
	visible = show and you["state"] == "wall"
	if not visible:
		return
	var w: Dictionary = D.WEAPONS[you["weapon"]]
	var reach: float = w["range"]
	var c := Vector2(you["x"], you["y"])
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	# Range arc across the lane in front of the wall, dashed.
	var segs := 96
	for i in segs:
		if i % 2 == 1:
			continue
		var a0 := PI + PI * i / segs
		var a1 := PI + PI * (i + 1) / segs
		var p0 := c + Vector2(cos(a0), sin(a0)) * reach
		var p1 := c + Vector2(cos(a1), sin(a1)) * reach
		if _in_lane(p0) and _in_lane(p1):
			_quad(p0, p1, line_width * 1.3, range_color)

	var marker_col := marker_color
	if cursor != null and c.distance_to(cursor) > reach:
		marker_col = out_of_range_color

	# Marker at the cursor while aiming by hand.
	if manual and cursor != null and _in_lane(cursor):
		var r := 0.32
		for i in 16:
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 0.6) / 16.0
			_quad(cursor + Vector2(cos(a0), sin(a0)) * r, cursor + Vector2(cos(a1), sin(a1)) * r, line_width * 1.2, marker_col)
		_quad(cursor + Vector2(-0.12, 0), cursor + Vector2(0.12, 0), line_width, marker_col)
		_quad(cursor + Vector2(0, -0.12), cursor + Vector2(0, 0.12), line_width, marker_col)
	_im.surface_end()
