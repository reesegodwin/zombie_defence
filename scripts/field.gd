# A full-screen control under the HUD that receives mouse input meant for the
# battlefield: shooting, panning, zooming, and dropping or dragging traps.
extends Control

var main                     # main.gd


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	main.field_input(event)


func _get_drag_data(pos: Vector2) -> Variant:
	return main.field_drag(pos)


func _can_drop_data(pos: Vector2, data: Variant) -> bool:
	return main.field_can_drop(pos, data)


func _drop_data(pos: Vector2, data: Variant) -> void:
	main.field_drop(pos, data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		main.drag_ended()
