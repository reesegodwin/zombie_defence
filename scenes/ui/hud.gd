# The on-screen interface. The layout lives in hud.tscn (open it to rearrange
# or restyle); this script fills it in from the game each frame.
extends CanvasLayer

const D = preload("res://scripts/defs.gd")
const Pips = preload("res://scenes/ui/pips.gd")
const ResearchTree = preload("res://scenes/ui/research_tree.gd")
const Settings = preload("res://scripts/settings.gd")

@export var slot_scene: PackedScene

var main                     # main.gd, set by Main
var selected = null          # an inventory location Dictionary, or null
var slots: Array = []

@onready var field: Control = %Field
@onready var wall_label: Label = %WallLabel
@onready var wall_bar: ProgressBar = %WallBar
@onready var resources_label: Label = %ResourcesLabel
@onready var trip_label: Label = %TripLabel
@onready var food_label: Label = %FoodLabel
@onready var food_bar: ProgressBar = %FoodBar
@onready var stats_label: Label = %StatsLabel
@onready var hint: Label = %Hint
@onready var toasts: VBoxContainer = %Toasts
@onready var btn_storage: Button = %StorageButton
@onready var btn_pause: Button = %PauseButton
@onready var btn_sound: Button = %SoundButton
@onready var pause_overlay: Control = %PauseOverlay
@onready var inv_panel: Control = %InventoryPanel
@onready var storage_title: Label = %StorageTitle
@onready var storage_grid: GridContainer = %StorageGrid
@onready var crew_list: VBoxContainer = %CrewList
@onready var info_label: Label = %InfoLabel
@onready var btn_use: Button = %UseButton
@onready var btn_drop: Button = %DropButton
@onready var inv_msg: Label = %InvMessage
@onready var btn_workshop: Button = %WorkshopButton
@onready var btn_map: Button = %MapButton
@onready var workshop: Control = %WorkshopPanel
@onready var shop_list: VBoxContainer = %ShopList
@onready var scav_map: Control = %ScavengeMap
@onready var over_overlay: Control = %GameOverOverlay
@onready var over_stats: Label = %GameOverStats
@onready var title_overlay: Control = %TitleOverlay

var _hinted_storage := false
var _hinted_map := false
var _shop_rows := {}       # shop id -> button
var _shop_labels := {}     # shop id -> name label
var _shop_t := 0.0
var _hinted_research := false
var research_overlay: Control
var research_tree: Control
var research_info: Label
var research_msg: Label
var research_label: Label  # in the stats panel: what's being researched
var ammo_label: Label      # in the stats panel: your gun and rounds left
var btn_research: Button
var options_overlay: Control
var camp_overlay: Control
var _camp_grit: Label
var _camp_records: Label
var _camp_heat: OptionButton
var _camp_level: OptionButton
var _title_level: OptionButton
var _title_level_desc: Label
var _camp_rows := {}       # upgrade id -> {"pips": Label, "button": Button}
var _camp_msg: Label
var _reset_armed := false
var _btn_camp_over: Button
var _camp_result: Label    # how the last run went, when the camp opens after a loss
var _camp_back: Button
var _camp_go: Button        # START A RUN, hidden in the middle of one
var _camp_reset: Button
var _opt_mode: OptionButton
var _opt_size: OptionButton
var _opt_scale: OptionButton
var _sizes: Array = []
var _btn_board: Button     # "Everyone in the truck", while it waits in the yard


func _ready() -> void:
	field.main = main
	btn_storage.pressed.connect(toggle_inventory)
	btn_pause.pressed.connect(func(): main.toggle_pause())
	btn_sound.pressed.connect(func(): main.toggle_sound())
	btn_use.pressed.connect(use_selected)
	btn_drop.pressed.connect(_drop_selected)
	%PlayAgainButton.pressed.connect(func(): main.restart())
	%StartButton.pressed.connect(func(): main.start())
	_build_saves()
	btn_workshop.pressed.connect(toggle_workshop)
	btn_map.pressed.connect(toggle_map)
	scav_map.closed.connect(func(): btn_map.release_focus())
	title_overlay.visible = true
	_build_shop()
	_build_research()
	_build_options()
	_build_camp()


func _process(dt: float) -> void:
	if field.main == null and main != null:
		field.main = main
		scav_map.main = main
	_shop_t -= dt
	if workshop.visible and _shop_t <= 0.0:
		_shop_t = 0.2
		_refresh_shop()


# --- Screens ----------------------------------------------------------------
func hide_title() -> void:
	title_overlay.visible = false


func show_title() -> void:
	title_overlay.visible = true
	_refresh_title()


# --- Saved runs: Continue and Load on the title, Save/Load/Quit when paused ---
const Saves = preload("res://scripts/saves.gd")
var saves_overlay: Control
var _saves_title: Label
var _saves_rows := {}     # slot -> {"text": Label, "button": Button}
var _saves_mode := "load"
var _btn_continue: Button
var _btn_load_title: Button


func saves_open() -> bool:
	return saves_overlay != null and saves_overlay.visible


func close_saves() -> void:
	if saves_overlay != null:
		saves_overlay.visible = false


## Opens the slot list, to save into ("save") or load from ("load").
func open_saves(mode: String) -> void:
	_saves_mode = mode
	_saves_title.text = "SAVE THE RUN" if mode == "save" else "LOAD A RUN"
	for slot in Saves.SLOTS:
		var r: Dictionary = _saves_rows[slot]
		var info := Saves.info(slot)
		r["text"].text = Saves.describe(info)
		var b: Button = r["button"]
		if mode == "save":
			b.text = "Save here"
			b.disabled = slot == "auto"   # that one saves itself
			b.tooltip_text = "Saves itself every dawn, and when you quit to the title." if slot == "auto" else ""
		else:
			b.text = "Load"
			b.disabled = info.is_empty()
			b.tooltip_text = ""
	saves_overlay.visible = true


