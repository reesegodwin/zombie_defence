# Draws the compound in isometric view straight from the simulation state.
# Everything is vector shapes drawn in _draw(), so there are no art files yet:
# swapping in sprites later only touches this script.
extends Node2D

const D = preload("res://scripts/defs.gd")

var g                                # the game (game.gd)
var ground := PackedInt32Array()     # 0 grass, 1 dirt, 2 concrete, 3 mud
var shade := PackedFloat32Array()
var deco: Array = []
var preview = null                   # {"x","y","ok","key"} while dragging a trap
var show_trap_zone := false
var hover_trap_uid := -1
var font: Font

const DECK_H := 10.0
const WALL_H := 26.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	_make_terrain(1337)


func _process(_dt: float) -> void:
	queue_redraw()


# --- Terrain ----------------------------------------------------------------
func _make_terrain(seed_val: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	var N := D.N
	ground.resize(N * N)
	shade.resize(N * N)
	for y in N:
		for x in N:
			var i := y * N + x
			shade[i] = r.randf()
			var lane := x >= D.X0 and x < D.X1
			if y > D.WALL_Y and lane:
				ground[i] = 2
			elif y == int(D.WALL_Y) and lane:
				ground[i] = 1
			elif lane:
				ground[i] = 1 if r.randf() < 0.5 else 3
			elif (x == D.X0 - 1 or x == D.X1) and r.randf() < 0.5:
				ground[i] = 1
			else:
				ground[i] = 0
	# Thick woods on both sides of the lane, so the only way in is the front.
	for y in N:
		for x in N:
			if x >= D.X0 and x < D.X1:
				continue
			if y == int(D.WALL_Y) and (x == D.X0 - 1 or x == D.X1):
				continue
			var near := x == D.X0 - 1 or x == D.X1 or x == D.X0 - 2 or x == D.X1 + 1
			var p := (0.85 if near else 0.5) if y <= D.WALL_Y else (0.45 if near else 0.35)
			if r.randf() < p:
				deco.append({"type": "tree", "x": x + 0.5 + (r.randf() - 0.5) * 0.3, "y": y + 0.5 + (r.randf() - 0.5) * 0.3, "s": 0.85 + r.randf() * 0.4, "v": r.randf()})
	deco.append({"type": "rock", "x": D.X0 - 1.0, "y": D.WALL_Y - 0.4, "s": 1.4})
	deco.append({"type": "rock", "x": float(D.X1), "y": D.WALL_Y - 0.4, "s": 1.4})
	deco.append({"type": "core", "x": 5.0, "y": 18.0, "s": 2.0})
	deco.append({"type": "hut", "x": 14.0, "y": 18.0, "s": 1.0})
	deco.append({"type": "hut", "x": 15.0, "y": 19.4, "s": 1.0})
	deco.append({"type": "crate", "x": 9.2, "y": 18.4, "s": 0.55})
	deco.append({"type": "crate", "x": 9.9, "y": 18.5, "s": 0.5})
	deco.append({"type": "crate", "x": 9.5, "y": 19.2, "s": 0.5})
	deco.append({"type": "barrel", "x": 12.2, "y": 19.4, "s": 1.0})
	deco.append({"type": "barrel", "x": 12.7, "y": 19.9, "s": 1.0})
	deco.append({"type": "barrel", "x": 8.3, "y": 20.3, "s": 1.0})
	deco.append({"type": "tent", "x": 10.2, "y": 20.6, "s": 1.0})


# --- Primitives -------------------------------------------------------------
static func P(gx: float, gy: float, h := 0.0) -> Vector2:
	return D.g2w(gx, gy) - Vector2(0, h)


func ellipse(c: Vector2, rx: float, ry: float, col: Color, segs := 18) -> void:
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * i / segs
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


# A ground circle of radius r tiles, as it looks in isometric view.
func ground_circle(gx: float, gy: float, r: float, col: Color) -> void:
	ellipse(P(gx, gy), r * D.TW * 0.7071, r * D.TH * 0.7071, col, 24)


func ground_ring(gx: float, gy: float, r: float, col: Color, w := 1.5) -> void:
	var pts := PackedVector2Array()
	var c := P(gx, gy)
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * r * D.TW * 0.7071, sin(a) * r * D.TH * 0.7071))
	draw_polyline(pts, col, w, true)


