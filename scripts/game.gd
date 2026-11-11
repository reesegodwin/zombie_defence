# The whole simulation: wall, zombies, crew, weapons, traps, inventory,
# experience and upgrade cards, and the director that keeps raising the pressure.
# It has no nodes, so it can be run headlessly by the tests.
extends RefCounted

const D = preload("res://scripts/defs.gd")

signal toast(text: String, kind: String)
signal sound(name: String)
signal inv_changed
signal leveled_up
signal exploded(x: float, y: float, radius: float)
signal zombie_died(x: float, y: float, type: String)
signal wall_breached(x: float)

# --- State ------------------------------------------------------------------
var time := 0.0
var threat := 1
var wall := {}
var zombies: Array = []
var crew: Array = []
var shots: Array = []
var fires: Array = []
var parts: Array = []
var tracers: Array = []
var texts: Array = []
var traps: Array = []
var storage := {"cap": 8, "items": []}
var mods := {"crew_dmg": 1.0, "crew_rate": 1.0, "wire": 0.0}
var xp := 0
var level := 1
var xp_next := 0
var pending_levels := 0
var cards: Array = []          # non-empty while a level-up choice is open
var picks: Array = []
var kills := 0
var dark := 0.12
var over := false
var seen := {}
var zid := 1
var uid := 1
var spawn_acc := 0.0
var next_horde := D.HORDE_EVERY
var horde_left := 0
var horde_acc := 0.0
var shake := 0.0
var fx_id := 1                 # ids for fires, so the 3D view can track them

# Player input, written by main.gd each frame (grid coordinates).
var input_aim = null           # Vector2 or null
var input_firing := false
var input_auto := false


func _init() -> void:
	wall = {"hp": 500.0, "max_hp": 500.0, "stage": 0, "hurt": []}
	for i in D.X1 - D.X0:
		wall["hurt"].append(0.0)
	xp_next = xp_need(1)
	add_survivor("You", "pistol", true)


# --- Helpers ----------------------------------------------------------------
static func xp_need(lv: int) -> int:
	return int(round(4 + lv * 3 + lv * lv * 0.4))


func wall_mat() -> Dictionary:
	var s: int = wall["stage"]
	var i := 0 if s == 0 else (1 if s <= 2 else 2)
	return D.WALL_MATS[i]


func storage_free() -> int:
	return int(storage["cap"]) - storage["items"].size()


func _changed() -> void:
	inv_changed.emit()


func new_item(key: String, uses = null) -> Dictionary:
	var it := {"uid": uid, "key": key}
	uid += 1
	if D.ITEMS[key].has("uses"):
		it["uses"] = float(D.ITEMS[key]["uses"]) if uses == null else float(uses)
	return it


# --- Crew -------------------------------------------------------------------
func add_survivor(sname: String, weapon: String, is_player: bool) -> void:
	var i := crew.size()
	crew.append({
		"name": sname, "weapon": weapon, "is_player": is_player, "gear": [null, null], "mol_cd": 0.0,
		"x": 0.0, "y": 0.0, "cd": 0.3 + randf() * 0.3, "aim": -PI * 0.75, "flash": 0.0, "recoil": 0.0,
		"jacket": Color("3e5a6e") if is_player else D.JACKETS[i % D.JACKETS.size()],
		"skin": Color("d9a77f") if is_player else D.SKINS[(i * 3) % D.SKINS.size()],
	})
	layout_crew()


func layout_crew() -> void:
	var mid := (D.X0 + D.X1) / 2.0
	for i in crew.size():
		var s: Dictionary = crew[i]
		s["x"] = clampf(mid + D.CREW_SLOTS[i], D.X0 + 0.6, D.X1 - 0.6)
		s["y"] = D.WALK_Y


func free_name() -> String:
	var used := {}
	for s in crew:
		used[s["name"]] = true
	var pool: Array = []
	for n in D.NAMES:
		if not used.has(n):
			pool.append(n)
	return pool.pick_random() if pool.size() > 0 else "Sam"


# A survivor's effective numbers, from their role and the gear they carry.
func survivor_stats(s: Dictionary) -> Dictionary:
	var dmg: float = 1.0 if s["is_player"] else mods["crew_dmg"]
	var rate: float = 1.0 if s["is_player"] else 1.15 * mods["crew_rate"]
	var crates := 0
	var hollow := 0
	for g in s["gear"]:
		if g == null:
			continue
		match g["key"]:
			"hollow": hollow += 1
			"trigger": rate *= 0.85
			"molotov": crates += 1
	dmg *= 1.0 + 0.25 * hollow
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	var per_shot: float = w["dmg"] * w["pellets"] * dmg
	return {
		"dmg": dmg, "rate": rate, "interval": w["rate"] * rate,
		"dps": int(round(per_shot / (w["rate"] * rate))),
		"molotov_every": 10.0 * pow(0.8, crates - 1) if crates > 0 else 0.0,
	}