func _on_slot(slot: String) -> void:
	if _saves_mode == "save":
		if main.save_run(slot):
			toast("Saved to %s." % Saves.NAMES[slot], "good")
			main.sfx.play("build")
		open_saves("save")
	else:
		main.load_run(slot)


## A drop-down of the levels; picking one saves it as the next run's.
func _level_picker() -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	_fill_levels(ob)
	ob.item_selected.connect(func(i):
		main.progress.map_level = i + 1
		main.progress.save()
		_refresh_title()
		if camp_open():
			_refresh_camp())
	return ob


## Only the levels you've reached (the truck took you there) are listed.
func _fill_levels(ob: OptionButton) -> void:
	var n: int = D.LEVELS.size() if main == null or main.progress == null else clampi(main.progress.reached, 1, D.LEVELS.size())
	if ob.item_count == n:
		return
	ob.clear()
	for i in n:
		var L: Dictionary = D.LEVELS[i]
		ob.add_item("Level %d: %s  (%s)" % [i + 1, L["name"], L["short"]])
		ob.set_item_tooltip(i, L["desc"])


## Everything back to a first play: Grit, upgrades, Heat, levels, records,
## saved runs, and the tutorial.
func reset_game() -> void:
	main.progress.reset()
	for slot in Saves.SLOTS:
		Saves.erase(slot)
	main.settings.tutorial = true
	main.settings.tutorial_done = []
	main.settings.save()
	_refresh_title()
	if _btn_continue != null:
		_btn_continue.visible = Saves.latest() != ""


func _refresh_title() -> void:
	if _title_level != null and main != null:
		_fill_levels(_title_level)
		var lv: int = clampi(main.progress.map_level, 1, _title_level.item_count)
		_title_level.select(lv - 1)
		var L: Dictionary = D.LEVELS[lv - 1]
		var w: int = main.progress.level_wins.get(lv, 0)
		_title_level_desc.text = L["desc"] + ("  Won %d time%s." % [w, "" if w == 1 else "s"] if w > 0 else "") + (("  Pays %d%% more Grit." % int(round((L["grit"] - 1.0) * 100))) if L["grit"] > 1.0 else "")
	var latest := Saves.latest()
	_btn_continue.visible = latest != ""
	_btn_load_title.visible = latest != ""
	if latest != "":
		var i := Saves.info(latest)
		_btn_continue.text = "CONTINUE  (day %d, %s)" % [i.get("day", 1), Saves.NAMES[latest].to_lower()]
		_btn_continue.set_meta("slot", latest)


func _build_saves() -> void:
	# On the title: Continue (the latest save) and Load.
	var tv: Control = %StartButton.get_parent()
	_btn_continue = Button.new()
	_btn_continue.custom_minimum_size = Vector2(320, 48)
	_btn_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_continue.focus_mode = Control.FOCUS_NONE
	_btn_continue.add_theme_font_size_override("font_size", 20)
	_btn_continue.pressed.connect(func(): main.load_run(_btn_continue.get_meta("slot", "auto")))
	tv.add_child(_btn_continue)
	tv.move_child(_btn_continue, %StartButton.get_index())
	_btn_load_title = Button.new()
	_btn_load_title.text = "Load a saved run"
	_btn_load_title.custom_minimum_size = Vector2(320, 40)
	_btn_load_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_load_title.focus_mode = Control.FOCUS_NONE
	_btn_load_title.pressed.connect(func(): open_saves("load"))
	tv.add_child(_btn_load_title)
	tv.move_child(_btn_load_title, %StartButton.get_index() + 1)
	# Start over from scratch: click twice.
	var wipe := Button.new()
	wipe.text = "Reset game"
	wipe.custom_minimum_size = Vector2(320, 36)
	wipe.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wipe.focus_mode = Control.FOCUS_NONE
	wipe.modulate = Color(1, 1, 1, 0.7)
	wipe.pressed.connect(func():
		if wipe.has_meta("armed"):
			reset_game()
			wipe.remove_meta("armed")
			wipe.text = "Game reset"
		else:
			wipe.set_meta("armed", true)
			wipe.text = "Click again: wipe ALL progress and saves")
	wipe.mouse_exited.connect(func():
		if wipe.has_meta("armed"):
			wipe.remove_meta("armed")
			wipe.text = "Reset game")
	tv.add_child(wipe)
	tv.move_child(wipe, _btn_load_title.get_index() + 1)
	# The level to play.
	var lrow := HBoxContainer.new()
	lrow.alignment = BoxContainer.ALIGNMENT_CENTER
	lrow.add_theme_constant_override("separation", 10)
	tv.add_child(lrow)
	tv.move_child(lrow, %StartButton.get_index())
	var lt := Label.new()
	lt.text = "Level"
	lt.add_theme_font_size_override("font_size", 20)
	lrow.add_child(lt)
	_title_level = _level_picker()
	_title_level.custom_minimum_size = Vector2(300, 0)
	lrow.add_child(_title_level)
	_title_level_desc = Label.new()
	_title_level_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_level_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	tv.add_child(_title_level_desc)
	tv.move_child(_title_level_desc, %StartButton.get_index())
	_refresh_title()
	# In the pause box: Save, Load, Quit to title.
	var pv: Control = pause_overlay.get_node("Center/Panel/VBox")
	pause_overlay.get_node("Center/Panel").mouse_filter = Control.MOUSE_FILTER_PASS
	pv.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	pv.add_child(row)
	for spec in [["Save game", func(): open_saves("save")], ["Load game", func(): open_saves("load")], ["Quit to title", _on_quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		row.add_child(b)
	var hint := Label.new()
	hint.text = "F5 quick save  ·  F9 quick load  ·  autosaves every dawn"
	hint.theme_type_variation = &"DimLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(hint)
	# The slot list.
	var root: Control = over_overlay.get_parent()
	saves_overlay = ColorRect.new()
	saves_overlay.color = Color(0.02, 0.02, 0.03, 0.85)
	saves_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	saves_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	saves_overlay.visible = false
	root.add_child(saves_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	saves_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_saves_title = Label.new()
	_saves_title.theme_type_variation = &"HeaderLabel"
	box.add_child(_saves_title)
	for slot in Saves.SLOTS:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		box.add_child(r)
		var nm := Label.new()
		nm.text = Saves.NAMES[slot]
		nm.custom_minimum_size = Vector2(110, 0)
		nm.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29))
		r.add_child(nm)
		var text := Label.new()
		text.custom_minimum_size = Vector2(430, 0)
		text.theme_type_variation = &"DimLabel"
		r.add_child(text)
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 0)
		b.focus_mode = Control.FOCUS_NONE
		var sl: String = slot
		b.pressed.connect(func(): _on_slot(sl))
		r.add_child(b)
		_saves_rows[slot] = {"text": text, "button": b}
	var back := Button.new()
	back.text = "Back  (Esc)"
	back.focus_mode = Control.FOCUS_NONE
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(close_saves)
	box.add_child(back)