# An isometric box on the grid rectangle (x0,y0)-(x1,y1), from height b to h.
func box(x0: float, y0: float, x1: float, y1: float, h: float, top: Color, left: Color, right: Color, b := 0.0) -> void:
	draw_colored_polygon(PackedVector2Array([P(x0, y1, b), P(x1, y1, b), P(x1, y1, h), P(x0, y1, h)]), left)
	draw_colored_polygon(PackedVector2Array([P(x1, y0, b), P(x1, y1, b), P(x1, y1, h), P(x1, y0, h)]), right)
	draw_colored_polygon(PackedVector2Array([P(x0, y0, h), P(x1, y0, h), P(x1, y1, h), P(x0, y1, h)]), top)


func tile(x: int, y: int, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([P(x, y), P(x + 1, y), P(x + 1, y + 1), P(x, y + 1)]), col)


# --- Drawing ----------------------------------------------------------------
func _draw() -> void:
	if g == null:
		return
	_draw_ground()
	_draw_traps()
	_draw_fire_beds()

	# Things in front of the wall, sorted back to front.
	var front: Array = []
	var back: Array = []
	for d in deco:
		var item := {"k": d["x"] + d["y"], "kind": "deco", "o": d}
		if d["y"] < D.WALL_Y + 0.3:
			front.append(item)
		else:
			back.append(item)
	for z in g.zombies:
		front.append({"k": z["x"] + z["y"], "kind": "zombie", "o": z})
	front.sort_custom(func(a, b): return a["k"] < b["k"])
	for it in front:
		_draw_item(it)

	_draw_wall()
	_draw_deck()
	var crew_sorted: Array = g.crew.duplicate()
	crew_sorted.sort_custom(func(a, b): return a["x"] + a["y"] < b["x"] + b["y"])
	for s in crew_sorted:
		_draw_survivor(s)
	back.sort_custom(func(a, b): return a["k"] < b["k"])
	for it in back:
		_draw_item(it)

	_draw_night()
	_draw_lights()
	_draw_shots()
	_draw_parts()
	_draw_tracers()
	_draw_preview()
	_draw_texts()


func _draw_item(it: Dictionary) -> void:
	if it["kind"] == "zombie":
		_draw_zombie(it["o"])
		return
	var d: Dictionary = it["o"]
	match d["type"]:
		"tree": _draw_tree(d)
		"rock": _draw_rock(d)
		"core": _draw_core(d)
		"hut": _draw_hut(d)
		"crate":
			var s: float = d["s"] * 0.5
			box(d["x"] - s, d["y"] - s, d["x"] + s, d["y"] + s, 22.0 * d["s"], Color("9a7a4c"), Color("6d5434"), Color("826640"))
		"barrel": _draw_barrel(d)
		"tent": _draw_tent(d)


func _draw_ground() -> void:
	var N := D.N
	var pal := [
		[Color("3c5232"), Color("435a37")],  # grass
		[Color("5a4b36"), Color("63523b")],  # dirt
		[Color("5b5d5a"), Color("636560")],  # concrete
		[Color("4a3f30"), Color("514534")],  # mud
	]
	for y in N:
		for x in N:
			var i := y * N + x
			var p: Array = pal[ground[i]]
			tile(x, y, p[0].lerp(p[1], shade[i]))
	# Faint grid lines on the base floor.
	for x in range(D.X0, D.X1 + 1):
		draw_line(P(x, D.WALL_Y + 1), P(x, D.N), Color(0, 0, 0, 0.12), 1.0)
	if show_trap_zone:
		var b: Rect2 = g.trap_bounds()
		var pts := PackedVector2Array([P(b.position.x, b.position.y), P(b.end.x, b.position.y), P(b.end.x, b.end.y), P(b.position.x, b.end.y), P(b.position.x, b.position.y)])
		draw_colored_polygon(pts, Color(1, 0.85, 0.4, 0.06))
		draw_polyline(pts, Color(1, 0.85, 0.4, 0.55), 2.0)


