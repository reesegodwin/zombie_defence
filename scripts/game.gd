# The whole simulation: wall, zombies, crew, weapons, traps, inventory,
# scavenging trips, food, the workshop, and the director that keeps raising the
# pressure.
# It has no nodes, so it can be run headlessly by the tests.
extends RefCounted

const D = preload("res://scripts/defs.gd")

signal toast(text: String, kind: String)
signal sound(name: String)
signal inv_changed
signal trip_returned(report: Dictionary)
signal survivor_arrived(name: String)
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
var scrap := D.START_SCRAP
var food := D.START_FOOD       # eaten continuously by everyone in the crew
var hungry := false
var trip = null                # the scavenging trip in progress, or null
var looted := {}               # site key -> true once a scavenger has picked it clean
var purchases: Array = []
var drills := 0
var shelves := 0
var kills := 0
var dark := 0.12
var over := false
var seen := {}
var zid := 1
var uid := 1
var spawn_acc := 0.0
var next_horde := D.FIRST_HORDE
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
	add_survivor("You", "pistol", true)


# --- Helpers ----------------------------------------------------------------
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
func add_survivor(sname: String, weapon: String, is_player: bool) -> Dictionary:
	var i := crew.size()
	crew.append({
		"name": sname, "weapon": weapon, "is_player": is_player, "gear": [null, null], "mol_cd": 0.0,
		"x": 0.0, "y": 0.0, "slot_x": 0.0, "state": "wall", "path_t": 0.0, "cd": 0.3 + randf() * 0.3, "aim": -PI * 0.75, "flash": 0.0, "recoil": 0.0,
		"jacket": Color("3e5a6e") if is_player else D.JACKETS[i % D.JACKETS.size()],
		"skin": Color("d9a77f") if is_player else D.SKINS[(i * 3) % D.SKINS.size()],
	})
	layout_crew()
	return crew[-1]


func layout_crew() -> void:
	var mid := (D.X0 + D.X1) / 2.0
	for i in crew.size():
		var s: Dictionary = crew[i]
		s["slot_x"] = clampf(mid + D.CREW_SLOTS[i], D.X0 + 0.6, D.X1 - 0.6)
		if s.get("state", "wall") == "wall":
			s["x"] = s["slot_x"]
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
	if hungry:
		rate *= D.HUNGRY_SLOWDOWN
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
		s["flash"] = maxf(0.0, s["flash"] - dt)
		s["recoil"] = maxf(0.0, s["recoil"] - dt)
		if s["state"] != "wall":
			continue
		s["cd"] -= dt
		if s.get("repairing", false):
			continue
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
			# Holding the mouse aims at the cursor. Otherwise, with auto-fire on,
			# you face whatever auto-fire is shooting at; with it off, the cursor.
			var manual: bool = input_firing and input_aim != null
			var target = null
			if not manual and input_auto:
				target = auto_target(s, w["range"])
				if target != null:
					s["aim"] = atan2(target["y"] - s["y"], target["x"] - s["x"])
			elif input_aim != null:
				s["aim"] = atan2(input_aim.y - s["y"], input_aim.x - s["x"])
			s["auto_target"] = target["id"] if target != null else -1
			if s["cd"] > 0:
				continue
			if manual:
				fire(s, input_aim.x, input_aim.y, k["dmg"])
				s["cd"] = k["interval"]
			elif target != null:
				fire(s, target["x"], target["y"], k["dmg"])
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
	for loc in [from, to]:
		if loc["where"] != "storage" and loc["s"] < crew.size() and crew[loc["s"]]["state"] != "wall":
			return {"msg": crew[loc["s"]]["name"] + " isn't on the wall right now."}
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
	if it["key"] == "wire":
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
				if key == "wire" and mods["wire"] < D.WIRE_MAX:
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


# --- Scavenging -------------------------------------------------------------
# One survivor at a time can leave through the mountain pass to loot a site on
# the map. They walk out, are gone for a while, then walk back with scrap and
# maybe a gun, food or another survivor.

