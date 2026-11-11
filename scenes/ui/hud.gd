# The on-screen interface. The layout lives in hud.tscn (open it to rearrange
# or restyle); this script fills it in from the game each frame.
extends CanvasLayer

const D = preload("res://scripts/defs.gd")

@export var slot_scene: PackedScene
@export var card_scene: PackedScene

var main                     # main.gd, set by Main
var selected = null          # an inventory location Dictionary, or null
var slots: Array = []

@onready var field: Control = %Field
@onready var wall_label: Label = %WallLabel
@onready var wall_bar: ProgressBar = %WallBar
@onready var level_label: Label = %LevelLabel
@onready var xp_bar: ProgressBar = %XpBar
@onready var stats_label: Label = %StatsLabel
@onready var hint: Label = %Hint
@onready var toasts: VBoxContainer = %Toasts
@onready var btn_auto: Button = %AutoButton
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
@onready var cards_overlay: Control = %CardsOverlay
@onready var cards_title: Label = %CardsTitle
@onready var card_row: HBoxContainer = %CardRow
@onready var over_overlay: Control = %GameOverOverlay
@onready var over_stats: Label = %GameOverStats
@onready var title_overlay: Control = %TitleOverlay

var _hinted_storage := false


func _ready() -> void:
	field.main = main
	btn_auto.pressed.connect(func(): main.toggle_auto())
	btn_storage.pressed.connect(toggle_inventory)
	btn_pause.pressed.connect(func(): main.toggle_pause())
	btn_sound.pressed.connect(func(): main.toggle_sound())
	btn_use.pressed.connect(use_selected)
	btn_drop.pressed.connect(_drop_selected)
	%PlayAgainButton.pressed.connect(func(): main.restart())
	%StartButton.pressed.connect(func(): main.start())
	title_overlay.visible = true


func _process(_dt: float) -> void:
	if field.main == null and main != null:
		field.main = main


# --- Screens ----------------------------------------------------------------
func hide_title() -> void:
	title_overlay.visible = false


func show_cards() -> void:
	var g = main.game
	for c in card_row.get_children():
		c.queue_free()
	for i in g.cards.size():
		var card: Button = card_scene.instantiate()
		card_row.add_child(card)
		card.setup(g.cards[i], i)
		var idx: int = i
		card.pressed.connect(func(): main.choose_card(idx))
	var more: String = "" if g.pending_levels == 0 else "   (+%d more)" % g.pending_levels
	cards_title.text = "LEVEL %d: CHOOSE ONE%s" % [g.level, more]
	cards_overlay.visible = true


func hide_cards() -> void:
	cards_overlay.visible = false


func show_game_over() -> void:
	var g = main.game
	var t: int = int(g.time)
	var text := "You held for %d:%02d.\nLevel %d  ·  %d of the dead put down  ·  crew of %d" % [t / 60, t % 60, g.level, g.kills, g.crew.size()]
	if g.picks.size() > 0:
		text += "\n\nLast upgrades: " + ", ".join(PackedStringArray(g.picks.slice(maxi(0, g.picks.size() - 8))))
	over_stats.text = text
	over_overlay.visible = true


func hide_game_over() -> void:
	over_overlay.visible = false


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
		row.add_child(nm)
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
		info_label.text = "Select an item to see what it does. Double-click a supply to use it."
		btn_use.visible = false
		btn_drop.visible = false
		return
	var key: String = it["key"]
	var kind := D.item_kind(key)
	info_label.text = D.item_name(key) + "  (" + D.KIND_TAG[kind] + ")\n" + D.item_desc(key)
	btn_use.visible = kind == "supply" and selected["where"] == "storage"
	btn_drop.visible = selected["where"] != "weapon"


func use_selected() -> void:
	if selected == null or selected["where"] != "storage":
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
	var r: Dictionary = main.game.drop_item(selected)
	if r.has("ok"):
		clear_selection()
	elif r.get("msg", "") != "":
		set_inv_message(r["msg"])


# --- Every frame ------------------------------------------------------------
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
	btn_storage.text = "Storage %d/%d (I)" % [g.storage["items"].size(), g.storage["cap"]]
	btn_pause.text = "Resume (P)" if main.paused else "Pause (P)"
	btn_sound.text = "Sound: %s (M)" % ("off" if main.sfx.muted else "on")
	pause_overlay.visible = main.paused and not g.over and g.cards.is_empty() and main.started

	var h := ""
	if main.started:
		if g.time < 10:
			h = "Auto-fire is on: you shoot whatever is closest to the wall." if g.input_auto else "Hold the left mouse button to shoot. Your aim snaps to the zombie under the cursor."
		elif not _hinted_storage and g.storage["items"].size() > 0:
			h = "You have something in storage. Press I to open it and hand it out."
		elif inv_panel.visible:
			h = "Storage is open. Clicking the field still shoots, unless you grab a placed trap."
	hint.text = h