func _on_quit() -> void:
	main.quit_to_title()
	toast("Your run is kept in the autosave: Continue picks it up.", "info")


func show_game_over(result: Dictionary) -> void:
	var g = main.game
	var t: int = int(g.time)
	var nights: int = result["nights"]
	var title: Label = over_overlay.get_node("Center/Panel/VBox/Title")
	if result["won"]:
		title.text = "YOU HELD OUT"
		title.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5))
	else:
		title.text = "THE WALL HAS FALLEN"
		title.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
	var text := ""
	if result["won"]:
		text = "You held the Last Stand: %d nights in all, until they finally got in.\n" % nights
	else:
		text = "The outpost fell on %s, level %d. You saw %d %s through.\n" % [D.LEVELS[g.level - 1]["name"], g.level, nights, "night" if nights == 1 else "nights"]
	text += "%d of the dead put down" % g.kills
	var p: Dictionary = result["parts"]
	text += "\n\nGrit earned: %d" % result["total"]
	var bits: PackedStringArray = []
	for k in ["base", "nights", "kills", "research", "survivors", "win"]:
		if p[k] > 0:
			bits.append("%s %d" % [k, p[k]])
	if bits.size() > 0:
		text += "   (" + ", ".join(bits) + (", Heat x%.2f" % (1.0 + D.HEAT_GRIT * result["heat"]) if result["heat"] > 0 else "") + ")"
	text += "\nGrit to spend at the camp: %d" % main.progress.grit
	if result.get("unlocked", false):
		text += "\nHeat %d unlocked: pick it at the camp for a harder run and more Grit." % main.progress.max_heat
	if not result["won"]:
		# Lost: straight to the camp, with the run's tally at the top.
		_camp_result.text = text
		_camp_result.visible = true
		over_overlay.visible = false
		if not camp_open():
			toggle_camp()
		return
	over_stats.text = text
	%PlayAgainButton.visible = false   # the next run starts from the camp
	over_overlay.visible = true


func hide_game_over() -> void:
	over_overlay.visible = false


## A big banner across the middle of the screen, fading in and out: "DAY 3".
## The big button that sends everyone to the truck, shown while it waits.
func _sync_board(g) -> void:
	var show: bool = g.truck_waiting() and g.left_to_board() > 0 and not g.over
	if _btn_board == null:
		if not show:
			return
		_btn_board = Button.new()
		_btn_board.anchor_left = 0.5
		_btn_board.anchor_right = 0.5
		_btn_board.anchor_top = 1.0
		_btn_board.anchor_bottom = 1.0
		_btn_board.offset_left = -190
		_btn_board.offset_right = 190
		_btn_board.offset_top = -150
		_btn_board.offset_bottom = -96
		_btn_board.add_theme_font_size_override("font_size", 24)
		_btn_board.focus_mode = Control.FOCUS_NONE
		_btn_board.pressed.connect(func(): main.board_all())
		over_overlay.get_parent().add_child(_btn_board)
	_btn_board.visible = show
	if show:
		var waiting := 0
		for c in g.crew:
			if c["state"] == "boarding":
				waiting += 1
		var left: int = g.left_to_board() - waiting
		_btn_board.text = "Everyone in the truck! (G)" if left > 0 else "Climbing in... (%d)" % waiting
		_btn_board.disabled = left <= 0


func banner(title: String, sub := "") -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -400
	box.offset_right = 400
	box.offset_top = 140
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 96)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if sub != "":
		var st := Label.new()
		st.text = sub
		st.add_theme_font_size_override("font_size", 24)
		st.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(st)
	over_overlay.get_parent().add_child(box)
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.9)
	tw.tween_callback(box.queue_free)


func toast(text: String, kind := "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.38, 0.07, 0.05, 0.88) if kind == "danger" else Color(0.06, 0.07, 0.08, 0.86)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	p.add_child(l)
	toasts.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15).from(0.0)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# --- Inventory --------------------------------------------------------------
func inventory_open() -> bool:
	return inv_panel.visible


func toggle_inventory() -> void:
	if inv_panel.visible:
		close_inventory()
	elif not main.game.over:
		inv_panel.visible = true
		_hinted_storage = true
		_rebuild_inventory()


func close_inventory() -> void:
	inv_panel.visible = false
	selected = null


func on_inv_changed() -> void:
	if inv_panel.visible:
		_rebuild_inventory()


func _rebuild_inventory() -> void:
	var g = main.game
	storage_title.text = "BASE STORAGE  %d / %d" % [g.storage["items"].size(), g.storage["cap"]]
	slots.clear()
	for c in storage_grid.get_children():
		c.queue_free()
	for c in crew_list.get_children():
		c.queue_free()
	for i in g.storage["cap"]:
		storage_grid.add_child(_slot({"where": "storage", "i": i}))
	for s_i in g.crew.size():
		var s: Dictionary = g.crew[s_i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var k: Dictionary = g.survivor_stats(s)
		var nm := Label.new()
		nm.text = "%s\n%s · %d dps" % [s["name"], D.WEAPONS[s["weapon"]]["name"], k["dps"]]
		nm.theme_type_variation = &"DimLabel"
		nm.custom_minimum_size = Vector2(170, 0)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.custom_minimum_size = Vector2(170, 0)
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		info.tooltip_text = g.skills_detail(s)
		info.add_child(nm)
		var sk := Label.new()
		sk.text = g.skills_text(s)
		sk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sk.custom_minimum_size = Vector2(170, 0)
		sk.add_theme_font_size_override("font_size", 13)
		sk.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29, 0.9))
		info.add_child(sk)
		row.add_child(info)
		row.add_child(_slot({"where": "weapon", "s": s_i}))
		row.add_child(_slot({"where": "gear", "s": s_i, "g": 0}))
		row.add_child(_slot({"where": "gear", "s": s_i, "g": 1}))
		crew_list.add_child(row)
	_update_info()


