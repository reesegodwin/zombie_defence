# A row of level pips (filled for each level bought, hollow for the rest),
# drawn as circles rather than text, so they show in any font and in a browser.
extends Control

var level := 0:
	set(v):
		level = v
		queue_redraw()
var max_level := 1:
	set(v):
		max_level = v
		queue_redraw()
var color := Color(0.88, 0.7, 0.29)

const R := 5.0
const GAP := 4.0


func _init() -> void:
	custom_minimum_size = Vector2(48, 2.0 * R + 4.0)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var y := size.y / 2.0
	for i in max_level:
		var c := Vector2(R + 1.0 + i * (2.0 * R + GAP), y)
		if i < level:
			draw_circle(c, R, color)
		else:
			draw_arc(c, R - 0.75, 0.0, TAU, 20, color, 1.5, true)