# --- Zombies ----------------------------------------------------------------
func spawn_zombie(type: String, hp_mul: float, spd_mul: float) -> Dictionary:
	var T: Dictionary = ZT(type)
	var hp := roundf(T["hp"] * hp_mul)
	var z := {
		"id": zid, "type": type,
		"x": D.X0 + 0.4 + randf() * (D.X1 - D.X0 - 0.8), "y": 0.15 + randf() * 0.5,
		"hp": hp, "max_hp": hp, "spd": spd_mul * (0.9 + randf() * 0.2),
		"cd": randf() * T["rate"], "t": randf() * 10.0, "sway": randf() * TAU,
		"burn": 0.0, "hit": 0.0, "atk": 0.0, "held": 0.0, "slow": 1.0,
		"shirt": randi() % T["shirts"].size(), "groan": 2.0 + randf() * 10.0,
	}
	zid += 1
	zombies.append(z)
	return z


static func ZT(type: String) -> Dictionary:
	return D.ZTYPES[type]


func hit_wall(x: float, dmg: float) -> void:
	if over:
		return
	wall["hp"] -= dmg
	var seg := clampi(int(floor(x)) - D.X0, 0, wall["hurt"].size() - 1)
	wall["hurt"][seg] = 0.15
	burst(x, D.WALL_Y - 0.05, 3, {"colors": wall_mat()["chips"], "spread": 1.0, "up": 90.0, "life": 0.45, "size": 2.2, "z": 16.0})
	sound.emit("hit")
	if wall["hp"] <= 0:
		wall["hp"] = 0.0
		over = true
		shake = 1.0
		for k in 6:
			burst(x + (randf() - 0.5) * 3.0, D.WALL_Y, 12, {"colors": wall_mat()["chips"], "spread": 3.0, "up": 180.0, "life": 1.0, "size": 4.0, "z": 18.0})
		sound.emit("crash")
		wall_breached.emit(x)


func update_zombies(dt: float) -> void:
	var wire: float = mods["wire"]
	for z in zombies:
		if z["hp"] <= 0:
			continue
		var T := ZT(z["type"])
		z["t"] += dt
		z["hit"] = maxf(0.0, z["hit"] - dt)
		z["atk"] = maxf(0.0, z["atk"] - dt)
		if z["burn"] > 0:
			z["burn"] -= dt
			damage(z, 10.0 * dt, true)
			if randf() < dt * 12.0:
				burst(z["x"], z["y"], 1, {"colors": [Color("ffcf5a"), Color("ff8a2a")], "spread": 0.3, "up": 40.0, "life": 0.45, "size": 2.6, "z": 20.0 * T["scale"], "grav": -60.0, "glow": true})
			if z["hp"] <= 0:
				continue
		z["groan"] -= dt
		if z["groan"] <= 0:
			z["groan"] = 8.0 + randf() * 14.0
			sound.emit("groan")

		var front: float = D.WALL_Y - T["r"]
		if z["held"] > 0:
			z["held"] -= dt  # caught in a bear trap
		elif z["y"] < front - 0.01:
			var slow: float = z["slow"]
			z["x"] += sin(z["t"] * 0.8 + z["sway"]) * 0.18 * dt * slow
			z["y"] = minf(front, z["y"] + T["speed"] * z["spd"] * slow * dt)
		else:
			z["y"] = front
			z["cd"] -= dt
			if z["cd"] <= 0:
				z["cd"] = T["rate"]
				z["atk"] = 0.25
				hit_wall(z["x"], T["dmg"])
			if wire > 0:
				damage(z, wire * dt, true)

	# Separation so the crowd piles up along the wall instead of stacking.
	var n := zombies.size()
	for i in n:
		var a: Dictionary = zombies[i]
		var ra: float = ZT(a["type"])["r"]
		for j in range(i + 1, n):
			var b: Dictionary = zombies[j]
			var dx: float = b["x"] - a["x"]
			var dy: float = b["y"] - a["y"]
			var mn: float = (ra + ZT(b["type"])["r"]) * 1.1
			var d2 := dx * dx + dy * dy
			if d2 < mn * mn and d2 > 1e-6:
				var d := sqrt(d2)
				var push := (mn - d) * 0.5
				var ux := dx / d * push
				var uy := dy / d * push
				a["x"] -= ux; a["y"] -= uy
				b["x"] += ux; b["y"] += uy
	for z in zombies:
		var r: float = ZT(z["type"])["r"]
		z["x"] = clampf(z["x"], D.X0 + r, D.X1 - r)
		z["y"] = minf(z["y"], D.WALL_Y - r)
	zombies = zombies.filter(func(z): return z["hp"] > 0)


func damage(z: Dictionary, amt: float, quiet := false) -> void:
	if z["hp"] <= 0:
		return
	z["hp"] -= amt
	if not quiet:
		z["hit"] = 0.08
	if z["hp"] <= 0:
		var T := ZT(z["type"])
		xp += int(T["xp"])
		kills += 1
		zombie_died.emit(z["x"], z["y"], z["type"])
		burst(z["x"], z["y"], 10 + int(round(T["scale"] * 6)), {"colors": [Color("5a2a26"), Color("7a3a2c"), T["skin"]], "spread": 2.2, "up": 130.0, "life": 0.8, "size": 2.6 * T["scale"], "z": 14.0 * T["scale"]})
		sound.emit("die")


