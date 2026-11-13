# The tutorial: no reading, just pointing. When the game reaches a point where
# there's something worth learning, the button to press gets a pulsing gold
# outline and a bobbing arrow; once that opens a menu, the next thing to
# click in it lights up, and so on until it's done. The very first steps show
# keys and a mouse instead (walk, shoot).
#
# Each step shows once on this computer, ever (and counts as done if you do it
# without help). It can be turned off in Options; turning it back on replays
# it. The step logic (ready/done) only looks at the game, so the tests check it.
extends Control

const D = preload("res://scripts/defs.gd")

const GOLD := Color(1.0, 0.8, 0.25)
const INK := Color(0.05, 0.05, 0.05, 0.9)

## In order: the first one that's ready and not done is shown.
const STEPS := ["walk", "shoot", "rescue", "research", "buy_smg", "equip", "research_build", "turret", "radio", "repair", "truck", "grit"]
## Steps that can show over the game-over screen and the camp.
const CAMP_STEPS := ["grit"]
const CABIN := "ranger_cabin"

var main
var current := ""          # the step being shown, or ""
var _t := 0.0
var _walk_from = null      # where you stood when the run began (for "walk")
var _run_time := 0.0       # seconds into this run, for the first steps' time-outs


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func on() -> bool:
	return main != null and main.settings.tutorial


## A new run: the walking and shooting steps watch from here.
func run_started() -> void:
	_walk_from = null
	_run_time = 0.0


# --- The steps (game only, for the tests) -------------------------------------
static func has_smg(g) -> bool:
	return g.storage["items"].any(func(it): return it["key"] == "smg") or g.crew.any(func(c): return c["weapon"] == "smg")


static func damaged_wall(g) -> Variant:
	for w in g.walls:
		if g.sides_open[w["side"]] and w["hp"] < w["max_hp"] * 0.95 and not w.get("breached", false):
			return w
	return null


## The building project to point out: Auto-turrets if its needs are met,
## else the Radio; "" if neither is open and affordable.
static func build_project(g) -> String:
	for id in ["turrets", "radio"]:
		if g.research_state(id) == "open" and g.scrap >= D.RESEARCH[id]["cost"]:
			return id
	return ""


## Grit: worth a visit to the camp once it buys something and nothing has
## been bought there yet.
static func grit_ready(pr) -> bool:
	if not pr.levels.is_empty():
		return false
	for id in D.META:
		if pr.can_buy(id).has("ok"):
			return true
	return false


static func grit_done(pr) -> bool:
	return not pr.levels.is_empty()


static func step_ready(id: String, g) -> bool:
	match id:
		"research_build":
			return g.research_cur == "" and build_project(g) != ""
		"turret":
			return g.researched.has("turrets") and g.turrets.is_empty() and g.can_buy("turret").has("ok")
		"radio":
			return g.researched.has("radio") and g.radio == null and g.can_buy("radio").has("ok")
		"rescue":
			return g.trip == null and not g.looted.has(CABIN) and not g.available_scavengers().is_empty()
		"research":
			return g.research_cur == "" and g.researched.is_empty() and g.scrap >= D.RESEARCH["firearms"]["cost"]
		"buy_smg":
			return g.researched.has("firearms")
		"equip":
			return g.storage["items"].any(func(it): return it["key"] == "smg")
		"repair":
			return damaged_wall(g) != null and g.repairers() == 0 and g.scrap > 0
		"truck":
			return g.truck_waiting() and g.left_to_board() > 0
	return false


static func step_done(id: String, g) -> bool:
	match id:
		"research_build":
			return g.researched.has("turrets") or g.researched.has("radio") or g.research_cur in ["turrets", "radio"]
		"turret":
			return not g.turrets.is_empty()
		"radio":
			return g.radio != null
		"rescue":
			return g.looted.has(CABIN) or (g.trip != null and g.trip["site"] == CABIN)
		"research":
			return g.research_cur != "" or not g.researched.is_empty()
		"buy_smg":
			return has_smg(g)
		"equip":
			return g.crew.any(func(c): return c["weapon"] == "smg")
		"repair":
			return g.repairers() > 0
		"truck":
			return g.evac_go >= 0.0
	return false


