# All on-screen interface: stats, buttons, toasts, upgrade cards, base storage
# and crew loadouts, pause, title and game-over screens. Built in code.
extends CanvasLayer

const D = preload("res://scripts/defs.gd")
const Slot = preload("res://scripts/slot.gd")
const Field = preload("res://scripts/field.gd")

var main                     # main.gd
var root: Control
var field: Control
var selected = null          # a location Dictionary, or null

var wall_bar: ProgressBar
var wall_label: Label
var xp_bar: ProgressBar
var level_label: Label
var stats_label: Label
var hint_label: Label
var toasts: VBoxContainer
var btn_auto: Button
var btn_inv: Button
var btn_pause: Button
var btn_sound: Button

var inv_panel: PanelContainer
var inv_box: VBoxContainer
var inv_info: Label
var inv_msg: Label
var btn_use: Button
var btn_drop: Button
var slots: Array = []

var cards_overlay: Control
var cards_box: HBoxContainer
var cards_title: Label
var pause_overlay: Control
var over_overlay: Control
var over_label: Label
var title_overlay: Control

const ACCENT := Color("e0b44a")


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	field = Field.new()
	field.main = main
	root.add_child(field)

	_build_stats()
	_build_buttons()
	_build_toasts()
	_build_hint()
	_build_pause()
	_build_inventory()
	_build_cards()
	_build_over()
	_build_title()


# --- Building ---------------------------------------------------------------
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.08, 0.86)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.14, 0.15, 0.16, 0.92), "hover": Color(0.22, 0.23, 0.24, 0.95), "pressed": Color(0.3, 0.26, 0.16, 0.95),
			"focus": Color(0.14, 0.15, 0.16, 0.92), "disabled": Color(0.1, 0.1, 0.1, 0.6)}[state]
		b.set_corner_radius_all(5)
		b.set_content_margin_all(8)
		if state == "focus":
			b.draw_center = false
			b.border_color = Color(ACCENT, 0.6)
			b.set_border_width_all(1)
		t.set_stylebox(state, "Button", b)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.5)
	bar_bg.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	return t