# --- Weapons ----------------------------------------------------------------
# Closest-to-the-wall target in range: the most urgent threat.
func auto_target(s: Dictionary, rng: float) -> Variant:
	var best = null
	var by := -INF
	for z in zombies:
		if z["hp"] <= 0:
			continue
		var d2: float = pow(z["x"] - s["x"], 2) + pow(z["y"] - s["y"], 2)
		if d2 > rng * rng:
			continue
		var score: float = z["y"] + (1.5 if z["type"] == "brute" else 0.0)
		if score > by:
			by = score
			best = z
	return best


const MUZZLE_H := 29.0  # pixels above the ground: walkway plus shoulder height


func fire(s: Dictionary, tx: float, ty: float, dmg_mul: float) -> void:
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	var ang := atan2(ty - s["y"], tx - s["x"])
	s["aim"] = ang
	s["flash"] = 0.06
	s["recoil"] = 0.1
	sound.emit(w["sound"])
	if w.has("splash"):
		var d := minf(w["range"], Vector2(tx - s["x"], ty - s["y"]).length())
		shots.append({"kind": "grenade", "x0": s["x"], "y0": s["y"], "x1": s["x"] + cos(ang) * d, "y1": s["y"] + sin(ang) * d,
			"t": 0.0, "dur": 0.25 + d / 12.0, "dmg": w["dmg"] * dmg_mul, "splash": w["splash"]})
		return
	for p in int(w["pellets"]):
		var a: float = ang + (randf() * 2.0 - 1.0) * w["spread"]
		var dx := cos(a)
		var dy := sin(a)
		var hits: Array = []
		for z in zombies:
			if z["hp"] <= 0:
				continue
			var rx: float = z["x"] - s["x"]
			var ry: float = z["y"] - s["y"]
			var t := rx * dx + ry * dy
			if t <= 0 or t > w["range"]:
				continue
			if absf(rx * dy - ry * dx) < ZT(z["type"])["r"] + 0.1:
				hits.append([t, z])
		hits.sort_custom(func(a1, b1): return a1[0] < b1[0])
		var hit := hits.slice(0, int(w["pierce"]))
		for h in hit:
			var z: Dictionary = h[1]
			damage(z, w["dmg"] * dmg_mul)
			if z["type"] != "brute":
				z["y"] = maxf(0.0, z["y"] - w["knock"])
			burst(z["x"], z["y"], 2, {"colors": [Color("6a2a22"), Color("8a3a2c")], "spread": 1.0, "up": 60.0, "life": 0.35, "size": 2.0, "z": 16.0})
		var ln: float = hit[-1][0] if hit.size() > 0 else w["range"]
		var h2: float = 17.0 * ZT(hit[-1][1]["type"])["scale"] if hit.size() > 0 else 0.0
		tracers.append({"x1": s["x"], "y1": s["y"], "h1": MUZZLE_H, "x2": s["x"] + dx * ln, "y2": s["y"] + dy * ln, "h2": h2,
			"life": 0.07, "w": 1.0 if w["pellets"] > 1 else (2.4 if s["weapon"] == "rifle" else 1.6)})


func update_crew(dt: float) -> void:
	for s in crew:
		s["cd"] -= dt
		s["flash"] = maxf(0.0, s["flash"] - dt)
		s["recoil"] = maxf(0.0, s["recoil"] - dt)
		var w: Dictionary = D.WEAPONS[s["weapon"]]
		var k := survivor_stats(s)

		# Firebombs: carried molotov crates are thrown at the thickest crowd.
		if k["molotov_every"] > 0:
			s["mol_cd"] -= dt
			if s["mol_cd"] <= 0:
				var target = crowd_centre()
				if target != null:
					s["mol_cd"] = k["molotov_every"]
					var d := Vector2(target["x"] - s["x"], target["y"] - s["y"]).length()
					shots.append({"kind": "molotov", "x0": s["x"], "y0": s["y"], "x1": target["x"], "y1": target["y"], "t": 0.0, "dur": 0.35 + d / 14.0})
					sound.emit("launch")
				else:
					s["mol_cd"] = 1.0

		if s["is_player"]:
			if input_aim != null:
				s["aim"] = atan2(input_aim.y - s["y"], input_aim.x - s["x"])
			if s["cd"] > 0:
				continue
			if input_firing and input_aim != null:
				fire(s, input_aim.x, input_aim.y, k["dmg"])
				s["cd"] = k["interval"]
			elif input_auto:
				var z = auto_target(s, w["range"])
				if z != null:
					fire(s, z["x"], z["y"], k["dmg"])
					s["cd"] = k["interval"]
		else:
			var z = auto_target(s, w["range"])
			if z == null:
				continue
			s["aim"] = atan2(z["y"] - s["y"], z["x"] - s["x"])
			if s["cd"] <= 0:
				fire(s, z["x"], z["y"], k["dmg"])
				s["cd"] = k["interval"]