func _draw_fire_beds() -> void:
	for f in g.fires:
		var a: float = clampf(f["life"] / 1.0, 0.0, 1.0)
		ground_circle(f["x"], f["y"], f["r"], Color(0.18, 0.08, 0.03, 0.55 * a))


func _draw_traps() -> void:
	for t in g.traps:
		var c := P(t["x"], t["y"])
		var hl: bool = t["uid"] == hover_trap_uid
		match t["key"]:
			"spikes":
				ground_circle(t["x"], t["y"], 0.6, Color(0.25, 0.22, 0.2, 0.8))
				for i in 9:
					var a := TAU * i / 9.0
					var q := c + Vector2(cos(a) * 22, sin(a) * 11)
					draw_colored_polygon(PackedVector2Array([q + Vector2(-3, 0), q + Vector2(3, 0), q + Vector2(0, -9)]), Color("a5a9ac"))
			"beartrap":
				ground_ring(t["x"], t["y"], 0.33, Color("8d9296"), 3.0)
				var shut: bool = t["hold"] >= 0
				for i in 8:
					var a := TAU * i / 8.0
					var q := c + Vector2(cos(a) * 14, sin(a) * 7) * (0.4 if shut else 1.0)
					draw_line(q, q + Vector2(0, -5), Color("c7cbce"), 2.0)
			"mine":
				ellipse(c, 12, 6, Color("2b2d2a"))
				ellipse(c - Vector2(0, 2), 9, 4.5, Color("3d403b"))
				if fmod(t["t"], 1.0) < 0.5:
					draw_circle(c - Vector2(0, 4), 2.0, Color("ff3b2f"))
			"slick":
				var a2: float = clampf(t["uses"] / 15.0, 0.25, 1.0)
				ground_circle(t["x"], t["y"], 0.9, Color(0.08, 0.07, 0.1, 0.75 * a2))
				ground_circle(t["x"] - 0.15, t["y"] - 0.15, 0.4, Color(0.4, 0.35, 0.55, 0.25 * a2))
		if hl:
			ground_ring(t["x"], t["y"], D.TRAP_R[t["key"]] + 0.12, Color(1, 0.9, 0.5, 0.9), 2.0)
		# Wear bar.
		var frac: float = clampf(t["uses"] / t["max"], 0.0, 1.0)
		if t["key"] != "mine":
			draw_rect(Rect2(c + Vector2(-12, 10), Vector2(24, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(c + Vector2(-12, 10), Vector2(24 * frac, 3)), Color("e0b44a"))


func _draw_tree(d: Dictionary) -> void:
	var c := P(d["x"], d["y"])
	var s: float = d["s"]
	ellipse(c + Vector2(4, 2), 20 * s, 9 * s, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(c + Vector2(-3 * s, -16 * s), Vector2(6 * s, 16 * s)), Color("4a3524"))
	var v: float = d.get("v", 0.5)
	var dark := Color("1f3a24").lerp(Color("2a4528"), v)
	var mid := Color("2d5232").lerp(Color("3a5e33"), v)
	var lite := Color("3f6b3d").lerp(Color("527a42"), v)
	for k in 3:
		var w := (24.0 - k * 6.0) * s
		var y0 := (-12.0 - k * 13.0) * s
		var col: Color = [dark, mid, lite][k]
		draw_colored_polygon(PackedVector2Array([c + Vector2(-w, y0), c + Vector2(w, y0), c + Vector2(0, y0 - 24 * s)]), col)


func _draw_rock(d: Dictionary) -> void:
	var c := P(d["x"], d["y"])
	var s: float = d["s"]
	ellipse(c + Vector2(0, 4), 30 * s, 12 * s, Color(0, 0, 0, 0.3))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-28, 4) * s, c + Vector2(-20, -18) * s, c + Vector2(-2, -30) * s, c + Vector2(18, -22) * s, c + Vector2(28, 2) * s, c + Vector2(4, 10) * s]), Color("6a6a64"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -18) * s, c + Vector2(-2, -30) * s, c + Vector2(18, -22) * s, c + Vector2(2, -12) * s]), Color("8a8a82"))