func _label(text := "", size := 15, color := Color(1, 1, 1, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, h := 12.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(220, h)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _overlay(dim := 0.6) -> Control:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, dim)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.visible = false
	root.add_child(c)
	return c


func _center_panel(parent: Control, width := 520.0, click_through := false) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var p := PanelContainer.new()
	if click_through:
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(width, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	if click_through:
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return v


func _build_stats() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 12)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	wall_label = _label("Wall", 14)
	v.add_child(wall_label)
	wall_bar = _bar(Color("c9a24a"), 14)
	v.add_child(wall_bar)
	level_label = _label("Level 1", 14)
	v.add_child(level_label)
	xp_bar = _bar(Color("6fa3c9"), 8)
	v.add_child(xp_bar)
	stats_label = _label("", 13, Color(1, 1, 1, 0.7))
	v.add_child(stats_label)


func _build_buttons() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	h.position = Vector2(-12, 12)
	h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.add_theme_constant_override("separation", 6)
	root.add_child(h)
	btn_auto = Button.new()
	btn_auto.pressed.connect(func(): main.toggle_auto())
	btn_inv = Button.new()
	btn_inv.pressed.connect(func(): toggle_inventory())
	btn_pause = Button.new()
	btn_pause.pressed.connect(func(): main.toggle_pause())
	btn_sound = Button.new()
	btn_sound.pressed.connect(func(): main.toggle_sound())
	for b in [btn_auto, btn_inv, btn_pause, btn_sound]:
		b.focus_mode = Control.FOCUS_NONE
		h.add_child(b)


func _build_toasts() -> void:
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.position = Vector2(-260, 64)
	toasts.custom_minimum_size = Vector2(520, 0)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	root.add_child(toasts)


func _build_hint() -> void:
	hint_label = _label("", 14, Color(1, 1, 1, 0.75))
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.custom_minimum_size = Vector2(900, 0)
	hint_label.position = Vector2(-450, -40)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("shadow_offset_x", 1)
	hint_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(hint_label)


func _build_inventory() -> void:
	inv_panel = PanelContainer.new()
	inv_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inv_panel.offset_left = -400
	inv_panel.offset_top = 64
	inv_panel.offset_bottom = -12
	inv_panel.offset_right = -12
	inv_panel.visible = false
	root.add_child(inv_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_panel.add_child(scroll)
	inv_box = VBoxContainer.new()
	inv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_box.add_theme_constant_override("separation", 8)
	scroll.add_child(inv_box)


func _rebuild_inventory() -> void:
	for c in inv_box.get_children():
		c.queue_free()
	slots.clear()
	var g = main.game
	var head := _label("Base storage  %d / %d" % [g.storage["items"].size(), g.storage["cap"]], 17, ACCENT)
	inv_box.add_child(head)
	var help := _label("Drag items between slots. Drag traps onto the ground in front of the wall, and placed traps back here.", 12, Color(1, 1, 1, 0.55))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(340, 0)
	inv_box.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	inv_box.add_child(grid)
	for i in g.storage["cap"]:
		grid.add_child(_slot({"where": "storage", "i": i}))
	inv_box.add_child(HSeparator.new())
	inv_box.add_child(_label("Crew on the wall", 17, ACCENT))
	for s_i in g.crew.size():
		var s: Dictionary = g.crew[s_i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var k: Dictionary = g.survivor_stats(s)
		var nm := _label("%s\n%s · %d dps" % [s["name"], D.WEAPONS[s["weapon"]]["name"], k["dps"]], 12)
		nm.custom_minimum_size = Vector2(150, 0)
		row.add_child(nm)
		row.add_child(_slot({"where": "weapon", "s": s_i}))
		row.add_child(_slot({"where": "gear", "s": s_i, "g": 0}))
		row.add_child(_slot({"where": "gear", "s": s_i, "g": 1}))
		inv_box.add_child(row)
	inv_box.add_child(HSeparator.new())
	inv_info = _label("", 13, Color(1, 1, 1, 0.85))
	inv_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_info.custom_minimum_size = Vector2(340, 0)
	inv_box.add_child(inv_info)
	var btns := HBoxContainer.new()
	btn_use = Button.new()
	btn_use.text = "Use"
	btn_use.pressed.connect(use_selected)
	btn_drop = Button.new()
	btn_drop.text = "Drop"
	btn_drop.pressed.connect(_drop_selected)
	for b in [btn_use, btn_drop]:
		b.focus_mode = Control.FOCUS_NONE
		btns.add_child(b)
	inv_box.add_child(btns)
	inv_msg = _label("", 13, Color("ff9a7a"))
	inv_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_msg.custom_minimum_size = Vector2(340, 0)
	inv_box.add_child(inv_msg)
	_update_info()


func _slot(loc: Dictionary) -> Control:
	var s := Slot.new()
	s.loc = loc
	s.hud = self
	slots.append(s)
	s.refresh()
	return s


func _build_cards() -> void:
	cards_overlay = _overlay(0.55)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cards_overlay.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	cc.add_child(v)
	var t := _label("Level up: choose one", 26, ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_title = t
	v.add_child(t)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 14)
	v.add_child(cards_box)
	var hint := _label("Click a card, or press 1, 2 or 3.", 13, Color(1, 1, 1, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func show_cards() -> void:
	var g = main.game
	for c in cards_box.get_children():
		c.queue_free()
	for i in g.cards.size():
		var card: Dictionary = g.cards[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 190)
		b.focus_mode = Control.FOCUS_NONE
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14; v.offset_right = -14; v.offset_top = 12; v.offset_bottom = -12
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 6)
		b.add_child(v)
		var tag_col: Color = ACCENT
		if card["id"] == "item":
			tag_col = D.KIND_COLORS[D.item_kind(card["key"])]
		v.add_child(_label("%d · %s" % [i + 1, card["tag"].to_upper()], 12, tag_col))
		var title := _label(card["title"], 20)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(title)
		var desc := _label(card["desc"], 13, Color(1, 1, 1, 0.75))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(desc)
		var idx: int = i
		b.pressed.connect(func(): main.choose_card(idx))
		cards_box.add_child(b)
	cards_title.text = "Level %d: choose one" % g.level if g.pending_levels == 0 else "Level %d: choose one (%d more)" % [g.level, g.pending_levels]
	cards_overlay.visible = true


func hide_cards() -> void:
	cards_overlay.visible = false


func _build_pause() -> void:
	pause_overlay = _overlay(0.35)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := _center_panel(pause_overlay, 360, true)
	var l := _label("Paused", 28, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var l2 := _label("Press P or Space to resume.\nYou can still rearrange storage while paused.", 14, Color(1, 1, 1, 0.75))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l2)


func _build_over() -> void:
	over_overlay = _overlay(0.6)
	var v := _center_panel(over_overlay, 460)
	var l := _label("The wall has fallen", 30, Color("ff7a5a"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	over_label = _label("", 15)
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(over_label)
	var b := Button.new()
	b.text = "Play again  (R)"
	b.pressed.connect(func(): main.restart())
	v.add_child(b)


func show_over() -> void:
	var g = main.game
	var t: int = int(g.time)
	over_label.text = "You held for %d:%02d.\nLevel %d · %d of the dead put down · crew of %d" % [t / 60, t % 60, g.level, g.kills, g.crew.size()]
	if g.picks.size() > 0:
		over_label.text += "\n\nUpgrades: " + ", ".join(PackedStringArray(g.picks.slice(maxi(0, g.picks.size() - 8))))
	over_overlay.visible = true


func _build_title() -> void:
	title_overlay = _overlay(0.55)
	var v := _center_panel(title_overlay, 560)
	var l := _label("NIGHTFALL OUTPOST", 34, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var sub := _label("One wall. One way in. The dead never stop coming.", 15, Color(1, 1, 1, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var how := _label(
		"• Hold the left mouse button to shoot where you point.\n" +
		"• F toggles auto-fire. Your crew always fires on their own.\n" +
		"• Kills give experience. Each level, pick one of three cards:\n   new guns, gear, traps, supplies, survivors, or a stronger wall.\n" +
		"• I opens base storage. Drag guns and gear onto your crew,\n   drag traps onto the ground in front of the wall.\n" +
		"• Right-drag or WASD pans, the mouse wheel zooms, P pauses.\n" +
		"• It only gets harder. A horde arrives every 70 seconds.", 14)
	v.add_child(how)
	var b := Button.new()
	b.text = "Hold the wall  (Enter)"
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(func(): main.start())
	v.add_child(b)
	title_overlay.visible = true


# --- Runtime ----------------------------------------------------------------
func toast(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 0.08, 0.06, 0.88) if kind == "danger" else Color(0.08, 0.09, 0.1, 0.88)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(text, 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	toasts.add_child(p)
	var tw := create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func toggle_inventory() -> void:
	if main.game.over:
		return
	inv_panel.visible = not inv_panel.visible
	main.world.show_trap_zone = inv_panel.visible
	if inv_panel.visible:
		main.game.set_meta("hinted_inv", true)
		_rebuild_inventory()
	else:
		selected = null


func on_inv_changed() -> void:
	if inv_panel.visible:
		_rebuild_inventory()


func select(loc: Dictionary) -> void:
	selected = loc.duplicate()
	if inv_msg:
		inv_msg.text = ""
	for s in slots:
		s.queue_redraw()
	_update_info()


func set_inv_message(msg: String) -> void:
	if inv_msg and is_instance_valid(inv_msg):
		inv_msg.text = msg


func _update_info() -> void:
	if inv_info == null or not is_instance_valid(inv_info):
		return
	var it = main.game.item_at(selected) if selected != null else null
	if it == null:
		inv_info.text = "Select an item to see what it does. Double-click a supply to use it."
		btn_use.visible = false
		btn_drop.visible = false
		return
	var key: String = it["key"]
	var kind := D.item_kind(key)
	inv_info.text = D.item_name(key) + "  (" + D.KIND_TAG[kind] + ")\n" + D.item_desc(key)
	btn_use.visible = kind == "supply" and selected["where"] == "storage"
	btn_drop.visible = selected["where"] != "weapon"


func use_selected() -> void:
	if selected == null or selected["where"] != "storage":
		return
	var r: Dictionary = main.game.use_supply(selected["i"])
	if r.has("msg") and r["msg"] != "":
		if r.has("ok"):
			toast(r["msg"])
		else:
			set_inv_message(r["msg"])
	if r.has("ok"):
		selected = null
		_update_info()


func _drop_selected() -> void:
	if selected == null:
		return
	var r: Dictionary = main.game.drop_item(selected)
	if r.has("ok"):
		selected = null
		_update_info()
	elif r.get("msg", "") != "":
		set_inv_message(r["msg"])


func update_hud() -> void:
	var g = main.game
	var w: Dictionary = g.wall
	wall_bar.max_value = w["max_hp"]
	wall_bar.value = w["hp"]
	wall_label.text = "Wall  %d / %d  ·  %s" % [ceili(w["hp"]), int(w["max_hp"]), g.wall_mat()["name"]]
	level_label.text = "Level %d" % g.level
	xp_bar.max_value = g.xp_next
	xp_bar.value = g.xp
	var t := int(g.time)
	stats_label.text = "Time %d:%02d   Kills %d   Threat %d   Crew %d/%d" % [t / 60, t % 60, g.kills, g.threat, g.crew.size(), D.MAX_CREW]
	btn_auto.text = "Auto-fire: %s (F)" % ("on" if g.input_auto else "off")
	btn_inv.text = "Storage %d/%d (I)" % [g.storage["items"].size(), g.storage["cap"]]
	btn_pause.text = "Resume (P)" if main.paused else "Pause (P)"
	btn_sound.text = "Sound: %s (M)" % ("off" if main.sfx.muted else "on")
	pause_overlay.visible = main.paused and not g.over and g.cards.is_empty() and main.started

	var hint := ""
	if not main.started:
		hint = ""
	elif g.time < 10:
		hint = "Auto-fire is on: you shoot whatever is closest to the wall." if g.input_auto else "Hold the left mouse button to shoot. Your aim snaps to the zombie under the cursor."
	elif not g.has_meta("hinted_inv") and g.storage["items"].size() > 0:
		hint = "You have something in storage. Press I to open it and hand it out."
	elif inv_panel.visible:
		hint = "Storage is open. Clicking the field still shoots, unless you grab a placed trap."
	hint_label.text = hint