func crowd_centre() -> Variant:
	var best = null
	var bn := 0.0
	for z in zombies:
		if z["y"] < 4:
			continue
		var n := 0.0
		for o in zombies:
			if pow(o["x"] - z["x"], 2) + pow(o["y"] - z["y"], 2) < 2.2:
				n += 1.0
		n += z["y"] / 20.0
		if n > bn:
			bn = n
			best = z
	return best


func update_shots(dt: float) -> void:
	for sh in shots:
		sh["t"] += dt
		if sh["t"] < sh["dur"]:
			continue
		sh["done"] = true
		if sh["kind"] == "grenade":
			explode(sh["x1"], sh["y1"], sh["dmg"], sh["splash"])
		else:
			_add_fire(sh["x1"], sh["y1"], 1.35, 4.5)
			sound.emit("fire")
	shots = shots.filter(func(s): return not s.has("done"))

	for f in fires:
		f["life"] -= dt
		for z in zombies:
			if pow(z["x"] - f["x"], 2) + pow(z["y"] - f["y"], 2) < f["r"] * f["r"]:
				damage(z, 20.0 * dt, true)
				z["burn"] = 1.4
		if randf() < dt * 30.0:
			var a := randf() * TAU
			var rr: float = sqrt(randf()) * f["r"]
			parts.append({"x": f["x"] + cos(a) * rr, "y": f["y"] + sin(a) * rr, "z": 2.0, "vx": 0.0, "vy": 0.0, "vz": 30.0 + randf() * 30.0,
				"life": 0.6, "max": 0.6, "color": [Color("ffe08a"), Color("ffb347"), Color("ff7a2a")].pick_random(),
				"size": 3.0 + randf() * 3.0, "grav": -40.0, "glow": true})
	fires = fires.filter(func(f): return f["life"] > 0)


func _add_fire(x: float, y: float, r: float, life: float) -> void:
	fires.append({"id": fx_id, "x": x, "y": y, "r": r, "life": life, "max": life})
	fx_id += 1


func explode(x: float, y: float, dmg: float, splash: float) -> void:
	for z in zombies:
		var d := Vector2(z["x"] - x, z["y"] - y).length()
		if d < splash:
			damage(z, dmg * (1.0 - d / splash * 0.5))
			if z["type"] != "brute":
				z["y"] = maxf(0.0, z["y"] - 0.3 * (1.0 - d / splash))
	burst(x, y, 26, {"colors": [Color("ffe08a"), Color("ffb347"), Color("ff7a2a"), Color("3a3530")], "spread": 3.2, "up": 200.0, "life": 0.6, "size": 4.0, "z": 6.0, "glow": true})
	burst(x, y, 10, {"colors": [Color("2e2a26"), Color("4a443d")], "spread": 2.0, "up": 120.0, "life": 1.0, "size": 5.0, "z": 6.0, "grav": -20.0})
	sound.emit("boom")
	exploded.emit(x, y, splash)
	shake = maxf(shake, 0.35)
	ignite_slicks(x, y, splash)


# --- Particles and effects --------------------------------------------------
func burst(x: float, y: float, n: int, o: Dictionary) -> void:
	var colors: Array = o["colors"]
	for i in n:
		var a := randf() * TAU
		var sp: float = o.get("spread", 1.0) * (0.3 + randf() * 0.7)
		var life: float = o.get("life", 0.6) * (0.6 + randf() * 0.6)
		parts.append({
			"x": x, "y": y, "z": o.get("z", 8.0),
			"vx": cos(a) * sp, "vy": sin(a) * sp, "vz": o.get("up", 80.0) * (0.5 + randf()),
			"life": life, "max": life, "color": colors.pick_random(),
			"size": o.get("size", 2.5) * (0.6 + randf() * 0.8),
			"grav": o.get("grav", 320.0), "glow": o.get("glow", false),
		})
	if parts.size() > 900:
		parts = parts.slice(parts.size() - 900)


func float_text(x: float, y: float, txt: String, color: Color, life := 1.2) -> void:
	texts.append({"x": x, "y": y, "txt": txt, "color": color, "life": life, "max": life})


func update_parts(dt: float) -> void:
	for p in parts:
		p["x"] += p["vx"] * dt
		p["y"] += p["vy"] * dt
		p["vz"] -= p["grav"] * dt
		p["z"] += p["vz"] * dt
		if p["z"] < 0:
			p["z"] = 0.0
			p["vz"] *= -0.3
			p["vx"] *= 0.5
			p["vy"] *= 0.5
		p["life"] -= dt
	parts = parts.filter(func(p): return p["life"] > 0)
	for t in tracers:
		t["life"] -= dt
	tracers = tracers.filter(func(t): return t["life"] > 0)
	for t in texts:
		t["life"] -= dt
	texts = texts.filter(func(t): return t["life"] > 0)
	var hurt: Array = wall["hurt"]
	for i in hurt.size():
		hurt[i] = maxf(0.0, hurt[i] - dt)
	shake = maxf(0.0, shake - dt * 2.5)


# --- Traps ------------------------------------------------------------------
const TRAP_GAP := 0.9