func _draw_core(d: Dictionary) -> void:
	var x: float = d["x"]
	var y: float = d["y"]
	box(x - 1.3, y - 1.1, x + 1.3, y + 1.1, 44, Color("6c7268"), Color("464b44"), Color("575d55"))
	box(x - 0.5, y - 0.4, x + 0.5, y + 0.4, 58, Color("7d8478"), Color("50564d"), Color("5e655b"), 44)
	var top := P(x, y, 58)
	draw_line(top, top - Vector2(0, 30), Color("2a2a2a"), 2.0)
	var blink: bool = fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.2
	draw_circle(top - Vector2(0, 30), 3.0, Color("ff4a3a") if blink else Color("6a2a22"))
	# Door.
	draw_colored_polygon(PackedVector2Array([P(x - 0.3, y + 1.1), P(x + 0.3, y + 1.1), P(x + 0.3, y + 1.1, 22), P(x - 0.3, y + 1.1, 22)]), Color("2a2c28"))


func _draw_hut(d: Dictionary) -> void:
	var x: float = d["x"]
	var y: float = d["y"]
	box(x - 0.7, y - 0.55, x + 0.7, y + 0.55, 24, Color("6d5a3f"), Color("564630"), Color("665238"))
	# Pitched roof along x.
	var a := P(x - 0.8, y - 0.65, 24)
	var b := P(x + 0.8, y - 0.65, 24)
	var c2 := P(x + 0.8, y + 0.65, 24)
	var d2 := P(x - 0.8, y + 0.65, 24)
	var ra := P(x - 0.8, y, 40)
	var rb := P(x + 0.8, y, 40)
	draw_colored_polygon(PackedVector2Array([a, b, rb, ra]), Color("5a3a2a"))
	draw_colored_polygon(PackedVector2Array([ra, rb, c2, d2]), Color("7a4c34"))
	draw_colored_polygon(PackedVector2Array([rb, b, c2]), Color("4a3122"))


func _draw_barrel(d: Dictionary) -> void:
	var c := P(d["x"], d["y"])
	ellipse(c, 8, 4, Color("2b3a30"))
	draw_rect(Rect2(c + Vector2(-8, -18), Vector2(16, 18)), Color("3e5546"))
	ellipse(c - Vector2(0, 18), 8, 4, Color("4f6b58"))
	draw_line(c + Vector2(-8, -6), c + Vector2(8, -6), Color("2b3a30"), 1.5)


func _draw_tent(d: Dictionary) -> void:
	var x: float = d["x"]
	var y: float = d["y"]
	var a := P(x - 0.8, y + 0.5)
	var b := P(x + 0.8, y + 0.5)
	var c2 := P(x + 0.8, y - 0.5)
	var top_b := P(x + 0.8, y, 26)
	var top_a := P(x - 0.8, y, 26)
	draw_colored_polygon(PackedVector2Array([a, b, top_b, top_a]), Color("6b6b4a"))
	draw_colored_polygon(PackedVector2Array([b, c2, top_b]), Color("54543a"))


