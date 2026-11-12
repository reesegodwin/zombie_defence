# Draws the scavenging map as an ink sketch on parchment: the outpost, the
# mountains and the pass, trails out to each site, and whoever is out there.
# Every line wobbles a little, seeded so the map looks the same each time.
extends Control

const D = preload("res://scripts/defs.gd")

signal site_clicked(key: String)

const INK := Color(0.2, 0.13, 0.08, 0.92)
const FADED := Color(0.2, 0.13, 0.08, 0.45)
const RED := Color(0.62, 0.1, 0.06, 0.95)
const OUTPOST := Vector2(0.5, 0.12)
const PASS := Vector2(0.5, 0.37)

var main
var selected := ""
var hover := ""
var font: Font


func _ready() -> void:
	font = get_theme_font("font", "InkLabel")
	mouse_filter = Control.MOUSE_FILTER_STOP


func px(p: Vector2) -> Vector2:
	return p * size


func site_px(key: String) -> Vector2:
	return px(D.SITES[key]["pos"])


# --- Sketch primitives ------------------------------------------------------
func _noise(seed_val: float, t: float) -> float:
	return sin(t * 12.9 + seed_val * 3.1) * 0.6 + sin(t * 31.7 + seed_val * 7.7) * 0.4


func wline(a: Vector2, b: Vector2, col: Color, width := 2.0, seed_val := 0.0, dashed := false) -> void:
	var n := maxi(2, int(a.distance_to(b) / 9.0))
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) + side * _noise(seed_val, t * 3.0) * 1.6)
	if dashed:
		for i in range(0, pts.size() - 1, 2):
			draw_line(pts[i], pts[i + 1], col, width, true)
	else:
		draw_polyline(pts, col, width, true)
		var faint := col
		faint.a *= 0.35
		var shifted := PackedVector2Array()
		for p in pts:
			shifted.append(p + Vector2(0.8, 0.9))
		draw_polyline(shifted, faint, maxf(1.0, width * 0.6), true)


func wpath(points: Array, col: Color, width := 2.0, seed_val := 0.0, dashed := false) -> void:
	for i in range(1, points.size()):
		wline(points[i - 1], points[i], col, width, seed_val + i, dashed)