## Survivors who could be sent out right now (indices into crew).
func available_scavengers() -> Array:
	var out: Array = []
	for i in crew.size():
		if not crew[i]["is_player"] and crew[i]["state"] == "wall":
			out.append(i)
	return out


func can_scavenge(si: int) -> Dictionary:
	if trip != null:
		return {"msg": trip["who"]["name"] + " is already out. Only one person can go at a time."}
	if si < 0 or si >= crew.size():
		return {"msg": "Nobody to send. Wait for a survivor to find you."}
	var s: Dictionary = crew[si]
	if s["is_player"]:
		return {"msg": "You have to stay and hold the wall."}
	if s["state"] != "wall":
		return {"msg": s["name"] + " isn't on the wall right now."}
	return {"ok": true}


func site_open(site_key: String) -> bool:
	return not looted.has(site_key) and not (trip != null and trip["site"] == site_key)


func open_sites() -> Array:
	return D.SITE_KEYS.filter(func(k): return site_open(k))


func can_send(si: int, site_key: String) -> Dictionary:
	if looted.has(site_key):
		return {"msg": "The %s has already been picked clean." % D.SITES[site_key]["name"]}
	return can_scavenge(si)


func send_scavenger(si: int, site_key: String) -> Dictionary:
	var chk := can_send(si, site_key)
	if not chk.has("ok"):
		return chk
	var site: Dictionary = D.SITES[site_key]
	var s: Dictionary = crew[si]
	var walk := path_length(s["slot_x"]) / D.WALK_SPEED
	s["repairing"] = false
	s["state"] = "leaving"
	s["path_t"] = 0.0
	trip = {"who": s, "site": site_key, "away": maxf(5.0, site["gone"] - walk * 2.0), "t": 0.0, "walk": walk}
	toast.emit("%s heads out through the pass to the %s." % [s["name"], site["name"]], "info")
	_changed()
	return {"ok": true}


## Seconds until the survivor out scavenging is back on the wall.
func trip_time_left() -> float:
	if trip == null:
		return 0.0
	var s: Dictionary = trip["who"]
	var walk: float = trip["walk"]
	match s["state"]:
		"leaving":
			return walk * (1.0 - s["path_t"]) + trip["away"] + walk
		"away":
			return trip["away"] - trip["t"] + walk
		"returning":
			return walk * s["path_t"]
	return 0.0


func update_trip(dt: float) -> void:
	if trip == null:
		return
	var s: Dictionary = trip["who"]
	if s["state"] == "away":
		trip["t"] += dt
		if trip["t"] >= trip["away"]:
			trip["report"] = _roll_loot(trip["site"])
			s["state"] = "returning"
			s["path_t"] = 1.0
			if trip["report"]["survivor"] != "":
				var n := add_survivor(trip["report"]["survivor"], "pistol", false)
				n["state"] = "arriving"
				n["path_t"] = 1.12   # a few steps behind
				n["x"] = D.PASS_PATH[-1].x
				n["y"] = D.PASS_PATH[-1].y


## Moves everyone who is walking between the wall and the pass.
func update_walkers(dt: float) -> void:
	for s in crew:
		var st: String = s["state"]
		if st == "wall" or st == "away":
			continue
		var length := path_length(s["slot_x"])
		var dp := D.WALK_SPEED * dt / length
		if st == "leaving":
			s["path_t"] = minf(1.0, s["path_t"] + dp)
			if s["path_t"] >= 1.0:
				s["state"] = "away"
		else:
			s["path_t"] = maxf(0.0, s["path_t"] - dp)
			if s["path_t"] <= 0.0:
				s["state"] = "wall"
				s["cd"] = 0.5
				if st == "returning":
					_deliver_trip()
				else:
					survivor_arrived.emit(s["name"])
					toast.emit("%s made it through the pass and joins you on the wall." % s["name"], "good")
					sound.emit("coin")
				_changed()
		var p := path_point(s["slot_x"], minf(1.0, s["path_t"]))
		s["x"] = p.x
		s["y"] = p.y