func _draw_wall() -> void:
	var mat: Dictionary = g.wall_mat()
	var frac: float = g.wall["hp"] / g.wall["max_hp"]
	var dim := 0.55 + 0.45 * frac
	var y0 := D.WALL_Y
	var y1 := D.WALL_Y + D.WALL_T
	for i in range(D.X1 - D.X0):
		var x := float(D.X0 + i)
		var hurt: float = g.wall["hurt"][i]
		var top: Color = mat["top"] * dim
		var left: Color = mat["left"] * dim
		var right: Color = mat["right"] * dim
		top.a = 1; left.a = 1; right.a = 1
		if hurt > 0:
			var k := hurt / 0.15 * 0.5
			top = top.lerp(Color.WHITE, k); left = left.lerp(Color.WHITE, k); right = right.lerp(Color.WHITE, k)
		var h := WALL_H
		if g.over:
			h = WALL_H * (0.25 + 0.3 * fmod(i * 0.37, 1.0))
		box(x, y0, x + 1, y1, h, top, left, right)
		# Crenellations.
		if not g.over:
			box(x + 0.1, y0 + 0.05, x + 0.45, y1 - 0.05, h + 7, top, left, right, h)
			box(x + 0.6, y0 + 0.05, x + 0.95, y1 - 0.05, h + 7, top, left, right, h)
		# Plank or block lines on the face.
		var lc := Color(0, 0, 0, 0.18)
		draw_line(P(x, y1, h * 0.33), P(x + 1, y1, h * 0.33), lc, 1.0)
		draw_line(P(x, y1, h * 0.66), P(x + 1, y1, h * 0.66), lc, 1.0)
		# Cracks as the wall weakens.
		if frac < 0.66 and not g.over:
			var cc := Color(0.05, 0.04, 0.03, 0.75)
			var bx := x + 0.3 + fmod(i * 0.61, 0.4)
			draw_polyline(PackedVector2Array([P(bx, y1, h * 0.9), P(bx + 0.1, y1, h * 0.6), P(bx - 0.05, y1, h * 0.4), P(bx + 0.12, y1, h * 0.15)]), cc, 1.5)
			if frac < 0.33:
				var bx2 := x + 0.75
				draw_polyline(PackedVector2Array([P(bx2, y1, h * 0.75), P(bx2 - 0.12, y1, h * 0.5), P(bx2 + 0.05, y1, h * 0.2)]), cc, 1.5)
	# Barbed wire strung along the outside.
	var wire: float = g.mods["wire"]
	if wire > 0:
		var rows := int(ceil(wire / 8.0))
		for r in rows:
			var pts := PackedVector2Array()
			var yy := y0 - 0.12 - r * 0.12
			var steps := (D.X1 - D.X0) * 4
			for k in steps + 1:
				var xx := D.X0 + 0.05 + k * 0.25 * 0.993
				pts.append(P(xx, yy, 5.0 + r * 5.0 + (3.0 if k % 2 == 0 else -1.0)))
			draw_polyline(pts, Color("9aa0a3"), 1.2)


func _draw_deck() -> void:
	box(D.X0, D.WALL_Y + D.WALL_T, D.X1, D.WALK_Y + 0.7, DECK_H, Color("7a6040"), Color("4f3d28"), Color("604b31"))
	for x in range(D.X0, D.X1 + 1):
		draw_line(P(x, D.WALL_Y + D.WALL_T, DECK_H), P(x, D.WALK_Y + 0.7, DECK_H), Color(0, 0, 0, 0.18), 1.0)


func _screen_dir(ang: float) -> Vector2:
	return D.g2w(cos(ang), sin(ang)).normalized()


