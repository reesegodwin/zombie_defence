# The scavenging map: pick a site and a survivor, and send them out through the
# pass. The game pauses while the map is open.
extends Control

const D = preload("res://scripts/defs.gd")

signal closed

@onready var canvas: Control = %Canvas
@onready var site_name: Label = %SiteName
@onready var site_note: Label = %SiteNote
@onready var gone_label: Label = %GoneLabel
@onready var scrap_label: Label = %ScrapLabel
@onready var finds_label: Label = %FindsLabel
@onready var who_row: HFlowContainer = %WhoRow
@onready var send_button: Button = %SendButton
@onready var status_label: Label = %StatusLabel

var main
var site := ""
var who := -1
var status_extra := ""       # the chosen survivor's skills and odds on this trip


func _ready() -> void:
	visible = false
	canvas.site_clicked.connect(_on_site)
	send_button.pressed.connect(_send)
	%CloseButton.pressed.connect(close)


func open() -> void:
	canvas.main = main
	visible = true
	var open_sites: Array = main.game.open_sites()
	if site == "" or main.game.looted.has(site) or not main.game.biome_sites().has(site):
		site = open_sites[0] if not open_sites.is_empty() else main.game.biome_sites()[0]
	var free: Array = main.game.available_scavengers()
	if not free.has(who):
		who = free[0] if not free.is_empty() else -1
	_refresh()


## Where a site sits on screen (its drawing on the map), for the tutorial.
func site_rect(key: String) -> Rect2:
	var p: Vector2 = canvas.get_global_transform() * (canvas.site_px(key) + Vector2(0, -6))
	var r := 46.0 * canvas.get_global_transform().get_scale().x
	return Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)


func close() -> void:
	visible = false
	closed.emit()


func _on_site(key: String) -> void:
	site = key
	main.sfx.play("coin")
	_refresh()


func _chance(p: float) -> String:
	if p >= 1.0:
		return "someone's waiting there"
	if p >= 0.28:
		return "decent chance"
	if p >= 0.12:
		return "some chance"
	if p > 0.0:
		return "slim chance"
	return "none"


func _refresh() -> void:
	var g = main.game
	canvas.selected = site
	var s: Dictionary = D.SITES[site]
	site_name.text = s["name"]
	site_note.text = s["note"]
	var t := int(s["gone"])
	gone_label.text = "Gone for %d:%02d (there and back)" % [t / 60, t % 60]
	var tier: Array = D.SCRAP_TIERS[s["scrap"]]
	var looted: bool = g.looted.has(site)
	$Center/Sheet/Details/FindsTitle.visible = not looted
	if looted:
		gone_label.text = "Picked clean."
		scrap_label.text = "Nothing left worth the walk."
		finds_label.text = ""
	else:
		scrap_label.text = "Scrap: %s  (%d–%d)" % [D.SCRAP_NAMES[s["scrap"]].to_upper(), tier[0], tier[1]]
		finds_label.text = "Guns: %s\nFood: %s\nMolotovs, pipe bombs: %s\nSurvivors: %s" % [_chance(s["weapon_chance"]), _chance(s["food_chance"]), _chance(s["throw_chance"]), _chance(s["survivor_chance"])]
	for c in who_row.get_children():
		c.queue_free()
	var free: Array = g.available_scavengers()
	for i in free:
		var b := Button.new()
		b.text = g.crew[i]["name"]
		b.toggle_mode = true
		b.button_pressed = i == who
		b.theme_type_variation = &"InkButton"
		b.focus_mode = Control.FOCUS_NONE
		var idx: int = i
		b.pressed.connect(func():
			who = idx
			_refresh())
		who_row.add_child(b)
	if who >= 0 and who < g.crew.size():
		var sv: Dictionary = g.crew[who]
		var risk: float = g.death_chance(sv, site) * 100.0
		var tt := int(g.trip_seconds(sv, site))
		status_extra = "%s: %s.\nWith %s: gone %d:%02d, %s%% chance of not coming back." % [sv["name"], g.skills_text(sv), sv["name"], tt / 60, tt % 60, ("%.1f" % risk) if risk < 10.0 else str(int(round(risk)))]
		if not g.back_before_dark(sv, site):
			status_extra += "\nWarning: they won't be back before the horde comes." if not g.is_night() else "\nIt's night: the horde is here, and they'll be gone while it lasts."
	else:
		status_extra = ""
	var chk: Dictionary = g.can_send(who, site)
	send_button.disabled = not chk.has("ok")
	send_button.text = "Send %s to the %s" % [g.crew[who]["name"], s["name"]] if chk.has("ok") else "Send"
	_update_status()


func _update_status() -> void:
	var g = main.game
	if g.looted.has(site):
		status_label.text = "Already looted. Pick a place that isn't crossed out."
	elif g.open_sites().is_empty() and g.trip == null:
		status_label.text = "Every place on the map has been picked clean."
	elif g.trip != null:
		var left := int(ceil(g.trip_time_left()))
		status_label.text = "%s is out at the %s. Back in %d:%02d." % [g.trip["who"]["name"], D.SITES[g.trip["site"]]["name"], left / 60, left % 60]
	elif g.available_scavengers().is_empty():
		status_label.text = "Nobody to send. You have to stay on the wall. Wait for a survivor to find you."
	else:
		status_label.text = status_extra if status_extra != "" else "Only one person can be out at a time. Their gun leaves the wall with them."


func _send() -> void:
	var r: Dictionary = main.act("send_scavenger", [who, site])
	if r.has("ok"):
		close()
	else:
		status_label.text = r.get("msg", "")


func _process(_dt: float) -> void:
	if visible:
		_update_status()