# --- Each frame ---------------------------------------------------------------
func _process(dt: float) -> void:
	_t += dt
	var was := current
	current = ""
	if on() and main.started:
		var playing: bool = not main.game.over and not main.hud.camp_open()
		if playing:
			_run_time += dt
			_check_done()
		elif not main.settings.tutorial_done.has("grit") and grit_done(main.progress):
			main.settings.tutorial_done.append("grit")
			main.settings.save()
		if _showable():
			for id in STEPS:
				if not playing and not id in CAMP_STEPS:
					continue
				if not main.settings.tutorial_done.has(id) and _ready_now(id):
					current = id
					break
	if current != "" or was != "":
		queue_redraw()


func _check_done() -> void:
	var g = main.game
	var changed := false
	for id in STEPS:
		if main.settings.tutorial_done.has(id):
			continue
		if _done_now(id, g):
			main.settings.tutorial_done.append(id)
			changed = true
	if changed:
		main.settings.save()


func _done_now(id: String, g) -> bool:
	var me: Dictionary = g.crew[0]
	match id:
		"walk":
			if _walk_from == null:
				_walk_from = Vector2(me["x"], me["y"])
			return Vector2(me["x"], me["y"]).distance_to(_walk_from) > 2.0 or _run_time > 25.0
		"shoot":
			return me.get("flash", 0.0) > 0.0 and g.input_firing or _run_time > 40.0
		"grit":
			return grit_done(main.progress)
	return step_done(id, g)


func _ready_now(id: String) -> bool:
	var g = main.game
	match id:
		"walk", "shoot":
			return g.crew[0]["is_player"] and g.crew[0]["hp"] > 0.0
		"grit":
			return grit_ready(main.progress)
	return step_ready(id, g)


## Not over the options, the camp or the title.
func _showable() -> bool:
	var h = main.hud
	return not h.options_open() and not h.saves_open() and (not main.paused or h.camp_open())


# --- What to point at -----------------------------------------------------------
## The thing to click now: a Rect2 (on screen) or a Vector2 (a point in the
## world, already on screen), or null.
func _target():
	var h = main.hud
	var g = main.game
	match current:
		"rescue":
			if not h.map_open():
				return h.btn_map.get_global_rect()
			var m = h.scav_map
			if m.site != CABIN:
				return m.site_rect(CABIN)
			if m.who < 0 and m.who_row.get_child_count() > 0:
				return m.who_row.get_child(0).get_global_rect()
			return m.send_button.get_global_rect()
		"research":
			if not h.research_open():
				return h.btn_research.get_global_rect()
			var b: Control = h.research_tree._buttons["firearms"]
			return b.get_global_rect()
		"buy_smg":
			if h.research_open():
				return h.btn_research.get_global_rect()   # close it first
			if not h.workshop.visible:
				return h.btn_workshop.get_global_rect()
			return h._shop_rows["smg"].get_global_rect()
		"equip":
			if not h.inventory_open():
				return h.btn_storage.get_global_rect()
			return _slot_rect(func(loc): return loc["where"] == "storage" and _item_key(loc) == "smg")
		"repair":
			var wv = damaged_wall(g)
			if wv == null:
				return null
			var w: Dictionary = wv
			var best := -1
			var bd := INF
			for i in g.crew.size():
				var s: Dictionary = g.crew[i]
				if s["state"] != "wall" or s["hp"] <= 0.0:
					continue
				var d: float = 0.0 if s["side"] == w["side"] and not s.has("post") else 10.0 + absf(s["u"] - D.LANES[w["side"]]["u0"])
				if s["is_player"]:
					d += 5.0   # one of the crew, so you keep shooting
				if s["id"] == main.selected_id:
					d = -1.0   # already picked: click them again
				if d < bd:
					bd = d
					best = i
			if best < 0:
				return null
			var s: Dictionary = g.crew[best]
			var p: Vector2 = main.rig.world_to_screen(Vector3(s["x"], D.DECK_H + 2.0, s["y"]))
			if s["id"] == main.selected_id:
				p.y -= 64.0   # above the big "Click again to REPAIR"
			return p
		"truck":
			if h._btn_board != null and h._btn_board.visible:
				return h._btn_board.get_global_rect()
		"research_build":
			var pid := build_project(g)
			if pid == "":
				return null
			if not h.research_open():
				return h.btn_research.get_global_rect()
			return h.research_tree._buttons[pid].get_global_rect()
		"turret", "radio":
			if main.placing == current:
				return _free_spot(current)
			if h.research_open():
				return h.btn_research.get_global_rect()   # close it first
			if not h.workshop.visible:
				return h.btn_workshop.get_global_rect()
			return h._shop_rows[current].get_global_rect()
		"grit":
			if h.camp_open():
				var best = null
				var bc := 1 << 30
				for id in h._camp_rows:
					if main.progress.can_buy(id).has("ok") and main.progress.next_cost(id) < bc:
						bc = main.progress.next_cost(id)
						best = id
				return h._camp_rows[best]["button"].get_global_rect() if best != null else null
			if g.over and h._btn_camp_over != null and h._btn_camp_over.is_visible_in_tree():
				return h._btn_camp_over.get_global_rect()
			return h.btn_camp.get_global_rect()
	return null