func _slot(loc: Dictionary) -> Control:
	var s: Control = slot_scene.instantiate()
	s.loc = loc
	s.hud = self
	slots.append(s)
	s.refresh.call_deferred()
	return s


func select(loc: Dictionary) -> void:
	selected = loc.duplicate()
	inv_msg.text = ""
	for s in slots:
		if is_instance_valid(s):
			s.queue_redraw()
	_update_info()


func clear_selection() -> void:
	selected = null
	_update_info()


func set_inv_message(msg: String) -> void:
	inv_msg.text = msg


## A small label that follows the cursor while dragging.
func set_drag_label(text: String, key: String, from: Control = null) -> void:
	var l := Label.new()
	l.text = "  " + text + "  "
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, 0.92)
	sb.border_color = D.KIND_COLORS[D.item_kind(key)]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(6)
	l.add_theme_stylebox_override("normal", sb)
	(from if from != null else field).set_drag_preview(l)


func _update_info() -> void:
	var it = main.game.item_at(selected) if selected != null else null
	if it == null:
		info_label.text = "Select an item to see what it does. Double-click a supply to use it, or a molotov or pipe bomb to throw it."
		btn_use.visible = false
		btn_drop.visible = false
		return
	var key: String = it["key"]
	var kind := D.item_kind(key)
	info_label.text = D.item_name(key) + "  (" + D.KIND_TAG[kind] + ")\n" + D.item_desc(key)
	btn_use.visible = (kind == "supply" or kind == "throw") and selected["where"] == "storage"
	btn_use.text = "Throw" if kind == "throw" else "Use"
	btn_drop.visible = selected["where"] != "weapon"
	btn_drop.text = "Tear down (+%d scrap)" % main.game.salvage_value(key)


func use_selected() -> void:
	if selected == null or selected["where"] != "storage":
		return
	var it = main.game.item_at(selected)
	if it != null and D.item_kind(it["key"]) == "throw":
		main.start_throwing(it["uid"])
		clear_selection()
		return
	var r: Dictionary = main.game.use_supply(selected["i"])
	if r.get("msg", "") != "":
		if r.has("ok"):
			toast(r["msg"])
		else:
			set_inv_message(r["msg"])
	if r.has("ok"):
		clear_selection()


func _drop_selected() -> void:
	if selected == null:
		return
	var r: Dictionary = main.game.salvage(selected)
	if r.has("ok"):
		toast(r["msg"])
		clear_selection()
	elif r.get("msg", "") != "":
		set_inv_message(r["msg"])