func _roll_loot(site_key: String) -> Dictionary:
	var site: Dictionary = D.SITES[site_key]
	var tier: Array = D.SCRAP_TIERS[site["scrap"]]
	var r := {"site": site_key, "scrap": randi_range(tier[0], tier[1]), "weapon": "", "food": 0, "survivor": ""}
	if randf() < site["weapon_chance"]:
		r["weapon"] = ["smg", "shotgun", "rifle", "launcher", "smg", "shotgun", "rifle"].pick_random()
	if randf() < site["food_chance"]:
		r["food"] = randi_range(2, 5)
	if randf() < site["survivor_chance"] and crew.size() < D.MAX_CREW:
		r["survivor"] = free_name()
	return r


func _deliver_trip() -> void:
	var s: Dictionary = trip["who"]
	var r: Dictionary = trip["report"]
	var site: Dictionary = D.SITES[r["site"]]
	looted[r["site"]] = true
	scrap += r["scrap"]
	food += r["food"]
	var found: Array = ["%d scrap" % r["scrap"]]
	r["weapon_kept"] = false
	if r["weapon"] != "":
		if add_to_storage(r["weapon"]):
			r["weapon_kept"] = true
			found.append("a " + D.item_name(r["weapon"]).to_lower())
		else:
			found.append("a " + D.item_name(r["weapon"]).to_lower() + " (left behind: storage is full)")
	if r["food"] > 0:
		found.append("%d food" % r["food"])
	if r["survivor"] != "":
		found.append(r["survivor"] + ", a survivor")
	var text := "%s is back from the %s with " % [s["name"], site["name"]]
	if found.size() == 1:
		text += found[0] + "."
	else:
		text += ", ".join(PackedStringArray(found.slice(0, found.size() - 1))) + " and " + found[-1] + "."
	r["who"] = s["name"]
	r["text"] = text
	trip = null
	sound.emit("coin")
	toast.emit(text, "good")
	trip_returned.emit(r)


# --- The walk to the pass ---------------------------------------------------
## The route from a survivor's spot on the walkway out through the pass.
static func path_points(slot_x: float) -> Array:
	var pts: Array = [Vector2(slot_x, D.WALK_Y), Vector2(slot_x, D.WALK_Y + 1.2)]
	pts.append_array(D.PASS_PATH)
	return pts


static func path_length(slot_x: float) -> float:
	var pts := path_points(slot_x)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## A point along the route, t from 0 (walkway) to 1 (out of sight in the pass).
static func path_point(slot_x: float, t: float) -> Vector2:
	var pts := path_points(slot_x)
	var target := clampf(t, 0.0, 1.0) * path_length(slot_x)
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if target <= seg:
			return pts[i - 1].lerp(pts[i], target / maxf(seg, 0.001))
		target -= seg
	return pts[-1]


# --- Repairing the wall -----------------------------------------------------
# Any survivor on the walkway (you included) can be set to repair the wall.
# They stop shooting while they work, and each bit of wall costs scrap.
var _repair_debt := 0.0         # scrap owed for repairs so far, paid a whole scrap at a time


func repairers() -> int:
	var n := 0
	for s in crew:
		if s.get("repairing", false):
			n += 1
	return n


func toggle_repair(i: int) -> Dictionary:
	if i < 0 or i >= crew.size():
		return {"msg": ""}
	var s: Dictionary = crew[i]
	if s.get("repairing", false):
		s["repairing"] = false
		return {"ok": true, "msg": "You go back to shooting." if s["is_player"] else s["name"] + " goes back to shooting."}
	if s["state"] != "wall":
		return {"msg": s["name"] + " isn't on the wall right now."}
	if wall["hp"] >= wall["max_hp"]:
		return {"msg": "The wall doesn't need repairs."}
	if scrap <= 0 and _repair_debt <= 0.0:
		return {"msg": "No scrap to repair with."}
	s["repairing"] = true
	s["repair_fx"] = 0.0
	sound.emit("build")
	return {"ok": true, "msg": ("You start" if s["is_player"] else s["name"] + " starts") + " repairing the wall."}