## A good free spot in the yard for a building (behind the front wall), on
## screen, for the arrow while you're placing it.
func _free_spot(id: String):
	var g = main.game
	var y := D.WALK_Y + 2.2
	while y < D.BASE_Y1 - 2.0:
		for x in [8.0, 14.0, 6.0, 16.0, 4.0, 18.0, 11.0]:
			if g.can_build_at(id, x, y).has("ok"):
				return main.rig.world_to_screen(Vector3(x, 0.3, y))
		y += 1.5
	return null


func _item_key(loc: Dictionary) -> String:
	var it = main.game.item_at(loc)
	return it["key"] if it != null else ""


func _slot_rect(pick: Callable):
	for s in main.hud.slots:
		if is_instance_valid(s) and s.is_visible_in_tree() and pick.call(s.loc):
			return s.get_global_rect()
	return null


# --- Drawing ------------------------------------------------------------------
func _draw() -> void:
	if current == "":
		return
	match current:
		"walk":
			_draw_keys()
			return
		"shoot":
			_draw_mouse()
			return
	var tgt = _target()
	if tgt is Rect2:
		_highlight(tgt)
		if current == "equip" and main.hud.inventory_open():
			# Then drag it onto your weapon slot.
			var to = _slot_rect(func(loc): return loc["where"] == "weapon" and loc["s"] == 0)
			if to != null:
				_drag_arrow(tgt.get_center(), to.get_center())
	elif tgt is Vector2:
		_point_at(tgt)
	if current == "truck" and main.truck != null:
		_point_at(main.rig.world_to_screen(main.truck.position + Vector3(0, 3.4, 0)))


## A pulsing gold frame round r, and an arrow toward it from the side with room.
func _highlight(r: Rect2) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var grow := 4.0 + pulse * 3.0
	var box := r.grow(grow)
	for k in 3:   # a soft glow, then the frame
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(3 + (2 - k) * 3)
		sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, (0.12 + 0.1 * pulse) if k < 2 else 0.95)
		draw_style_box(sb, box.grow(float(2 - k) * 3.0))
	var size := get_viewport_rect().size
	var c := r.get_center()
	var dir: Vector2
	if c.y < size.y * 0.1:
		dir = Vector2.UP          # under a top-bar button, pointing up at it
	elif c.x > size.x * 0.55:
		dir = Vector2.RIGHT       # to its left, pointing right
	else:
		dir = Vector2.LEFT        # to its right, pointing left
	var tip := c - dir * (absf(dir.x) * r.size.x * 0.5 + absf(dir.y) * r.size.y * 0.5 + grow + 8.0)
	_arrow(tip, dir)