# --- Every frame ------------------------------------------------------------
func update_hud() -> void:
	var g = main.game
	# The bar shows the weakest open wall; the label lists them all.
	var w: Dictionary = g.weakest_wall()
	wall_bar.max_value = w["max_hp"]
	wall_bar.value = w["hp"]
	var open_walls: Array = g.walls.filter(func(x): return g.sides_open[x["side"]])
	if open_walls.size() == 1:
		wall_label.text = ("Wall  DOWN  ·  %s" % g.wall_name()) if w.get("breached", false) else "Wall  %d / %d  ·  %s" % [ceili(w["hp"]), int(w["max_hp"]), g.wall_name()]
	else:
		var parts: PackedStringArray = []
		for x in open_walls:
			parts.append("%s %s" % [D.LANES[x["side"]]["name"], "DOWN" if x.get("breached", false) else str(ceili(x["hp"]))])
		wall_label.text = "%s  ·  %s" % ["   ".join(parts), g.wall_name()]
	if g.in_lull():
		wall_label.text += "  ·  lull"
	var fixing: int = g.repairers()
	if fixing > 0:
		wall_label.text += "  ·  repairing +%d/s" % int(g.repair_rate())
	resources_label.text = "Scrap %d" % g.scrap
	_grit_t -= get_process_delta_time()
	if _grit_t <= 0.0 and grit_label != null:
		_grit_t = 0.5
		grit_label.text = "Grit %d   +%d" % [main.progress.grit, g.run_result()["total"]]
	var you: Dictionary = g.crew[0]
	var wname: String = D.WEAPONS[you["weapon"]]["name"]
	# Just your gun, and a word while it reloads (no round count).
	if g.is_reloading(you):
		ammo_label.text = "%s  ·  reloading" % wname
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		ammo_label.text = wname
		ammo_label.add_theme_color_override("font_color", Color(0.93, 0.92, 0.9))
	# Food: stock bar, how fast it's going, how long it lasts.
	food_bar.max_value = maxf(D.FOOD_BAR_MIN, g.food)
	food_bar.value = g.food
	var rate: float = g.food_per_minute()
	var low: bool = g.hungry or g.food_time_left() < 60.0
	if g.hungry:
		food_label.text = "Food 0   ·   HUNGRY: shooting slower"
	else:
		food_label.text = "Food %.1f   ·   −%.1f/min%s" % [g.food, rate, "   ·   running low" if low else ""]
	food_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if low else Color(0.93, 0.92, 0.9))
	food_bar.modulate = Color(1, 0.5, 0.4) if low else Color.WHITE
	var trip_text := ""
	if g.trip != null:
		var verb: String = {"leaving": "heading out to", "away": "scavenging at", "returning": "coming back from"}.get(g.trip["who"]["state"], "at")
		trip_text = "%s is %s the %s." % [g.trip["who"]["name"], verb, D.SITES[g.trip["site"]]["name"]]
	trip_label.text = trip_text
	trip_label.visible = trip_text != ""
	if g.research_cur != "":
		research_label.text = "Researching %s." % D.RESEARCH[g.research_cur]["name"]
	else:
		research_label.text = "Nothing being researched. Press T."
	research_label.modulate = Color.WHITE if g.research_cur != "" else Color(1, 1, 1, 0.55)
	btn_research.text = "Research (T)"
	if research_overlay.visible:
		research_info.text = "Scrap %d. Research costs scrap up front and takes a while; one project at a time. The game waits while this is open." % g.scrap
	# Just the day or night: no clocks or counters.
	var phase: String = ("Night %d" if g.is_night() else "Day %d") % g.day_number()
	phase += "  ·  Level %d: %s" % [g.level, D.LEVELS[g.level - 1]["name"]]
	for side in range(1, D.LANES.size()):
		if g.sides_open[side] and not g.side_live(side):
			phase += "  ·  the %s lane is waking" % D.LANES[side]["name"].to_lower()
		elif not g.sides_open[side] and g.open_at[side] != INF and g.time >= g.open_at[side] - D.SIDE_WARNING:
			phase += "  ·  the %s opens soon" % D.LANES[side]["name"].to_lower()
	stats_label.text = phase
	_sync_board(g)
	btn_storage.text = "Storage %d/%d (I)" % [g.storage["items"].size(), g.storage["cap"]]
	btn_pause.text = "Resume (P)" if main.paused else "Pause (P)"
	btn_sound.text = "Sound: %s (N)" % ("off" if main.sfx.muted else "on")
	btn_workshop.text = "Workshop (B)"
	btn_map.text = "Scavenge (M)" if g.trip == null else "Map (M)"
	pause_overlay.visible = main.paused and not g.over and main.started and not scav_map.visible and not options_open() and not saves_open()

	var h := ""
	if main.started:
		if g.time < 10 and not main.settings.tutorial:
			h = "Hold the left mouse button to shoot. Your aim snaps to the zombie under the cursor."
		elif g.any_breach() and g.evac_go < 0.0:
			h = "A wall is down and they're getting in. Repair it to a quarter of its strength to close the gap. If everyone in the base falls, the run is over."
		elif main.throwing >= 0:
			h = "Click where to throw it. Whoever's on the nearest wall throws. Right-click or Esc to cancel."
		elif main.placing != "":
			h = "Click in the base to place it (green is clear). Right-click or Esc to cancel."
		elif main.selected_id >= 0:
			h = "Click anywhere in the base, or a spot on a walkway, to send them there. Click them again to set them repairing (on a walkway), or click a damaged turret to repair it. Right-click to cancel."
		elif w["hp"] < w["max_hp"] * 0.7 and g.repairers() == 0 and g.scrap > 0:
			h = "The %s wall is damaged. Click a survivor on it, then click them again to have them repair it (costs scrap)." % D.LANES[w["side"]]["name"].to_lower()
		elif g.time < 60 and g.crew.size() > 1:
			h = "Click a survivor to pick them, then click a walkway or anywhere in the base to move them there."
		elif not _hinted_map and not main.settings.tutorial and g.trip == null and not g.available_scavengers().is_empty():
			h = "You have someone who could go scavenging. Press M to open the map."
		elif g.crew.size() == 1 and g.time < D.FIRST_STRANGER_AT:
			h = "You're alone for now. Keep an eye on the mountain pass behind the base."
		elif not _hinted_research and not main.settings.tutorial and g.research_cur == "" and g.researched.is_empty() and g.scrap >= 15:
			h = "Press T to research: it unlocks guns, traps, walls, turrets and better provisions."
		elif not _hinted_storage and not main.settings.tutorial and g.storage["items"].size() > 0:
			h = "You have something in storage. Press I to open it and hand it out."
		elif inv_panel.visible:
			h = "Storage is open. Clicking the field still shoots, unless you grab a placed trap."
	hint.text = h


# --- Workshop ---------------------------------------------------------------
func toggle_workshop() -> void:
	workshop.visible = not workshop.visible and not main.game.over
	if workshop.visible:
		_refresh_shop()


func _build_shop() -> void:
	var title := Label.new()
	title.text = "WORKSHOP"
	title.theme_type_variation = &"HeaderLabel"
	shop_list.add_child(title)
	var help := Label.new()
	help.text = "Spend scrap. Items go to base storage.\nResearch (T) unlocks more."
	help.theme_type_variation = &"DimLabel"
	shop_list.add_child(help)
	for section in D.SHOP_SECTIONS:
		var h := Label.new()
		h.text = section[0]
		h.theme_type_variation = &"DimLabel"
		h.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29, 0.85))
		shop_list.add_child(h)
		for id in section[1]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var lbl := Label.new()
			lbl.text = D.SHOP[id]["name"]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			lbl.tooltip_text = D.SHOP[id].get("desc", D.item_desc(id) if D.ITEMS.has(id) else "")
			row.add_child(lbl)
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(96, 0)
			b.tooltip_text = lbl.tooltip_text
			var bid: String = id
			b.pressed.connect(func(): _buy(bid))
			row.add_child(b)
			shop_list.add_child(row)
			_shop_rows[id] = b
			_shop_labels[id] = lbl


func _refresh_shop() -> void:
	var g = main.game
	for id in _shop_rows:
		var b: Button = _shop_rows[id]
		var unlocked: bool = g.is_unlocked(id)
		var chk: Dictionary = g.can_buy(id)
		if not unlocked:
			b.text = "Locked"
		elif g.shop_maxed(id):
			b.text = "Built"
		else:
			b.text = "%d scrap" % g.shop_cost(id)
		_shop_labels[id].modulate = Color.WHITE if unlocked else Color(1, 1, 1, 0.4)
		b.disabled = not chk.has("ok")
		if id == "wire":
			_shop_labels[id].text = "Wire coil  (%d of %d)" % [g.wire_count(), D.WIRE_LIMIT]
		var desc: String = D.SHOP[id].get("desc", D.item_desc(id) if D.ITEMS.has(id) else "")
		b.tooltip_text = desc if chk.has("ok") else chk["msg"]
		_shop_labels[id].tooltip_text = desc if unlocked else desc + "\n" + chk["msg"]