func update_repairs(dt: float) -> void:
	for s in crew:
		if not s.get("repairing", false):
			continue
		if s["state"] != "wall":
			s["repairing"] = false
			continue
		if wall["hp"] >= wall["max_hp"]:
			s["repairing"] = false
			toast.emit(("You finish" if s["is_player"] else s["name"] + " finishes") + " repairing. The wall is at full strength.", "good")
			continue
		if scrap <= 0:
			s["repairing"] = false
			toast.emit("Out of scrap. Repairs have stopped.", "danger")
			continue
		var gain := minf(D.REPAIR_PER_SECOND * dt, wall["max_hp"] - wall["hp"])
		wall["hp"] += gain
		_repair_debt += gain / D.WALL_PER_SCRAP
		while _repair_debt >= 1.0 and scrap > 0:
			_repair_debt -= 1.0
			scrap -= 1
		# Sparks where they're working, and the odd hammer blow.
		s["repair_fx"] -= dt
		if s["repair_fx"] <= 0.0:
			s["repair_fx"] = 0.35 + randf() * 0.2
			burst(s["x"] + randf_range(-0.3, 0.3), D.WALL_Y + D.WALL_T, 4, {"colors": [Color("ffe08a"), Color("ffb347")], "spread": 0.8, "up": 90.0, "life": 0.35, "size": 1.6, "z": 14.0, "glow": true})
			sound.emit("hit")


# --- Strangers --------------------------------------------------------------
# One survivor always finds the outpost and walks in through the pass early
# on. After that, strangers only come down the pass if you've lost everyone:
# while you're alone, one turns up every so often.
var first_stranger_done := false


func update_arrivals(dt: float) -> void:
	if crew.size() >= D.MAX_CREW:
		return
	if not first_stranger_done:
		if time >= D.FIRST_STRANGER_AT:
			first_stranger_done = true
			_stranger_arrives()
		return
	# Survivors out scavenging or walking in still count as alive.
	if crew.size() == 1 and randf() < dt / D.STRANGER_EVERY_WHEN_ALONE:
		_stranger_arrives()


func _stranger_arrives() -> void:
	var n := add_survivor(free_name(), "pistol", false)
	n["state"] = "arriving"
	n["path_t"] = 1.0
	var p := path_point(n["slot_x"], 1.0)
	n["x"] = p.x
	n["y"] = p.y
	toast.emit("Someone is coming down the mountain pass…", "info")


# --- Food -------------------------------------------------------------------
# Everyone eats all the time: each survivor, you included and anyone out
# scavenging, gets through FOOD_PER_MINUTE. When the stock runs out the whole
# crew is hungry and shoots slower until food comes in.

## Food eaten per minute by the whole crew right now.
func food_per_minute() -> float:
	return crew.size() * D.FOOD_PER_MINUTE


## Seconds until the food runs out at the current rate.
func food_time_left() -> float:
	var rate := food_per_minute()
	return INF if rate <= 0.0 else food / rate * 60.0


func update_food(dt: float) -> void:
	food = maxf(0.0, food - food_per_minute() / 60.0 * dt)
	if food <= 0.0 and not hungry:
		hungry = true
		toast.emit("The food has run out. The crew is hungry and shoots slower.", "danger")
	elif food > 0.0 and hungry:
		hungry = false
		toast.emit("There's food again. The crew is back to full strength.", "good")


# --- Workshop ---------------------------------------------------------------
## Current price of a workshop entry (some get dearer each time you buy them).
func shop_cost(id: String) -> int:
	var base: int = D.SHOP[id]["cost"]
	match id:
		"reinforce":
			return int(round(base * (1.0 + 0.6 * wall["stage"])))
		"drill":
			return int(round(base * (1.0 + 0.7 * drills)))
		"shelves":
			return base + 15 * shelves
	return base


