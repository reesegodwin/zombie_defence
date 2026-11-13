# One inventory slot: base storage, a survivor's weapon slot, or a gear slot.
# Items move with Godot's built-in drag and drop.
extends Control

const D = preload("res://scripts/defs.gd")

var loc: Dictionary
var hud                      # hud.gd
var _drag_ok := false
var _dragging := false


func game():
	return hud.main.game


func _process(_dt: float) -> void:
	var dragging := get_viewport().gui_is_dragging()
	var ok := dragging and _accepts(get_viewport().gui_get_drag_data())
	if dragging != _dragging or ok != _drag_ok:
		_dragging = dragging
		_drag_ok = ok
		queue_redraw()


func refresh() -> void:
	var it = game().item_at(loc)
	if it == null:
		tooltip_text = {"weapon": "Weapon slot", "gear": "Gear slot", "storage": "Empty"}[loc["where"]]
	else:
		tooltip_text = D.item_name(it["key"]) + "\n" + D.item_desc(it["key"])
	queue_redraw()


func _short(key: String) -> String:
	if D.WEAPONS.has(key):
		return D.WEAPONS[key]["short"]
	return D.ITEMS[key]["short"]


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var it = game().item_at(loc)
	var bg := Color(0.09, 0.1, 0.11, 0.92)
	if loc["where"] == "weapon":
		bg = Color(0.15, 0.12, 0.07, 0.92)
	elif loc["where"] == "gear":
		bg = Color(0.07, 0.11, 0.15, 0.92)
	draw_style_box(_box(bg), r)
	var border := Color(1, 1, 1, 0.1)
	if it != null:
		border = D.KIND_COLORS[D.item_kind(it["key"])]
	if hud.selected != null and game().same_loc(hud.selected, loc):
		border = Color(1, 0.95, 0.6)
	if _dragging and _drag_ok:
		draw_style_box(_box(Color(0.3, 0.9, 0.4, 0.22)), r)
		border = Color(0.45, 1.0, 0.55)
	var outline := _box(Color(0, 0, 0, 0))
	outline.border_color = border
	outline.set_border_width_all(2)
	draw_style_box(outline, r)
	var font := get_theme_default_font()
	if it == null:
		var hint: String = {"weapon": "GUN", "gear": "GEAR", "storage": ""}[loc["where"]]
		draw_string(font, Vector2(0, size.y / 2 + 4), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 1, 1, 0.22))
		return
	var key: String = it["key"]
	var col: Color = D.KIND_COLORS[D.item_kind(key)]
	draw_rect(Rect2(Vector2(8, 7), Vector2(size.x - 16, 3)), Color(col, 0.8))
	draw_string(font, Vector2(0, size.y / 2 + 7), _short(key), HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.95))
	if it.has("uses") and D.ITEMS[key].has("uses"):
		var frac: float = clampf(it["uses"] / float(D.ITEMS[key]["uses"]), 0.0, 1.0)
		draw_rect(Rect2(Vector2(8, size.y - 10), Vector2(size.x - 16, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(8, size.y - 10), Vector2((size.x - 16) * frac, 3)), Color("e0b44a"))


func _box(c: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(6)
	return b


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hud.select(loc)
		if event.double_click:
			hud.use_selected()
		accept_event()


func _get_drag_data(_pos: Vector2) -> Variant:
	var it = game().item_at(loc)
	if it == null:
		return null
	hud.set_drag_label(D.item_name(it["key"]), it["key"], self)
	hud.select(loc)
	return {"loc": loc.duplicate(), "key": it["key"]}


func _accepts(data) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.has("loc"):
		return game().can_move(data["loc"], loc).has("ok")
	if data.has("trap_uid"):
		return loc["where"] == "storage" and game().storage_free() > 0
	return false


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var ok := _accepts(data)
	if not ok and typeof(data) == TYPE_DICTIONARY and data.has("loc"):
		var msg: String = game().can_move(data["loc"], loc).get("msg", "")
		if msg != "":
			hud.set_inv_message(msg)
	return ok


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var r: Dictionary
	if data.has("loc"):
		r = hud.main.act("move_item", [data["loc"], loc])
		if r.has("ok"):
			hud.main.sfx.play("build")
			hud.select(loc)
	else:
		r = hud.main.act("pick_up_trap", [data["trap_uid"]])
	if r.has("msg") and r["msg"] != "":
		hud.set_inv_message(r["msg"])