func _buy(id: String) -> void:
	if D.BUILD_SIZE.has(id):
		# Pick where it goes: close the workshop and click in the base.
		toggle_workshop()
		main.start_placing(id)
		return
	var r: Dictionary = main.game.buy(id)
	if r.has("ok"):
		if D.ITEMS.has(id):
			toast(D.SHOP[id]["name"] + " built. It's in storage (I).")
		else:
			toast(D.SHOP[id]["name"] + " done.")
	elif r.get("msg", "") != "":
		toast(r["msg"])
	_refresh_shop()


# --- Scavenging map ---------------------------------------------------------
func map_open() -> bool:
	return scav_map.visible


func toggle_map() -> void:
	if scav_map.visible:
		scav_map.close()
	elif not main.game.over and main.started:
		_hinted_map = true
		scav_map.main = main
		scav_map.open()


# --- Research ---------------------------------------------------------------
func research_open() -> bool:
	return research_overlay != null and research_overlay.visible


func toggle_research() -> void:
	if research_overlay.visible:
		research_overlay.visible = false
		btn_research.release_focus()
	elif not main.game.over and main.started:
		_hinted_research = true
		if workshop.visible:
			toggle_workshop()
		close_inventory()
		research_msg.text = "Click a project to start it."
		research_overlay.visible = true
		research_tree.main = main
		research_tree.refresh()


func _build_research() -> void:
	# A button next to the workshop's.
	btn_research = Button.new()
	btn_research.text = "Research (T)"
	btn_research.focus_mode = Control.FOCUS_NONE
	btn_research.pressed.connect(toggle_research)
	btn_workshop.get_parent().add_child(btn_research)
	btn_workshop.get_parent().move_child(btn_research, btn_workshop.get_index() + 1)
	# Grit under the scrap: what's banked, and what this run has earned so far.
	grit_label = Label.new()
	grit_label.theme_type_variation = &"HeaderLabel"
	grit_label.add_theme_font_size_override("font_size", 17)
	grit_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.4))
	grit_label.tooltip_text = "Grit: spend it at the camp (C) on upgrades that last. The + is what this run has earned so far; it's banked when the run ends."
	grit_label.mouse_filter = Control.MOUSE_FILTER_PASS
	resources_label.get_parent().add_child(grit_label)
	resources_label.get_parent().move_child(grit_label, resources_label.get_index() + 1)
	# Your ammo, under the scrap.
	ammo_label = Label.new()
	ammo_label.add_theme_font_size_override("font_size", 15)
	resources_label.get_parent().add_child(ammo_label)
	resources_label.get_parent().move_child(ammo_label, resources_label.get_index() + 1)
	resources_label.get_parent().move_child(grit_label, resources_label.get_index() + 1)   # Grit right under Scrap
	# A line in the stats panel under the trip.
	research_label = Label.new()
	research_label.add_theme_font_size_override("font_size", 15)
	research_label.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29))
	trip_label.get_parent().add_child(research_label)
	# The tree, over everything but the game-over screen.
	var root: Control = over_overlay.get_parent()
	research_overlay = ColorRect.new()
	research_overlay.color = Color(0.02, 0.02, 0.03, 0.72)
	research_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	research_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	research_overlay.visible = false
	root.add_child(research_overlay)
	# Under the top buttons, so they still work while it's open.
	root.move_child(research_overlay, btn_workshop.get_parent().get_index())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	research_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "RESEARCH"
	title.theme_type_variation = &"HeaderLabel"
	box.add_child(title)
	research_info = Label.new()
	research_info.theme_type_variation = &"DimLabel"
	box.add_child(research_info)
	research_tree = ResearchTree.new()
	research_tree.main = main
	research_tree.message.connect(func(t): research_msg.text = t)
	box.add_child(research_tree)
	research_msg = Label.new()
	research_msg.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(research_msg)
	var close := Button.new()
	close.text = "Close (T)"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(toggle_research)
	box.add_child(close)


# --- Options ----------------------------------------------------------------
func options_open() -> bool:
	return options_overlay != null and options_overlay.visible


func toggle_options() -> void:
	options_overlay.visible = not options_overlay.visible
	if options_overlay.visible:
		_fill_options()
		if main.started and not main.game.over:
			main.paused = true