static func trap_bounds() -> Rect2:
	return Rect2(D.X0 + 0.5, 1.0, (D.X1 - 0.5) - (D.X0 + 0.5), (D.WALL_Y - 0.7) - 1.0)


func can_place_trap(x: float, y: float, ignore_uid := -1) -> Dictionary:
	var b := trap_bounds()
	if x < b.position.x or x > b.end.x or y < b.position.y or y > b.end.y:
		return {"msg": "Traps go on open ground in front of the wall."}
	for t in traps:
		if t["uid"] == ignore_uid:
			continue
		if Vector2(t["x"] - x, t["y"] - y).length() < TRAP_GAP:
			return {"msg": "Too close to another trap."}
	return {"ok": true}


func place_trap(i: int, x: float, y: float) -> Dictionary:
	var items: Array = storage["items"]
	if i < 0 or i >= items.size() or D.item_kind(items[i]["key"]) != "trap":
		return {"msg": "Only traps can go on the field."}
	var chk := can_place_trap(x, y)
	if not chk.has("ok"):
		return chk
	var it: Dictionary = items[i]
	items.remove_at(i)
	traps.append({"uid": it["uid"], "key": it["key"], "x": x, "y": y, "uses": it["uses"], "max": float(D.ITEMS[it["key"]]["uses"]), "hold": -1, "rearm": 0.0, "t": 0.0})
	_changed()
	sound.emit("build")
	return {"ok": true}


func find_trap(tuid: int) -> Variant:
	for t in traps:
		if t["uid"] == tuid:
			return t
	return null


func move_trap(tuid: int, x: float, y: float) -> Dictionary:
	var t = find_trap(tuid)
	if t == null:
		return {"msg": ""}
	if t["hold"] >= 0:
		return {"msg": "It has a zombie in its jaws. Wait for it to open."}
	var chk := can_place_trap(x, y, tuid)
	if not chk.has("ok"):
		return chk
	t["x"] = x
	t["y"] = y
	sound.emit("build")
	return {"ok": true}


func pick_up_trap(tuid: int) -> Dictionary:
	var t = find_trap(tuid)
	if t == null:
		return {"msg": ""}
	if t["hold"] >= 0:
		return {"msg": "It has a zombie in its jaws. Wait for it to open."}
	if storage_free() <= 0:
		return {"msg": "Storage is full."}
	storage["items"].append({"uid": t["uid"], "key": t["key"], "uses": t["uses"]})
	traps.erase(t)
	_changed()
	sound.emit("coin")
	return {"ok": true}


func trap_at(x: float, y: float) -> Variant:
	var best = null
	var bd := INF
	for t in traps:
		var d := Vector2(t["x"] - x, t["y"] - y).length()
		if d < maxf(0.55, D.TRAP_R[t["key"]]) and d < bd:
			bd = d
			best = t
	return best


func ignite_slicks(x: float, y: float, r: float) -> void:
	for t in traps:
		if t["key"] != "slick" or t["uses"] <= 0:
			continue
		if Vector2(t["x"] - x, t["y"] - y).length() < r + D.TRAP_R["slick"] * 0.6:
			t["uses"] = 0.0
			_add_fire(t["x"], t["y"], 1.15, 6.0)
			burst(t["x"], t["y"], 18, {"colors": [Color("ffe08a"), Color("ffb347"), Color("ff7a2a")], "spread": 2.0, "up": 160.0, "life": 0.7, "size": 4.0, "z": 4.0, "glow": true})
			sound.emit("fire")


func _within(z: Dictionary, t: Dictionary) -> bool:
	return Vector2(z["x"] - t["x"], z["y"] - t["y"]).length() < D.TRAP_R[t["key"]] + ZT(z["type"])["r"] * 0.6


func _zombie_by_id(id: int) -> Variant:
	for z in zombies:
		if z["id"] == id:
			return z
	return null