func wcircle(c: Vector2, r: float, col: Color, width := 2.0, seed_val := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 29:
		var a := TAU * i / 26.0 + seed_val
		pts.append(c + Vector2(cos(a), sin(a)) * (r + _noise(seed_val, i * 0.2) * 1.5))
	draw_polyline(pts, col, width, true)


func ink_text(p: Vector2, text: String, size_px := 24, col := INK, center := true) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var at := p - Vector2(w * 0.5 if center else 0.0, 0)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


# Trail from the pass to a site: a gentle bend so it doesn't look ruled.
func trail_points(key: String) -> Array:
	var a := px(PASS) + Vector2(0, 12)
	var b := site_px(key) - Vector2(0, 26)
	var mid := a.lerp(b, 0.5) + Vector2((b.y - a.y) * 0.12, -(b.x - a.x) * 0.08)
	return [a, a.lerp(mid, 0.6), mid, mid.lerp(b, 0.5), b]


func point_on(points: Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var target := clampf(t, 0.0, 1.0) * total
	for i in range(1, points.size()):
		var seg: float = points[i - 1].distance_to(points[i])
		if target <= seg:
			return points[i - 1].lerp(points[i], target / maxf(seg, 0.01))
		target -= seg
	return points[-1]


# --- The map ----------------------------------------------------------------
func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if main == null:
		return
	var g = main.game
	# The dead lands to the north.
	for i in 22:
		var x := 0.06 + i * 0.04
		wline(px(Vector2(x, 0.02)), px(Vector2(x + 0.03, 0.055)), FADED, 1.2, i)
	ink_text(px(Vector2(0.5, 0.085)), "the dead come from the north", 22, FADED)

	# The outpost: the wall, the walkway, a few huts.
	var o := px(OUTPOST)
	wline(o + Vector2(-60, -8), o + Vector2(60, -8), INK, 4.0, 1.0)
	for k in 7:
		wline(o + Vector2(-56 + k * 18, -14), o + Vector2(-56 + k * 18, -2), INK, 2.0, k)
	wline(o + Vector2(-50, 6), o + Vector2(-30, 6), INK, 2.0, 2.0)
	wline(o + Vector2(-50, 6), o + Vector2(-50, 22), INK, 2.0, 3.0)
	wline(o + Vector2(-30, 6), o + Vector2(-30, 22), INK, 2.0, 4.0)
	wline(o + Vector2(-50, 22), o + Vector2(-30, 22), INK, 2.0, 5.0)
	wline(o + Vector2(20, 10), o + Vector2(32, 2), INK, 2.0, 6.0)
	wline(o + Vector2(32, 2), o + Vector2(44, 10), INK, 2.0, 7.0)
	wline(o + Vector2(22, 10), o + Vector2(22, 22), INK, 2.0, 8.0)
	wline(o + Vector2(42, 10), o + Vector2(42, 22), INK, 2.0, 9.0)
	ink_text(o + Vector2(96, 4), "Outpost", 30, INK)
	ink_text(o + Vector2(96, 26), "(home)", 20, FADED)

	# Trail from the outpost down to the pass.
	wpath([o + Vector2(0, 26), px(Vector2(0.5, 0.24)), px(PASS) - Vector2(0, 26)], INK, 2.0, 11.0, true)

	# The mountains, with a gap for the pass.
	var i2 := 0
	var x2 := 0.03
	while x2 < 0.97:
		if absf(x2 - 0.5) > 0.045:
			var base := px(Vector2(x2, 0.37 + sin(x2 * 17.0) * 0.012))
			var h := 34.0 + absf(sin(x2 * 9.3)) * 30.0 + (0.0 if absf(x2 - 0.5) > 0.12 else 10.0)
			var w := 22.0 + absf(cos(x2 * 7.1)) * 12.0
			var peak := base + Vector2(sin(x2 * 5.0) * 5.0, -h)
			wline(base + Vector2(-w, 0), peak, INK, 2.2, i2)
			wline(peak, base + Vector2(w, 0), INK, 2.2, i2 + 0.5)
			for k in 3:
				var t := 0.3 + k * 0.18
				var a := peak.lerp(base + Vector2(w, 0), t)
				wline(a, a + Vector2(-7, 8), FADED, 1.2, i2 + k)
			if h > 54.0:
				wline(peak + Vector2(-8, 12), peak + Vector2(0, 7), INK, 1.5, i2 + 3)
				wline(peak + Vector2(0, 7), peak + Vector2(9, 12), INK, 1.5, i2 + 4)
		x2 += 0.042
		i2 += 1
	ink_text(px(PASS) + Vector2(0, -44), "the pass", 24, RED)
	wline(px(PASS) + Vector2(-26, -36), px(PASS) + Vector2(-14, -18), RED, 1.6, 40.0)

	# Trails to every site, then the sites themselves.
	for key in D.SITE_KEYS:
		var on: bool = key == selected
		wpath(trail_points(key), RED if on else FADED, 3.0 if on else 1.8, key.length(), not on)
	for key in D.SITE_KEYS:
		_draw_site(key)

	# Whoever is out there right now.
	if g.trip != null:
		var who: Dictionary = g.trip["who"]
		var key: String = g.trip["site"]
		var pts := trail_points(key)
		var at: Vector2
		match who["state"]:
			"leaving":
				at = px(PASS) if who["path_t"] < 1.0 else pts[-1]
			"away":
				at = point_on(pts, clampf(g.trip["t"] / g.trip["away"] * 2.0, 0.0, 1.0)) if g.trip["t"] < g.trip["away"] * 0.5 else point_on(pts, clampf(2.0 - g.trip["t"] / g.trip["away"] * 2.0, 0.0, 1.0))
			_:
				at = px(PASS)
		_draw_figure(at, RED)
		ink_text(at + Vector2(0, -30), who["name"], 24, RED)

	# A compass in the corner.
	var c := px(Vector2(0.08, 0.9))
	wcircle(c, 22, FADED, 1.5, 3.0)
	wline(c + Vector2(0, 18), c + Vector2(0, -26), INK, 2.0, 1.0)
	wline(c + Vector2(0, -26), c + Vector2(-6, -16), INK, 2.0, 2.0)
	wline(c + Vector2(0, -26), c + Vector2(6, -16), INK, 2.0, 3.0)
	ink_text(c + Vector2(0, -32), "N", 22, INK)


func _draw_figure(at: Vector2, col: Color) -> void:
	wcircle(at + Vector2(0, -14), 4.0, col, 2.0, 1.0)
	wline(at + Vector2(0, -10), at + Vector2(0, 0), col, 2.0, 2.0)
	wline(at, at + Vector2(-4, 8), col, 2.0, 3.0)
	wline(at, at + Vector2(4, 8), col, 2.0, 4.0)
	wline(at + Vector2(-5, -7), at + Vector2(5, -5), col, 2.0, 5.0)


func _draw_site(key: String) -> void:
	var site: Dictionary = D.SITES[key]
	var p := site_px(key)
	var on: bool = key == selected
	var col := RED if on else INK
	var sd := float(key.length())
	match site["icon"]:
		"farm":
			wpath([p + Vector2(-16, 0), p + Vector2(-16, -16), p + Vector2(0, -28), p + Vector2(16, -16), p + Vector2(16, 0), p + Vector2(-16, 0)], col, 2.0, sd)
			wline(p + Vector2(-6, 0), p + Vector2(-6, -9), col, 1.5, sd + 1)
			wline(p + Vector2(22, 0), p + Vector2(22, -22), col, 1.5, sd + 2)
			wcircle(p + Vector2(22, -24), 5, col, 1.5, sd)
		"shop":
			wpath([p + Vector2(-20, 0), p + Vector2(-20, -20), p + Vector2(20, -20), p + Vector2(20, 0), p + Vector2(-20, 0)], col, 2.0, sd)
			wline(p + Vector2(-22, -24), p + Vector2(22, -24), col, 3.0, sd + 1)
			wline(p + Vector2(-6, 0), p + Vector2(-6, -11), col, 1.5, sd + 2)
			wline(p + Vector2(6, 0), p + Vector2(6, -11), col, 1.5, sd + 3)
		"trailer":
			for k in 3:
				var q := p + Vector2(-26 + k * 18, -k * 3)
				wpath([q, q + Vector2(0, -10), q + Vector2(14, -10), q + Vector2(14, 0), q], col, 1.6, sd + k)
		"tower":
			wpath([p + Vector2(-10, 0), p + Vector2(0, -36), p + Vector2(10, 0)], col, 2.0, sd)
			wline(p + Vector2(-6, -12), p + Vector2(6, -12), col, 1.5, sd + 1)
			wline(p + Vector2(-3, -24), p + Vector2(3, -24), col, 1.5, sd + 2)
			wcircle(p + Vector2(0, -38), 3, col, 1.5, sd)
		"police":
			wpath([p + Vector2(-20, 0), p + Vector2(-20, -18), p + Vector2(20, -18), p + Vector2(20, 0), p + Vector2(-20, 0)], col, 2.0, sd)
			wpath([p + Vector2(-8, -18), p + Vector2(0, -28), p + Vector2(8, -18)], col, 2.0, sd + 1)
			wline(p + Vector2(0, -26), p + Vector2(0, -38), col, 1.5, sd + 2)
			wline(p + Vector2(0, -38), p + Vector2(9, -35), col, 1.5, sd + 3)
		"rail":
			wline(p + Vector2(-34, 0), p + Vector2(34, 0), col, 2.0, sd)
			wline(p + Vector2(-34, 5), p + Vector2(34, 5), col, 2.0, sd + 1)
			for k in 2:
				var q := p + Vector2(-26 + k * 26, -2)
				wpath([q, q + Vector2(0, -14), q + Vector2(22, -14), q + Vector2(22, 0)], col, 1.8, sd + k)
		"sos":
			# A log cabin with an aerial, and radio waves coming off it.
			wpath([p + Vector2(-14, 0), p + Vector2(-14, -14), p + Vector2(0, -24), p + Vector2(14, -14), p + Vector2(14, 0), p + Vector2(-14, 0)], col, 2.0, sd)
			wline(p + Vector2(-14, -7), p + Vector2(14, -7), col, 1.2, sd + 1)
			wline(p + Vector2(8, -18), p + Vector2(8, -40), col, 1.6, sd + 2)
			for k in 3:
				var r := 7.0 + k * 6.0
				wline(p + Vector2(8 + r * 0.7, -40 - r * 0.7), p + Vector2(8 + r, -40), RED, 1.5, sd + 3 + k)
				wline(p + Vector2(8 - r * 0.7, -40 - r * 0.7), p + Vector2(8 - r, -40), RED, 1.5, sd + 6 + k)
			if not main.game.looted.has(key):
				ink_text(p + Vector2(0, -60), "SOS", 22, RED)
		_:
			wpath([p + Vector2(-14, 0), p + Vector2(-14, -16), p + Vector2(0, -26), p + Vector2(14, -16), p + Vector2(14, 0), p + Vector2(-14, 0)], col, 2.0, sd)
	if on:
		wcircle(p + Vector2(0, -6), 48, RED, 2.2, sd)
	elif key == hover:
		wcircle(p + Vector2(0, -6), 44, FADED, 1.5, sd)
	ink_text(p + Vector2(0, 30), site["name"], 26, col)
	if main.game.looted.has(key):
		# Picked clean: a big scribbled cross over the place, and the name struck out.
		var w := font.get_string_size(site["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		wline(p + Vector2(-w * 0.5 - 4, 22), p + Vector2(w * 0.5 + 4, 20), RED, 2.4, sd + 7)
		wline(p + Vector2(-30, -40), p + Vector2(30, 14), RED, 3.6, sd + 8)
		wline(p + Vector2(30, -40), p + Vector2(-30, 14), RED, 3.6, sd + 9)
		ink_text(p + Vector2(0, 52), "picked clean", 22, RED)
		return
	var t := int(site["gone"])
	ink_text(p + Vector2(0, 52), "%d:%02d away · %s scrap" % [t / 60, t % 60, D.SCRAP_NAMES[site["scrap"]].to_lower()], 20, RED if on else FADED)


func site_at(pos: Vector2) -> String:
	var best := ""
	var bd := 60.0
	for key in D.SITE_KEYS:
		var d := pos.distance_to(site_px(key) + Vector2(0, -6))
		if d < bd:
			bd = d
			best = key
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := site_at(event.position)
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var k := site_at(event.position)
		if k != "":
			site_clicked.emit(k)
			accept_event()