func _option_row(box: VBoxContainer, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(220, 0)
	ob.focus_mode = Control.FOCUS_NONE
	row.add_child(ob)
	box.add_child(row)
	return ob


const FOG_QUALITIES := ["Off", "Low", "Medium", "High"]
var _opt_fog: OptionButton
var _opt_gfx: OptionButton
var _opt_tut: OptionButton
var btn_camp: Button          # "Camp (C)" on the top bar
var grit_label: Label         # Grit under Scrap: banked, and what this run adds so far
var _grit_t := 0.0


func _build_options() -> void:
	var b := Button.new()
	b.text = "Options (O)"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(toggle_options)
	btn_sound.get_parent().add_child(b)
	var root: Control = over_overlay.get_parent()
	options_overlay = ColorRect.new()
	options_overlay.color = Color(0.02, 0.02, 0.03, 0.6)
	options_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	options_overlay.visible = false
	root.add_child(options_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "OPTIONS"
	title.theme_type_variation = &"HeaderLabel"
	box.add_child(title)
	_opt_mode = _option_row(box, "Display")
	for m in Settings.MODES:
		_opt_mode.add_item(m)
	_opt_size = _option_row(box, "Window size")
	if OS.has_feature("web"):   # the browser owns the window
		_opt_mode.get_parent().visible = false
		_opt_size.get_parent().visible = false
	_opt_scale = _option_row(box, "Interface size")
	for k in Settings.UI_SCALES:
		_opt_scale.add_item("%d%%" % int(round(k * 100)))
	_opt_gfx = _option_row(box, "Graphics")
	for q in ["Low", "Medium", "High"]:
		_opt_gfx.add_item(q)
	_opt_tut = _option_row(box, "Tutorial")
	_opt_tut.add_item("On")
	_opt_tut.add_item("Off")
	_opt_tut.item_selected.connect(func(i):
		var was: bool = main.settings.tutorial
		main.settings.tutorial = i == 0
		if main.settings.tutorial and not was:
			main.settings.tutorial_done = []   # on again: replay it from the start
		main.settings.save())
	_opt_fog = _option_row(box, "Fog")
	for q in FOG_QUALITIES:
		_opt_fog.add_item(q)
	var note := Label.new()
	note.text = "The game starts maximised to fit your screen. Everything is\ndrawn for 1600 x 900 and scaled up to the window, so a bigger\nwindow means bigger text; Interface size adjusts it from there.\nGraphics: Low if the game runs slowly (it's picked for your PC on the\nfirst run). Fog follows it, or set it on its own."
	note.theme_type_variation = &"DimLabel"
	box.add_child(note)
	var close := Button.new()
	close.text = "Close (O)"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(toggle_options)
	box.add_child(close)
	_opt_mode.item_selected.connect(func(i):
		main.settings.mode = Settings.MODES[i]
		_apply_options())
	_opt_size.item_selected.connect(func(i):
		main.settings.size = _sizes[i]
		_apply_options())
	_opt_scale.item_selected.connect(func(i):
		main.settings.ui_scale = Settings.UI_SCALES[i]
		_apply_options())
	_opt_gfx.item_selected.connect(func(i):
		var q: String = ["Low", "Medium", "High"][i]
		main.settings.graphics = q
		main.settings.fog = q   # the fog to match; it can still be set on its own
		_opt_fog.select(FOG_QUALITIES.find(q))
		main.apply_graphics()
		main.apply_fog()
		main.settings.save())
	_opt_fog.item_selected.connect(func(i):
		main.settings.fog = FOG_QUALITIES[i]
		main.apply_fog()
		main.settings.save())


func _fill_options() -> void:
	var st = main.settings
	_opt_mode.select(maxi(0, Settings.MODES.find(st.mode)))
	_sizes = Settings.sizes_that_fit()
	_opt_size.clear()
	var pick := 0
	for i in _sizes.size():
		_opt_size.add_item("%d x %d" % [_sizes[i].x, _sizes[i].y])
		if _sizes[i] == st.size:
			pick = i
	_opt_size.select(pick)
	_opt_size.disabled = st.mode != "Windowed"
	_opt_fog.select(maxi(0, FOG_QUALITIES.find(st.fog)))
	_opt_tut.select(0 if st.tutorial else 1)
	_opt_gfx.select(maxi(0, ["Low", "Medium", "High"].find(st.graphics)))
	var si: int = Settings.UI_SCALES.find(st.ui_scale)
	_opt_scale.select(si if si >= 0 else Settings.UI_SCALES.find(1.0))


func _apply_options() -> void:
	main.settings.apply(get_tree())
	main.settings.save()
	_opt_size.disabled = main.settings.mode != "Windowed"


# --- The camp ---------------------------------------------------------------
# Between runs: spend Grit on upgrades that last, pick the Heat, start a run.
func camp_open() -> bool:
	return camp_overlay != null and camp_overlay.visible


func toggle_camp() -> void:
	var run_over: bool = main.started and main.game.over
	if camp_overlay.visible:
		if not run_over or main.game.won:
			camp_overlay.visible = false
		return
	var mid_run: bool = main.started and not main.game.over
	_reset_armed = false
	if mid_run:
		_camp_msg.text = "The run is paused. Your skills take hold at once; the starting kit, blueprints and base wait for your next run."
	else:
		_camp_msg.text = "Upgrades last from run to run. Click one to buy its next level."
	# After a loss there's nowhere to go back to: the next run starts from here.
	_camp_back.visible = not run_over or main.game.won
	# In the middle of a run, no starting another (or wiping progress) from here.
	_camp_go.visible = not mid_run
	_camp_reset.visible = not mid_run
	_camp_heat.disabled = mid_run   # the Heat is set when a run starts
	_camp_level.disabled = mid_run
	camp_overlay.visible = true
	_refresh_camp()


func close_camp() -> void:
	if camp_overlay != null:
		camp_overlay.visible = false
		_camp_result.visible = false


func _build_camp() -> void:
	# Buttons on the title and game-over screens.
	var tb := Button.new()
	tb.text = "CAMP: spend Grit  (C)"
	tb.custom_minimum_size = Vector2(320, 44)
	tb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tb.focus_mode = Control.FOCUS_NONE
	tb.pressed.connect(toggle_camp)
	%StartButton.get_parent().add_child(tb)
	_btn_camp_over = Button.new()
	_btn_camp_over.text = "To the camp  (C)"
	_btn_camp_over.focus_mode = Control.FOCUS_NONE
	_btn_camp_over.add_theme_font_size_override("font_size", 20)
	_btn_camp_over.pressed.connect(toggle_camp)
	%PlayAgainButton.get_parent().add_child(_btn_camp_over)

	var root: Control = over_overlay.get_parent()
	camp_overlay = ColorRect.new()
	camp_overlay.color = Color(0.03, 0.03, 0.04, 0.94)
	camp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	camp_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	camp_overlay.visible = false
	root.add_child(camp_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	camp_overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	box.add_child(head)
	var title := Label.new()
	title.text = "CAMP"
	title.theme_type_variation = &"HeaderLabel"
	head.add_child(title)
	_camp_grit = Label.new()
	_camp_grit.add_theme_font_size_override("font_size", 24)
	_camp_grit.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29))
	head.add_child(_camp_grit)
	_camp_records = Label.new()
	_camp_records.theme_type_variation = &"DimLabel"
	_camp_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camp_records.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_camp_records)
	_camp_result = Label.new()
	_camp_result.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	_camp_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_result.visible = false
	box.add_child(_camp_result)
	var goal := Label.new()
	goal.text = "Hold out %d nights and an army truck takes you on to the next level. Every run pays Grit, win or lose: more for each night, kill, research and survivor." % D.WIN_NIGHTS
	goal.theme_type_variation = &"DimLabel"
	box.add_child(goal)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	box.add_child(cols)
	for c in D.META_CATS.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.custom_minimum_size = Vector2(300, 0)
		cols.add_child(col)
		var h := Label.new()
		h.text = D.META_CATS[c].to_upper()
		h.add_theme_color_override("font_color", Color(0.88, 0.7, 0.29, 0.9))
		col.add_child(h)
		for id in D.META:
			if D.META[id]["cat"] != c:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.tooltip_text = D.META[id]["desc"]
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			var nm := Label.new()
			nm.text = D.META[id]["name"]
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.mouse_filter = Control.MOUSE_FILTER_PASS
			nm.tooltip_text = D.META[id]["desc"]
			row.add_child(nm)
			var pips := Pips.new()
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pips)
			var b := Button.new()
			b.custom_minimum_size = Vector2(86, 0)
			b.focus_mode = Control.FOCUS_NONE
			var uid: String = id
			b.pressed.connect(func(): _camp_buy(uid))
			row.add_child(b)
			col.add_child(row)
			_camp_rows[id] = {"pips": pips, "button": b, "name": nm}
	var heat_row := HBoxContainer.new()
	heat_row.add_theme_constant_override("separation", 12)
	box.add_child(heat_row)
	var ll := Label.new()
	ll.text = "Level"
	heat_row.add_child(ll)
	_camp_level = _level_picker()
	heat_row.add_child(_camp_level)
	var hl := Label.new()
	hl.text = "Heat"
	heat_row.add_child(hl)
	_camp_heat = OptionButton.new()
	_camp_heat.focus_mode = Control.FOCUS_NONE
	_camp_heat.item_selected.connect(func(i):
		main.progress.heat = i
		main.progress.save()
		_refresh_camp())
	heat_row.add_child(_camp_heat)
	var hn := Label.new()
	hn.text = "Each Heat level: %d%% more zombies, %d%% tougher, %d%% more Grit. Win at your highest Heat to unlock the next." % [int(D.HEAT_SPAWN * 100), int(D.HEAT_HP * 100), int(D.HEAT_GRIT * 100)]
	hn.theme_type_variation = &"DimLabel"
	heat_row.add_child(hn)
	_camp_msg = Label.new()
	_camp_msg.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(_camp_msg)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var reset := Button.new()
	reset.text = "Reset all progress"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func():
		if _reset_armed:
			main.progress.reset()
			_reset_armed = false
			_camp_msg.text = "Progress wiped: no Grit, no upgrades, Heat 0."
		else:
			_reset_armed = true
			_camp_msg.text = "Click Reset again to wipe all Grit, upgrades and Heat. This can't be undone."
		_refresh_camp())
	foot.add_child(reset)
	_camp_reset = reset
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var back := Button.new()
	back.text = "Back  (C)"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(toggle_camp)
	foot.add_child(back)
	_camp_back = back
	var go := Button.new()
	go.text = "START A RUN  (Enter)"
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(func(): main.new_run())
	foot.add_child(go)
	_camp_go = go
	# And one on the top bar, to visit the camp in the middle of a run.
	var cb := Button.new()
	cb.text = "Camp (C)"
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "Spend Grit on upgrades. The run waits while you're there."
	cb.pressed.connect(toggle_camp)
	btn_pause.get_parent().add_child(cb)
	btn_camp = cb
	btn_pause.get_parent().move_child(cb, btn_pause.get_index())