func update_traps(dt: float) -> void:
	for z in zombies:
		z["slow"] = 1.0
	for t in traps:
		t["t"] += dt
		match t["key"]:
			"spikes":
				for z in zombies:
					if z["hp"] <= 0 or not _within(z, t):
						continue
					damage(z, 14.0 * dt, true)
					z["slow"] = minf(z["slow"], 0.5)
					t["uses"] -= dt * (3.0 if z["type"] == "brute" else 1.0)
					if randf() < dt * 4.0:
						burst(z["x"], z["y"], 1, {"colors": [Color("6a2a22")], "spread": 0.6, "up": 40.0, "life": 0.3, "size": 2.0, "z": 4.0})
			"beartrap":
				if t["hold"] >= 0:
					var z = _zombie_by_id(t["hold"])
					if z == null or z["hp"] <= 0 or not (z["held"] > 0):
						t["hold"] = -1
						t["rearm"] = 1.0
					else:
						z["x"] = t["x"]
						z["y"] = t["y"]
				elif t["rearm"] > 0:
					t["rearm"] -= dt
				elif t["uses"] > 0:
					for z in zombies:
						if z["hp"] > 0 and not (z["held"] > 0) and _within(z, t):
							z["held"] = 1.2 if z["type"] == "brute" else 3.0
							t["hold"] = z["id"]
							t["uses"] -= 1.0
							damage(z, 30.0)
							sound.emit("hit")
							burst(t["x"], t["y"], 6, {"colors": [Color("9aa0a3"), Color("6a2a22")], "spread": 1.0, "up": 70.0, "life": 0.4, "size": 2.0, "z": 4.0})
							break
			"mine":
				if t["uses"] > 0:
					for z in zombies:
						if z["hp"] > 0 and _within(z, t):
							t["uses"] = 0.0
							explode(t["x"], t["y"], 120.0, 1.8)
							break
			"slick":
				t["uses"] -= dt
				for z in zombies:
					if z["hp"] > 0 and _within(z, t):
						z["slow"] = minf(z["slow"], 0.6)
				for f in fires:
					if Vector2(f["x"] - t["x"], f["y"] - t["y"]).length() < f["r"] + D.TRAP_R["slick"] * 0.6:
						ignite_slicks(f["x"], f["y"], f["r"])
						break
	var before := traps.size()
	traps = traps.filter(func(t): return t["uses"] > 0 or t["hold"] >= 0)
	if traps.size() != before:
		_changed()


# --- Inventory --------------------------------------------------------------
# A location is a Dictionary:
#   {"where": "storage", "i": i}         slot i of storage (i >= item count is an empty slot)
#   {"where": "weapon", "s": s}          survivor s's weapon slot
#   {"where": "gear", "s": s, "g": g}    survivor s's gear slot g (0 or 1)
func item_at(loc: Dictionary) -> Variant:
	match loc["where"]:
		"storage":
			var items: Array = storage["items"]
			return items[loc["i"]] if loc["i"] < items.size() else null
		"weapon":
			if loc["s"] >= crew.size():
				return null
			return {"key": crew[loc["s"]]["weapon"]}
		"gear":
			if loc["s"] >= crew.size():
				return null
			return crew[loc["s"]]["gear"][loc["g"]]
	return null


static func same_loc(a: Dictionary, b: Dictionary) -> bool:
	return a["where"] == b["where"] and a.get("i", -1) == b.get("i", -1) and a.get("s", -1) == b.get("s", -1) and a.get("g", -1) == b.get("g", -1)


# Checks a move without doing it. Returns {"ok": true} or {"msg": "..."}.
func can_move(from: Dictionary, to: Dictionary) -> Dictionary:
	var a = item_at(from)
	if a == null or same_loc(from, to):
		return {"msg": ""}
	var kind := D.item_kind(a["key"])
	var b = item_at(to)
	if to["where"] == "storage":
		if from["where"] == "storage":
			return {"ok": true} if b != null else {"msg": ""}
		if from["where"] == "weapon":
			if b != null and D.item_kind(b["key"]) == "weapon":
				return {"ok": true}
			return {"msg": "Everyone keeps a gun. Swap it for another gun in storage instead."}
		# from gear
		if b == null:
			return {"ok": true} if storage_free() > 0 else {"msg": "Storage is full."}
		if D.item_kind(b["key"]) == "mod":
			return {"ok": true}
		return {"msg": "Put it in an empty storage slot."}
	if kind == "trap":
		return {"msg": "Traps go on the field. Drag it past the wall."}
	if to["where"] == "weapon":
		if kind != "weapon":
			return {"msg": "Supplies get used from storage, not carried." if kind == "supply" else "Only guns go in the weapon slot."}
		return {"ok": true}
	if kind != "mod":
		return {"msg": "Supplies get used from storage, not carried." if kind == "supply" else "Only gear goes in these slots: hollow points, hair triggers and molotov crates."}
	return {"ok": true}


func move_item(from: Dictionary, to: Dictionary) -> Dictionary:
	var chk := can_move(from, to)
	if not chk.has("ok"):
		return chk
	var items: Array = storage["items"]
	var a = item_at(from)
	var b = item_at(to)
	if to["where"] == "weapon":
		var target: Dictionary = crew[to["s"]]
		if from["where"] == "storage":
			var old: String = target["weapon"]
			target["weapon"] = a["key"]
			items[from["i"]] = new_item(old)
		else:
			var src: Dictionary = crew[from["s"]]
			var tmp: String = src["weapon"]
			src["weapon"] = target["weapon"]
			target["weapon"] = tmp
			src["cd"] = maxf(src["cd"], 0.25)
		target["cd"] = maxf(target["cd"], 0.25)
	elif to["where"] == "gear":
		var target: Dictionary = crew[to["s"]]
		if from["where"] == "storage":
			if b != null:
				items[from["i"]] = b
			else:
				items.remove_at(from["i"])
			target["gear"][to["g"]] = a
		else:
			var src: Dictionary = crew[from["s"]]
			src["gear"][from["g"]] = b
			target["gear"][to["g"]] = a
	else:
		if from["where"] == "storage":
			var tmp = items[from["i"]]
			items[from["i"]] = items[to["i"]]
			items[to["i"]] = tmp
		elif from["where"] == "weapon":
			var src: Dictionary = crew[from["s"]]
			src["weapon"] = b["key"]
			items[to["i"]] = new_item(a["key"])
			src["cd"] = maxf(src["cd"], 0.25)
		else:
			var src: Dictionary = crew[from["s"]]
			if b != null:
				src["gear"][from["g"]] = b
				items[to["i"]] = a
			else:
				src["gear"][from["g"]] = null
				items.append(a)
	for s in crew:
		var has_mol := false
		for g in s["gear"]:
			if g != null and g["key"] == "molotov":
				has_mol = true
		if has_mol and not (s["mol_cd"] > 0):
			s["mol_cd"] = 3.0
	_changed()
	return {"ok": true}


