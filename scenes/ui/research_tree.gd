# The research tree: one column per branch, one button per project, with lines
# from each project to the ones it opens up. Click an open project to spend its
# scrap and start it. Built in code from D.RESEARCH; the HUD shows it with T.
extends Control

const D = preload("res://scripts/defs.gd")

signal message(text: String)

const COL_W := 196.0
const NODE := Vector2(178, 64)
const ROW_H := 90.0
const TOP := 34.0

var main
var _buttons := {}     # research id -> Button
var _bars := {}        # research id -> ColorRect (progress, while active)
var _pos := {}         # research id -> top-left of its button


func _ready() -> void:
	var rows := {}
	for id in D.RESEARCH:
		var b: int = D.RESEARCH[id]["branch"]
		var r: int = rows.get(b, 0)
		rows[b] = r + 1
		_pos[id] = Vector2(b * COL_W + (COL_W - NODE.x) / 2, TOP + r * ROW_H)
	var most := 0
	for b in rows:
		most = maxi(most, rows[b])
	custom_minimum_size = Vector2(D.RESEARCH_BRANCHES.size() * COL_W, TOP + most * ROW_H)
	for b in D.RESEARCH_BRANCHES.size():
		var h := Label.new()
		h.text = D.RESEARCH_BRANCHES[b].to_upper()
		h.theme_type_variation = &"DimLabel"
		h.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29, 0.9))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.position = Vector2(b * COL_W, 0)
		h.size = Vector2(COL_W, 24)
		add_child(h)
	for id in D.RESEARCH:
		var btn := Button.new()
		btn.position = _pos[id]
		btn.size = NODE
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 15)
		var rid: String = id
		btn.pressed.connect(func(): _start(rid))
		add_child(btn)
		var bar := ColorRect.new()
		bar.color = Color(0.88, 0.7, 0.29, 0.9)
		bar.position = Vector2(6, NODE.y - 7)
		bar.size = Vector2(0, 3)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)
		_buttons[id] = btn
		_bars[id] = bar


func _start(id: String) -> void:
	var r: Dictionary = main.act("start_research", [id])
	if r.has("ok"):
		message.emit("Researching %s. It takes %d seconds once you close this." % [D.RESEARCH[id]["name"], int(D.RESEARCH[id]["time"])])
	else:
		message.emit(r.get("msg", ""))
	refresh()


func _style(c: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func refresh() -> void:
	if main == null:
		return
	var g = main.game
	for id in _buttons:
		var R: Dictionary = D.RESEARCH[id]
		var btn: Button = _buttons[id]
		var st: String = g.research_state(id)
		var tip: String = R["desc"]
		if not R["needs"].is_empty():
			var names: PackedStringArray = []
			for n in R["needs"]:
				names.append(D.RESEARCH[n]["name"])
			tip += "\nNeeds: " + ", ".join(names) + "."
		btn.tooltip_text = tip
		var bar: ColorRect = _bars[id]
		bar.visible = st == "active"
		var sb: StyleBoxFlat
		match st:
			"done":
				btn.text = "%s\nDone" % R["name"]
				sb = _style(Color(0.16, 0.24, 0.14, 0.95), Color(0.45, 0.7, 0.4), 2)
				btn.modulate = Color.WHITE
			"active":
				var left := int(ceil(g.research_left()))
				btn.text = "%s\nResearching · %d:%02d" % [R["name"], left / 60, left % 60]
				sb = _style(Color(0.2, 0.17, 0.08, 0.95), Color(0.88, 0.7, 0.29), 3)
				bar.size.x = (NODE.x - 12) * clampf(g.research_t / R["time"], 0.0, 1.0)
				btn.modulate = Color.WHITE
			"open":
				btn.text = "%s\n%d scrap · %ds" % [R["name"], R["cost"], int(R["time"])]
				var afford: bool = g.scrap >= R["cost"] and g.research_cur == ""
				sb = _style(Color(0.1, 0.1, 0.11, 0.95), Color(0.75, 0.72, 0.65) if afford else Color(0.4, 0.4, 0.4), 2)
				btn.modulate = Color.WHITE if afford else Color(1, 1, 1, 0.75)
			_:
				btn.text = "%s\n%d scrap · %ds" % [R["name"], R["cost"], int(R["time"])]
				sb = _style(Color(0.07, 0.07, 0.08, 0.9), Color(0.25, 0.25, 0.25), 1)
				btn.modulate = Color(1, 1, 1, 0.45)
		for k in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(k, sb)
	queue_redraw()


func _draw() -> void:
	if main == null:
		return
	var g = main.game
	for id in D.RESEARCH:
		for n in D.RESEARCH[id]["needs"]:
			var a: Vector2 = _pos[n] + Vector2(NODE.x / 2, NODE.y)
			var b: Vector2 = _pos[id] + Vector2(NODE.x / 2, 0)
			var done: bool = g.researched.has(n)
			var col := Color(0.45, 0.7, 0.4, 0.8) if done else Color(0.5, 0.5, 0.5, 0.45)
			if absf(a.x - b.x) < 1.0:
				draw_line(a, b, col, 2.0)
			else:
				# Across branches: down, over, then down into the project.
				var pts: PackedVector2Array
				if b.y > a.y:
					var mid := (a.y + b.y) * 0.5
					pts = PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), b])
				else:
					# Back up to an earlier row: along the gap under the
					# prerequisite, up the gutter beside the target column.
					var gx: float = _pos[id].x + NODE.x + 9.0 if a.x > b.x else _pos[id].x - 9.0
					pts = PackedVector2Array([a, Vector2(a.x, a.y + 10), Vector2(gx, a.y + 10), Vector2(gx, b.y - 10), Vector2(b.x, b.y - 10), b])
				draw_polyline(pts, col, 2.0)