func _draw_survivor(s: Dictionary) -> void:
	var feet := P(s["x"], s["y"], DECK_H)
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	var dir := _screen_dir(s["aim"])
	ellipse(feet + Vector2(0, 1), 9, 4.5, Color(0, 0, 0, 0.35))
	if s["is_player"]:
		var pts := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(feet + Vector2(cos(a) * 13, sin(a) * 6.5))
		draw_polyline(pts, Color(0.55, 0.85, 1.0, 0.8), 1.5)
	var recoil: float = s["recoil"] * 18.0
	var body := feet - dir * recoil * 0.2
	# Legs.
	draw_line(body + Vector2(-3, -9), body + Vector2(-3, 0), Color("2b2f33"), 3.0)
	draw_line(body + Vector2(3, -9), body + Vector2(3, 0), Color("2b2f33"), 3.0)
	# Torso.
	draw_rect(Rect2(body + Vector2(-6, -21), Vector2(12, 13)), s["jacket"])
	# Head.
	draw_circle(body + Vector2(0, -25), 4.6, s["skin"])
	draw_arc(body + Vector2(0, -26), 4.8, PI, TAU, 8, Color("2e2620"), 2.5)
	# Gun.
	var shoulder := body + Vector2(0, -17)
	var muzzle: Vector2 = shoulder + dir * (w["len"] - recoil)
	var wide := 3.0 if s["weapon"] in ["shotgun", "launcher"] else 2.4
	draw_line(shoulder, muzzle, Color("1d1f21"), wide)
	draw_line(shoulder + Vector2(0, 2), shoulder + dir * 6, s["skin"], 2.5)
	s["_muzzle"] = muzzle
	# Name.
	var label: String = s["name"]
	draw_string(font, body + Vector2(-30, 12), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 10, Color(1, 1, 1, 0.7))