func use_supply(i: int) -> Dictionary:
	var items: Array = storage["items"]
	if i >= items.size() or D.item_kind(items[i]["key"]) != "supply":
		return {"msg": ""}
	var it: Dictionary = items[i]
	if it["key"] == "repair":
		if wall["hp"] >= wall["max_hp"]:
			return {"msg": "The wall is already at full strength."}
		wall["hp"] = minf(wall["max_hp"], wall["hp"] + wall["max_hp"] * 0.5)
	elif it["key"] == "wire":
		if mods["wire"] >= D.WIRE_MAX:
			return {"msg": "There is no room for more wire along the wall."}
		mods["wire"] = minf(D.WIRE_MAX, mods["wire"] + 8.0)
	sound.emit("build")
	items.remove_at(i)
	_changed()
	return {"ok": true, "msg": D.item_name(it["key"]) + " used."}


func drop_item(loc: Dictionary) -> Dictionary:
	if loc["where"] == "storage":
		if loc["i"] >= storage["items"].size():
			return {"msg": ""}
		storage["items"].remove_at(loc["i"])
	elif loc["where"] == "gear":
		var s: Dictionary = crew[loc["s"]]
		if s["gear"][loc["g"]] == null:
			return {"msg": ""}
		s["gear"][loc["g"]] = null
	else:
		return {"msg": "Everyone keeps a gun."}
	_changed()
	return {"ok": true}


func add_to_storage(key: String) -> bool:
	if storage_free() <= 0:
		return false
	storage["items"].append(new_item(key))
	_changed()
	return true


# Hands out storage sensibly. Used by the automated balance test.
const RANK := {"pistol": 0, "smg": 2, "shotgun": 1, "rifle": 3, "launcher": 4}


func auto_equip() -> void:
	var moved := true
	var guard := 0
	while moved and guard < 50:
		guard += 1
		moved = false
		var items: Array = storage["items"]
		for i in items.size():
			var key: String = items[i]["key"]
			var kind := D.item_kind(key)
			if kind == "trap":
				moved = place_trap(i, D.X0 + 1 + randf() * (D.X1 - D.X0 - 2), 6.0 + randf() * 6.0).has("ok")
			elif kind == "supply":
				if (key == "wire" and mods["wire"] < D.WIRE_MAX) or (key == "repair" and wall["hp"] < wall["max_hp"] * 0.7):
					moved = use_supply(i).has("ok")
			elif kind == "weapon":
				var worst := -1
				var wr: int = RANK[key]
				for k in crew.size():
					if RANK[crew[k]["weapon"]] < wr:
						wr = RANK[crew[k]["weapon"]]
						worst = k
				if worst >= 0:
					moved = move_item({"where": "storage", "i": i}, {"where": "weapon", "s": worst}).has("ok")
			else:
				for k in crew.size():
					for g in 2:
						if not moved and crew[k]["gear"][g] == null:
							moved = move_item({"where": "storage", "i": i}, {"where": "gear", "s": k, "g": g}).has("ok")
			if moved:
				break


# --- Experience and cards ---------------------------------------------------
func _item_card(key: String) -> Dictionary:
	var kind := D.item_kind(key)
	return {"id": "item", "key": key, "tag": D.KIND_TAG[kind], "title": D.item_name(key),
		"desc": D.item_desc(key) + (" Goes to storage; drag it onto the field." if kind == "trap" else " Goes to storage.")}