func can_buy(id: String) -> Dictionary:
	var cost := shop_cost(id)
	if id == "shelves" and storage["cap"] >= D.STORAGE_MAX:
		return {"msg": "Storage can't get any bigger."}
	if id == "drill" and crew.size() < 2:
		return {"msg": "You need a crew to drill."}
	if D.ITEMS.has(id) and storage_free() <= 0:
		return {"msg": "Storage is full."}
	if id == "wire" and mods["wire"] >= D.WIRE_MAX:
		return {"msg": "There is no room for more wire."}
	if scrap < cost:
		return {"msg": "Not enough scrap (%d needed)." % cost}
	return {"ok": true}


func buy(id: String) -> Dictionary:
	var chk := can_buy(id)
	if not chk.has("ok"):
		return chk
	scrap -= shop_cost(id)
	if D.ITEMS.has(id):
		add_to_storage(id)
	else:
		match id:
			"shelves":
				storage["cap"] = mini(D.STORAGE_MAX, storage["cap"] + 4)
				shelves += 1
			"drill":
				mods["crew_dmg"] += 0.3
				mods["crew_rate"] = maxf(0.5, mods["crew_rate"] * 0.88)
				drills += 1
			"reinforce":
				var add := roundf(wall["max_hp"] * 0.3)
				wall["max_hp"] += add
				wall["hp"] += add
				wall["stage"] += 1
	purchases.append(D.SHOP[id]["name"])
	sound.emit("build")
	_changed()
	return {"ok": true}


# Sets someone repairing when the wall is low. Used by the automated balance test.
func auto_repair() -> void:
	var busy := 0
	for s in crew:
		if s.get("repairing", false):
			busy += 1
	if wall["hp"] < wall["max_hp"] * 0.6 and busy == 0 and scrap >= 5:
		for i in range(crew.size() - 1, -1, -1):
			if crew[i]["state"] == "wall":
				toggle_repair(i)
				return


# Spends scrap sensibly. Used by the automated balance test.
func auto_shop() -> void:
	auto_repair()
	var guard := 0
	while guard < 20:
		guard += 1
		var want := ""
		var worst := 99
		for c in crew:
			worst = mini(worst, RANK[c["weapon"]])
		if wall["hp"] < wall["max_hp"] * 0.6:
			break   # save scrap for repairs
		if worst < 2 and storage_free() > 0:
			want = "smg" if scrap < shop_cost("rifle") else "rifle"
		elif wall["stage"] < 4:
			want = "reinforce"
		elif crew.size() > 1 and drills < 3:
			want = "drill"
		else:
			want = ["hollow", "trigger", "mine", "spikes", "launcher"].pick_random()
		if not buy(want).has("ok"):
			break
	auto_equip()


## Sends someone out if nobody is out. Used by the automated balance test.
func auto_scavenge() -> void:
	var who := available_scavengers()
	var sites := open_sites()
	if trip != null or who.is_empty() or sites.is_empty():
		return
	send_scavenger(who.pick_random(), sites.pick_random())

# --- Director ---------------------------------------------------------------
static func spawn_rate(t: float) -> float:
	return 0.3 + t * 0.005 + pow(t / 230.0, 2) * 0.6


static func hp_mul(t: float) -> float:
	return 1.0 + t / 220.0 + pow(t / 450.0, 2)


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
		horde_left += 6 + int(time / 12.0)
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
	if over:
		update_parts(dt)
		return
	update_director(dt)
	update_trip(dt)
	update_walkers(dt)
	update_arrivals(dt)
	update_food(dt)
	update_repairs(dt)
	update_traps(dt)
	update_zombies(dt)
	update_crew(dt)
	update_shots(dt)
	update_parts(dt)