## An arrow coming down onto a point in the world (a survivor, the truck).
func _point_at(p: Vector2) -> void:
	_arrow(p, Vector2.DOWN)


## A chunky arrow whose tip bobs toward tip, pointing along dir.
func _arrow(tip: Vector2, dir: Vector2) -> void:
	var bob := (0.5 + 0.5 * sin(_t * 6.0)) * 10.0
	var t := tip - dir * bob
	var side := Vector2(-dir.y, dir.x)
	var head := [t, t - dir * 26.0 + side * 18.0, t - dir * 26.0 - side * 18.0]
	var tail := [t - dir * 24.0 + side * 7.0, t - dir * 62.0 + side * 7.0, t - dir * 62.0 - side * 7.0, t - dir * 24.0 - side * 7.0]
	# A dark outline under the gold, so it shows on anything.
	for pts in [head, tail]:
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, INK, 5.0, true)
	draw_colored_polygon(PackedVector2Array(tail), GOLD)
	draw_colored_polygon(PackedVector2Array(head), GOLD)


## A dashed curve from one place to another (drag this there).
func _drag_arrow(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5 + Vector2(0, -60)
	var pts := PackedVector2Array()
	for k in 25:
		var t := k / 24.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	var phase := fmod(_t * 2.0, 1.0)
	for k in range(0, pts.size() - 1, 2):
		var kk := (k + int(phase * 2.0)) % (pts.size() - 1)
		draw_line(pts[kk], pts[kk + 1], GOLD, 4.0, true)
	var dir := (pts[-1] - pts[-3]).normalized()
	_arrow(b - dir * 14.0, dir)


## W, A, S and D keycaps beside you.
func _draw_keys() -> void:
	var me: Dictionary = main.game.crew[0]
	var p: Vector2 = main.rig.world_to_screen(Vector3(me["x"], D.DECK_H + 1.0, me["y"])) + Vector2(70, -40)
	var font := get_theme_default_font()
	var k := 34.0
	var lift := (0.5 + 0.5 * sin(_t * 4.0)) * 3.0
	for key in [["W", Vector2(0, -1)], ["A", Vector2(-1, 0)], ["S", Vector2(0, 0)], ["D", Vector2(1, 0)]]:
		var at: Vector2 = p + key[1] * (k + 6.0)
		var r := Rect2(at - Vector2(k, k) * 0.5 - Vector2(0, lift if key[0] == "W" else 0.0), Vector2(k, k))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.11, 0.9)
		sb.border_color = GOLD
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, r)
		draw_string(font, r.position + Vector2(0, k * 0.7), key[0], HORIZONTAL_ALIGNMENT_CENTER, k, 20, GOLD)


## A mouse with its left button lit, beside the cursor (or you).
func _draw_mouse() -> void:
	var at: Vector2
	if main._mouse_screen != null:
		at = main._mouse_screen + Vector2(46, 34)
	else:
		var me: Dictionary = main.game.crew[0]
		at = main.rig.world_to_screen(Vector3(me["x"], D.DECK_H + 1.0, me["y"])) + Vector2(70, -40)
	var body := Rect2(at - Vector2(18, 26), Vector2(36, 52))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.9)
	sb.border_color = Color(0.85, 0.85, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	draw_style_box(sb, body)
	var pulse := 0.55 + 0.45 * sin(_t * 6.0)
	var left := PackedVector2Array([at + Vector2(-15, -4), at + Vector2(-15, -14), at + Vector2(-11, -21), at + Vector2(-5, -24), at + Vector2(-1, -24), at + Vector2(-1, -4)])
	draw_colored_polygon(left, Color(GOLD.r, GOLD.g, GOLD.b, pulse))
	draw_line(at + Vector2(0, -24), at + Vector2(0, -4), Color(0.85, 0.85, 0.85), 2.0, true)
	draw_line(at + Vector2(-16, -4), at + Vector2(16, -4), Color(0.85, 0.85, 0.85), 2.0, true)