func _draw_zombie(z: Dictionary) -> void:
	var T: Dictionary = D.ZTYPES[z["type"]]
	var sc: float = T["scale"]
	var feet := P(z["x"], z["y"])
	var t: float = z["t"]
	var walking: bool = z["atk"] <= 0 and z["held"] <= 0
	var bob := sin(t * 6.0) * 1.2 if walking else 0.0
	ellipse(feet + Vector2(0, 1), 8 * sc, 4 * sc, Color(0, 0, 0, 0.35))
	var skin: Color = T["skin"]
	var shirt: Color = T["shirts"][z["shirt"]]
	if z["hit"] > 0:
		skin = skin.lerp(Color.WHITE, 0.7)
		shirt = shirt.lerp(Color.WHITE, 0.7)
	elif z["burn"] > 0:
		skin = skin.lerp(Color("ff8a2a"), 0.35)
		shirt = shirt.lerp(Color("ff8a2a"), 0.25)
	var pants := Color("2c2a27")
	# Legs shuffle.
	var step := sin(t * 6.0) * 3.0 * sc if walking else 0.0
	draw_line(feet + Vector2(-3 * sc + step, -9 * sc), feet + Vector2(-3 * sc + step * 0.5, 0), pants, 3.0 * sc)
	draw_line(feet + Vector2(3 * sc - step, -9 * sc), feet + Vector2(3 * sc - step * 0.5, 0), pants, 3.0 * sc)
	var b := feet + Vector2(0, bob)
	# Hunched torso leaning toward the wall (down-left on screen).
	var lean := Vector2(-2, 0) * sc
	draw_colored_polygon(PackedVector2Array([b + Vector2(-6, -8) * sc, b + Vector2(6, -8) * sc, b + Vector2(5, -21) * sc + lean, b + Vector2(-7, -21) * sc + lean]), shirt)
	# Arms reach forward; swing when clawing.
	var reach := Vector2(-11, 5) * sc
	if z["atk"] > 0:
		reach = Vector2(-13, 9) * sc
	var sh := b + Vector2(-4, -18) * sc + lean
	draw_line(sh, sh + reach, skin, 2.5 * sc)
	draw_line(sh + Vector2(6, 1) * sc, sh + Vector2(6, 1) * sc + reach + Vector2(2, -2) * sc, skin, 2.5 * sc)
	# Head.
	var head := b + Vector2(-2, -25) * sc + lean
	draw_circle(head, 4.5 * sc, skin)
	draw_circle(head + Vector2(-2, -0.5) * sc, 1.0 * sc, Color("e8e05a") if z["type"] == "runner" else Color("2a1a14"))
	# Health bar once hurt.
	if z["hp"] < z["max_hp"]:
		var frac: float = clampf(z["hp"] / z["max_hp"], 0.0, 1.0)
		var top := head - Vector2(9 * sc, 9 * sc)
		draw_rect(Rect2(top, Vector2(18 * sc, 2.5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(18 * sc * frac, 2.5)), Color("d24a3a"))


func _draw_night() -> void:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var vr := get_viewport_rect()
	var r := Rect2(inv * vr.position, Vector2.ZERO).expand(inv * vr.end)
	draw_rect(r.grow(50), Color(0.02, 0.03, 0.09, g.dark))


func _draw_lights() -> void:
	# Fires and the bunker light glow through the dark.
	for f in g.fires:
		var a: float = clampf(f["life"], 0.0, 1.0)
		for k in 3:
			ground_circle(f["x"], f["y"], f["r"] * (1.4 - k * 0.35), Color(1.0, 0.55, 0.15, 0.08 * a))
	# Lanterns along the deck.
	for x in [D.X0 + 0.5, (D.X0 + D.X1) / 2.0, D.X1 - 0.5]:
		var c := P(x, D.WALL_Y + D.WALL_T + 0.3, DECK_H)
		ellipse(c, 70, 35, Color(1.0, 0.8, 0.45, 0.05 * g.dark / 0.58))
		draw_circle(c - Vector2(0, 30), 2.5, Color(1.0, 0.85, 0.5, 0.9))
	for s in g.crew:
		if s["flash"] > 0 and s.has("_muzzle"):
			var m: Vector2 = s["_muzzle"]
			draw_circle(m, 6.0, Color(1.0, 0.85, 0.4, 0.9))
			draw_circle(m, 14.0, Color(1.0, 0.7, 0.3, 0.2))


func _draw_shots() -> void:
	for sh in g.shots:
		var k: float = clampf(sh["t"] / sh["dur"], 0.0, 1.0)
		var gx: float = lerpf(sh["x0"], sh["x1"], k)
		var gy: float = lerpf(sh["y0"], sh["y1"], k)
		var h := 29.0 * (1.0 - k) + sin(k * PI) * 60.0
		var c := P(gx, gy, h)
		ellipse(P(gx, gy), 4, 2, Color(0, 0, 0, 0.3))
		if sh["kind"] == "grenade":
			draw_circle(c, 3.5, Color("3a4a2a"))
		else:
			draw_circle(c, 3.5, Color("6a8a5a"))
			draw_circle(c - Vector2(0, 4), 2.5, Color("ffb347"))


func _draw_parts() -> void:
	for p in g.parts:
		var c := P(p["x"], p["y"], p["z"])
		var col: Color = p["color"]
		var a: float = clampf(p["life"] / p["max"] * 1.5, 0.0, 1.0)
		col.a = a
		var s: float = p["size"]
		draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), col)


func _draw_tracers() -> void:
	for t in g.tracers:
		var a := P(t["x1"], t["y1"], t["h1"])
		var b := P(t["x2"], t["y2"], t["h2"])
		draw_line(a, b, Color(1.0, 0.92, 0.6, clampf(t["life"] / 0.07, 0.0, 1.0)), t["w"])


func _draw_preview() -> void:
	if preview == null:
		return
	var col := Color(0.4, 1.0, 0.5, 0.35) if preview["ok"] else Color(1.0, 0.3, 0.25, 0.35)
	ground_circle(preview["x"], preview["y"], D.TRAP_R[preview["key"]], col)
	ground_ring(preview["x"], preview["y"], D.TRAP_R[preview["key"]], Color(col, 0.9), 2.0)


func _draw_texts() -> void:
	for t in g.texts:
		var k: float = 1.0 - t["life"] / t["max"]
		var c := P(t["x"], t["y"], 30 + k * 30)
		var col: Color = t["color"]
		col.a = clampf(t["life"] / t["max"] * 2.0, 0.0, 1.0)
		draw_string(font, c + Vector2(-60, 0), t["txt"], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, col)