func _camp_buy(id: String) -> void:
	var r: Dictionary = main.progress.buy(id)
	if r.has("ok"):
		main.sfx.play("build")
		var lv: int = main.progress.level(id)
		var nm := "%s%s" % [D.META[id]["name"], "" if main.progress.max_level(id) == 1 else " " + D.LEVEL_MARKS[lv - 1]]
		if main.started and main.game.apply_live(id, lv):
			_camp_msg.text = "%s bought. It takes hold right now, and in every run after." % nm
		elif main.started and not main.game.over:
			_camp_msg.text = "%s bought. It applies from your next run." % nm
		else:
			_camp_msg.text = "%s bought. It applies from your next run." % nm
	else:
		_camp_msg.text = r.get("msg", "")
	_refresh_camp()


func _refresh_camp() -> void:
	var pr = main.progress
	_camp_grit.text = "Grit %d" % pr.grit
	_camp_records.text = "Runs %d   Wins %d   Best: %d %s" % [pr.runs, pr.wins, pr.best_nights, "night" if pr.best_nights == 1 else "nights"]
	for id in _camp_rows:
		var r: Dictionary = _camp_rows[id]
		var lv: int = pr.level(id)
		var mx: int = pr.max_level(id)
		r["pips"].max_level = mx
		r["pips"].level = lv
		var b: Button = r["button"]
		var cost: int = pr.next_cost(id)
		var chk: Dictionary = pr.can_buy(id)
		b.text = "Max" if cost < 0 else "%d Grit" % cost
		b.disabled = not chk.has("ok")
		b.tooltip_text = D.META[id]["desc"] + ("" if chk.has("ok") else "\n" + chk.get("msg", ""))
		r["name"].modulate = Color.WHITE if lv > 0 else Color(1, 1, 1, 0.75)
	_fill_levels(_camp_level)
	_camp_level.select(clampi(pr.map_level, 1, _camp_level.item_count) - 1)
	_camp_heat.clear()
	for h in pr.max_heat + 1:
		_camp_heat.add_item("Heat %d%s" % [h, " (normal)" if h == 0 else ""])
	_camp_heat.select(clampi(pr.heat, 0, pr.max_heat))
	_camp_heat.disabled = pr.max_heat == 0