func _candidates() -> Array:
	var c: Array = []
	var wall_frac: float = wall["hp"] / wall["max_hp"]
	var room := storage_free() > 0
	if room:
		for k in ["smg", "shotgun", "rifle", "launcher"]:
			c.append({"w": 0.9, "card": _item_card(k)})
		c.append({"w": 1.0, "card": _item_card("hollow")})
		c.append({"w": 1.0, "card": _item_card("trigger")})
		c.append({"w": 0.8, "card": _item_card("molotov")})
		c.append({"w": 2.2 if wall_frac < 0.5 else (1.0 if wall_frac < 0.85 else 0.4), "card": _item_card("repair")})
		if mods["wire"] < D.WIRE_MAX:
			c.append({"w": 0.7, "card": _item_card("wire")})
		for k in ["spikes", "beartrap", "mine", "slick"]:
			c.append({"w": 0.5, "card": _item_card(k)})
	if storage["cap"] < D.STORAGE_MAX:
		c.append({"w": 0.4 if room else 3.0, "card": {"id": "shelves", "tag": "Base", "title": "Shelving", "desc": "Base storage holds 4 more items. It holds %d now." % storage["cap"]}})
	if crew.size() < D.MAX_CREW:
		var n := free_name()
		c.append({"w": 1.5, "card": {"id": "hire", "name": n, "weapon": "pistol", "tag": "Crew", "title": "Take in " + n, "desc": n + " joins you on the wall with a pistol and two empty gear slots."}})
	if crew.size() > 1:
		c.append({"w": 1.0, "card": {"id": "drill", "tag": "Crew", "title": "Drill the crew", "desc": "Everyone else on the wall does 30% more base damage and fires 12% faster."}})
	var st: int = wall["stage"]
	var nxt := "Stone facing" if st == 0 else ("Steel plating" if st == 2 else ("More stone" if st < 3 else "More steel"))
	c.append({"w": 0.9, "card": {"id": "reinforce", "tag": "Wall", "title": nxt, "desc": "The wall gets 30% tougher, and the new strength comes fully built."}})
	return c


func draw_cards() -> Array:
	var pool := _candidates()
	var out: Array = []
	while out.size() < 3 and pool.size() > 0:
		var total := 0.0
		for c in pool:
			total += c["w"]
		var r := randf() * total
		var k := 0
		while k < pool.size() - 1:
			r -= pool[k]["w"]
			if r <= 0:
				break
			k += 1
		out.append(pool[k]["card"])
		pool.remove_at(k)
	return out


func apply_card(card: Dictionary) -> void:
	match card["id"]:
		"item":
			add_to_storage(card["key"])
		"shelves":
			storage["cap"] = mini(D.STORAGE_MAX, storage["cap"] + 4)
			_changed()
		"hire":
			add_survivor(card["name"], card["weapon"], false)
			_changed()
		"drill":
			mods["crew_dmg"] += 0.3
			mods["crew_rate"] = maxf(0.5, mods["crew_rate"] * 0.88)
			_changed()
		"reinforce":
			var add := roundf(wall["max_hp"] * 0.3)
			wall["max_hp"] += add
			wall["hp"] += add
			wall["stage"] += 1
	picks.append(card["title"])


func choose_card(i: int) -> void:
	if i < 0 or i >= cards.size():
		return
	apply_card(cards[i])
	cards = []
	if pending_levels > 0:
		pending_levels -= 1
		cards = draw_cards()
		leveled_up.emit()


func _check_level() -> void:
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_need(level)
		pending_levels += 1
	if pending_levels > 0 and cards.is_empty():
		pending_levels -= 1
		cards = draw_cards()
		sound.emit("levelup")
		leveled_up.emit()


# --- Director ---------------------------------------------------------------
static func spawn_rate(t: float) -> float:
	return 0.4 + t * 0.0075 + pow(t / 200.0, 2) * 0.6


static func hp_mul(t: float) -> float:
	return 1.0 + t / 170.0 + pow(t / 420.0, 2)


static func spd_mul(t: float) -> float:
	return 1.0 + minf(0.35, t / 900.0)


func _pick_type(t: float) -> String:
	var r := randf()
	var pb := minf(0.14, 0.03 + (t - 100.0) / 1200.0) if t > 100 else 0.0
	var pr := minf(0.35, 0.08 + (t - 35.0) / 400.0) if t > 35 else 0.0
	if r < pb:
		return "brute"
	if r < pb + pr:
		return "runner"
	return "walker"


func _spawn_one() -> void:
	var type := _pick_type(time)
	spawn_zombie(type, hp_mul(time), spd_mul(time))
	if not seen.has(type):
		seen[type] = true
		if type == "runner":
			toast.emit("Runners. Fast and fragile. Get them before they reach the wall.", "danger")
		elif type == "brute":
			toast.emit("A brute. Slow, huge, and it hits the wall hard.", "danger")


func update_director(dt: float) -> void:
	time += dt
	threat = 1 + int(time / 45.0)
	spawn_acc += spawn_rate(time) * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		_spawn_one()
	if time >= next_horde:
		next_horde += D.HORDE_EVERY
		horde_left += 8 + int(time / 10.0)
		toast.emit("A horde is coming.", "danger")
		sound.emit("horn")
	if horde_left > 0:
		horde_acc += dt * 6.0
		while horde_acc >= 1.0 and horde_left > 0:
			horde_acc -= 1.0
			horde_left -= 1
			_spawn_one()
	# Dusk deepens into night over the first few minutes.
	var target := minf(0.58, 0.12 + time / 320.0)
	dark += (target - dark) * minf(1.0, dt)


# --- Main step --------------------------------------------------------------
# Advances the world by dt seconds. Does nothing while a card choice is open.
func step(dt: float) -> void:
	if over or not cards.is_empty():
		update_parts(dt)
		return
	update_director(dt)
	update_traps(dt)
	update_zombies(dt)
	update_crew(dt)
	update_shots(dt)
	update_parts(dt)
	_check_level()
