# A full-screen control under the HUD that receives mouse input meant for the
# battlefield: shooting, panning, zooming, and dropping or dragging traps.
extends Control

var main                     # main.gd, set by the HUD


func _gui_input(event: InputEvent) -> void:
	if main:
		main.field_input(event)


func _get_drag_data(pos: Vector2) -> Variant:
	return main.field_drag(pos) if main else null


func _can_drop_data(pos: Vector2, data: Variant) -> bool:
	return main.field_can_drop(pos, data) if main else false


func _drop_data(pos: Vector2, data: Variant) -> void:
	main.field_drop(pos, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and main:
		main.drag_ended()
