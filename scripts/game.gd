# The whole simulation: wall, zombies, crew, weapons, traps, inventory,
# scavenging trips, food, the workshop, and the director that keeps raising the
# pressure.
# It has no nodes, so it can be run headlessly by the tests.
extends RefCounted

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")

signal toast(text: String, kind: String)
signal sound(name: String)
signal inv_changed
signal trip_returned(report: Dictionary)
signal survivor_arrived(name: String)
signal scavenger_lost(name: String, site: String)
signal research_done(id: String)
signal run_won
signal survivor_killed(name: String)
signal wall_patched(side: int)
signal exploded(x: float, y: float, radius: float)
signal zombie_died(x: float, y: float, type: String)
signal wall_breached(side: int, u: float)
signal side_opened(side: int)
signal turret_destroyed(index: int)
signal truck_coming(next_level: int)   # dawn after the last night: the truck's on its way
signal level_started(level: int)       # the crew have been driven to the next level's base
signal new_day(day: int)               # dawn (and the first morning): for the big day banner

# --- State ------------------------------------------------------------------
var time := 0.0
var threat := 1
var walls: Array = []          # one per lane: front, west, east
var wall := {}                 # the front wall (walls[0]), for short
var sides_open := [true, false, false]
var side_live_at := [0.0, INF, INF]   # when the dead start coming down each lane
var _side_warned := [true, false, false]
var zombies: Array = []
var crew: Array = []
var shots: Array = []
var fires: Array = []
var parts: Array = []
var tracers: Array = []
var bullets: Array = []      # shots in flight (see fire / update_bullets)
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
var dark := 0.12               # 0.12 by day .. 0.58 at night (drives the lighting)
var night := 0.0               # 0 in daylight, 1 in full dark, in between at dusk and dawn
var _cycle_done := {}          # day/night events already announced, e.g. "dusk2"
var over := false
var seen := {}
var zid := 1
var uid := 1
var spawn_acc := 0.0
var spawned := 0               # zombies spawned this run
var radio = null               # where the radio station stands (Vector2), or null
var horde_left := 0
var horde_acc := 0.0
var next_lull := D.FIRST_LULL
var lull_until := -1.0         # while time is below this, the dead thin out
var shake := 0.0
var fx_id := 1                 # ids for fires, so the 3D view can track them
var sid := 1                   # ids for survivors, so the 3D view can track them
var death_mul := 1.0           # scales the risk of dying while scavenging (tests set 0)
var researched := {}           # research id -> true once finished
var research_cur := ""         # the project under way, or ""
var research_t := 0.0          # seconds spent on it so far
var turrets: Array = []        # built auto-turrets
var hot_meal := 0.0            # Field kitchen: seconds of faster shooting left after sundown
var pantry := false            # the camp's Pantry
# From the camp (see apply_meta): Heat and the lasting upgrades.
var heat := 0
var level := 2                 # which level (D.LEVELS, from 1): which lanes the dead use
var open_at: Array = D.SIDE_OPEN_AT.duplicate()   # when each lane opens this run (INF: never)
var evac := -1.0               # seconds since the truck was called (-1: not yet)
var nights_before := 0         # nights held on earlier levels this run
var start_stage := 0           # the wall tier each new base starts with (Wooden walls at the camp)
var wall_mul := 1.0            # Tough: every wall tier is this much tougher
var price_mul := 1.0           # Quartermaster: workshop prices
var kill_scrap := 0            # Salvager: scrap per zombie killed (double for brutes)
var scav_eye := 0              # Scavenger's eye: its level (luckier scavenging)
var won := false               # held out to the end: the convoy came
var research_count := 0        # projects finished this run (blueprints don't count)

# Player input, written by main.gd each frame (grid coordinates).
var input_aim = null           # Vector2 or null: the host's own player (peer 1)
var input_firing := false
## The other players' (co-op): peer id -> {"aim": Vector2 or null, "firing": bool}.
var inputs := {}
var moved_crew := false         # has the player sent one of the crew somewhere yet (the tutorial)
var input_auto := false          # a stand-in player for the tests and balance bots: you shoot whatever is nearest the wall (not in the game)


func _init() -> void:
	var hp0: float = D.WALL_TIERS[0]["hp"]
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var w := {"hp": hp0, "max_hp": hp0, "stage": 0, "hurt": [], "side": side}
		for i in int(L["u1"] - L["u0"]):
			w["hurt"].append(0.0)
		walls.append(w)
	wall = walls[0]
	add_survivor("You", "pistol", true)
	crew[0]["peer"] = 1


# --- Lanes ------------------------------------------------------------------
## A point in a lane's frame (u along the wall, v towards the base) on the map.
static func lane_point(side: int, u: float, v: float) -> Vector2:
	var L: Dictionary = D.LANES[side]
	return L["o"] + L["t"] * u + L["n"] * v


## A map point in a lane's frame: Vector2(u, v).
static func lane_uv(side: int, p: Vector2) -> Vector2:
	var L: Dictionary = D.LANES[side]
	var d: Vector2 = p - L["o"]
	return Vector2(d.dot(L["t"]), d.dot(L["n"]))


## The lane whose ground in front of its wall holds p, or -1.
static func field_side(p: Vector2, margin := 0.0) -> int:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var uv := lane_uv(side, p)
		if uv.x >= L["u0"] + margin and uv.x <= L["u1"] - margin and uv.y >= D.LANE_START - 0.5 and uv.y <= D.WALL_Y:
			return side
	return -1


## True if p is up on one of the walkways behind the walls.
static func on_deck(p: Vector2, extra := 0.0) -> bool:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var uv := lane_uv(side, p)
		if uv.x >= L["u0"] - 0.2 and uv.x <= L["u1"] + 0.2 and uv.y >= D.WALL_Y + D.WALL_T and uv.y <= D.WALK_Y + 0.7 + extra:
			return true
	return false


## The walkway spot (side, u) under a map point, or {} if there's none.
static func deck_spot(p: Vector2) -> Dictionary:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var uv := lane_uv(side, p)
		if uv.x >= L["u0"] - 0.1 and uv.x <= L["u1"] + 0.1 and uv.y >= D.WALL_Y - 0.2 and uv.y <= D.WALK_Y + 1.0:
			return {"side": side, "u": clampf(uv.x, L["u0"] + 0.4, L["u1"] - 0.4)}
	return {}


## Which way is "out" from a wall, as an aim angle.
static func outward(side: int) -> float:
	var n: Vector2 = D.LANES[side]["n"]
	return atan2(-n.y, -n.x)


## The weakest wall that's open to the dead.
func weakest_wall() -> Dictionary:
	var best: Dictionary = walls[0]
	for w in walls:
		if sides_open[w["side"]] and w["hp"] / w["max_hp"] < best["hp"] / best["max_hp"]:
			best = w
	return best


## Opens the side lanes as the night goes on, with a warning first.
func update_sides() -> void:
	for side in range(1, D.LANES.size()):
		if sides_open[side]:
			continue
		var at: float = open_at[side]
		if at == INF:
			continue   # sealed on this level
		if not _side_warned[side] and time >= at - D.SIDE_WARNING:
			_side_warned[side] = true
			toast.emit("Something is moving in the dark to the %s. That side opens soon." % D.LANES[side]["name"].to_lower(), "danger")
			sound.emit("groan")
		if time >= at:
			open_side(side)


func open_side(side: int) -> void:
	sides_open[side] = true
	_side_warned[side] = true
	side_live_at[side] = time + D.SIDE_GRACE
	toast.emit("The %s is open. The dead will come from there soon: put someone on that wall." % D.LANES[side]["name"].to_lower(), "danger")
	sound.emit("horn")
	side_opened.emit(side)


# --- Helpers ----------------------------------------------------------------
func wall_mat() -> Dictionary:
	return D.WALL_MATS[clampi(wall["stage"], 0, D.WALL_MATS.size() - 1)]


func wall_name() -> String:
	return D.WALL_TIERS[wall["stage"]]["name"]


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
func add_survivor(sname: String, weapon: String, is_player: bool, skills = null) -> Dictionary:
	var i := crew.size()
	crew.append({
		"id": sid, "skills": ({} if is_player else roll_skills(false)) if skills == null else skills,
		"name": sname, "weapon": weapon, "is_player": is_player, "gear": [null, null],
		"x": 0.0, "y": 0.0, "side": -1, "u": 0.0, "route": [], "state": "wall", "path_t": 0.0, "cd": 0.3 + randf() * 0.3, "aim": -PI * 0.5, "flash": 0.0, "recoil": 0.0,
		"hp": D.SURVIVOR_HP, "max_hp": D.SURVIVOR_HP,
		"jacket": Color("3e5a6e") if is_player else D.JACKETS[i % D.JACKETS.size()],
		"skin": Color("d9a77f") if is_player else D.SKINS[(i * 3) % D.SKINS.size()],
	})
	sid += 1
	layout_crew()
	return crew[-1]


## One to three different random skills, each at level 1 to 3: {key: level}.
static func roll_skills(is_player: bool) -> Dictionary:
	var pool: Array = []
	for k in D.SKILLS:
		if D.SKILLS[k]["player"] or not is_player:
			pool.append(k)
	pool.shuffle()
	var n := _pick_weighted(D.SKILL_COUNT_ODDS) + 1
	var out := {}
	for k in pool.slice(0, n):
		out[k] = _pick_weighted(D.SKILL_LEVEL_ODDS) + 1
	return out


static func _pick_weighted(odds: Array) -> int:
	var r := randf()
	for i in odds.size():
		r -= odds[i]
		if r < 0.0:
			return i
	return odds.size() - 1


## "Handy II, Careful I"
static func skills_text(s: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in s.get("skills", {}):
		parts.append(D.skill_label(k, s["skills"][k]))
	return ", ".join(parts) if parts.size() > 0 else "No special skills"


## One line per skill, with what it does.
static func skills_detail(s: Dictionary) -> String:
	var lines: PackedStringArray = []
	for k in s.get("skills", {}):
		lines.append("%s: %s." % [D.skill_label(k, s["skills"][k]), D.skill_desc(k, s["skills"][k])])
	return "\n".join(lines) if lines.size() > 0 else "No special skills."


## Gives anyone new a spot on the front wall. Everyone else keeps theirs.
func layout_crew() -> void:
	for s in crew:
		if s["side"] >= 0:
			continue
		s["side"] = 0
		s["u"] = _free_front_spot(s)
		if s["u"] < 0.0:
			# The front walkway's full: a spot in the yard instead.
			_take_spot(s, _free_yard_spot(s))
		if s["state"] == "wall":
			var p := station_point(s)
			s["x"] = p.x
			s["y"] = p.y


func _free_front_spot(me: Dictionary) -> float:
	var mid := (D.X0 + D.X1) / 2.0
	# You start in the middle; the crew's spots go out from the middle of the
	# wall (not from wherever you've walked to), and you don't take one up.
	var offs: Array = [0.0, 1.0, -1.0, 2.0, -2.0] if me["is_player"] else D.CREW_SLOTS.slice(1)
	for k in range(1, 12):
		offs.append(-1.5 * k + 0.75)   # past the usual spots: fill in every metre and a half
		offs.append(1.5 * k - 0.75)
	for off in offs:
		var u := clampf(mid + off, D.X0 + 0.6, D.X1 - 0.6)
		var taken := false
		for o in crew:
			if o != me and o["is_player"] == me["is_player"] and o["side"] == 0 and not o.has("post") and absf(o["u"] - u) < (0.9 if me["is_player"] else 1.2):
				taken = true
		if not taken:
			return u
	return -1.0   # full


## A clear spot in the yard, away from everyone else.
func _free_yard_spot(me: Dictionary) -> Vector2:
	var y := D.WALK_Y + 2.0
	while y < D.BASE_Y1 - 1.0:
		var x := D.BASE_X0 + 1.5
		while x < D.BASE_X1 - 1.0:
			var p := Vector2(x, y)
			var clear := walkable(p)
			for o in crew:
				if o != me and Vector2(o["x"], o["y"]).distance_to(p) < 1.0:
					clear = false
			if clear:
				return p
			x += 1.2
		y += 1.2
	return D.HUB


## Where a survivor stands on their walkway.
static func station_point(s: Dictionary) -> Vector2:
	if s.has("post"):
		return s["post"]   # a spot in the yard
	return lane_point(s["side"], s["u"], D.WALK_Y)


## Just inside the yard, below a survivor's spot on the walkway.
static func yard_point(side: int, u: float) -> Vector2:
	return lane_point(side, u, D.WALK_Y + 1.2)


## The route from a survivor's spot out through the pass.
static func pass_route(s: Dictionary) -> Array:
	var pts: Array = [station_point(s)]
	if not s.has("post"):
		pts.append(yard_point(s["side"], s["u"]))
	pts.append_array(D.PASS_PATH)
	return pts


static func route_length(pts: Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## A point along a route, t from 0 (its start) to 1 (its end).
static func route_point(pts: Array, t: float) -> Vector2:
	var target := clampf(t, 0.0, 1.0) * route_length(pts)
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if target <= seg:
			return pts[i - 1].lerp(pts[i], target / maxf(seg, 0.001))
		target -= seg
	return pts[-1]


## Sends a survivor on the wall (or already walking to it) to a new spot,
## on the same wall or another one. They walk there and can't shoot meanwhile.
func move_survivor(i: int, side: int, u: float) -> Dictionary:
	if i < 0 or i >= crew.size():
		return {"msg": ""}
	var s: Dictionary = crew[i]
	if s["state"] != "wall" and s["state"] != "moving":
		return {"msg": s["name"] + " isn't on the wall right now."}
	var L: Dictionary = D.LANES[side]
	u = clampf(u, L["u0"] + 0.4, L["u1"] - 0.4)
	var here := Vector2(s["x"], s["y"])
	var target := lane_point(side, u, D.WALK_Y)
	if here.distance_to(target) < 0.15:
		return {"msg": ""}
	var route: Array = [here]
	if side != s["side"] or s["state"] == "moving" or s.has("post"):
		if on_deck(here) and s["state"] == "wall" and not s.has("post"):
			route.append(yard_point(s["side"], s["u"]))
		route.append(yard_point(side, u))
	route.append(target)
	s.erase("post")
	s["repairing"] = false
	_stop_fixing(s)
	s["side"] = side
	s["u"] = u
	s["route"] = route
	s["path_t"] = 0.0
	s["state"] = "moving"
	var who: String = "You head" if s["is_player"] else s["name"] + " heads"
	if not s["is_player"]:
		moved_crew = true
	return {"ok": true, "msg": "%s to the %s wall." % [who, L["name"].to_lower()]}


## True if p is inside the base (the yard, not out past the walls or fence).
static func in_base(p: Vector2) -> bool:
	return p.x > D.BASE_X0 + 0.5 and p.x < D.BASE_X1 - 0.5 and p.y > D.WALK_Y + 0.75 and p.y < D.BASE_Y1 - 0.4


## Sends a survivor to any spot in the yard. They still shoot from there, but
## need to be on a walkway to repair.
func move_survivor_to(i: int, p: Vector2) -> Dictionary:
	if i < 0 or i >= crew.size():
		return {"msg": ""}
	var s: Dictionary = crew[i]
	if s["state"] != "wall" and s["state"] != "moving":
		return {"msg": s["name"] + " isn't on the wall right now."}
	if not in_base(p):
		return {"msg": "That's outside the base."}
	var here := Vector2(s["x"], s["y"])
	var route: Array = [here]
	if on_deck(here) and s["state"] == "wall" and not s.has("post"):
		route.append(yard_point(s["side"], s["u"]))
	route.append(p)
	# The wall they're nearest counts as theirs (for facing and the bot).
	var best := 0
	var bd := INF
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var uv := lane_uv(side, p)
		var d := absf(uv.y - D.WALK_Y) + maxf(0.0, maxf(L["u0"] - uv.x, uv.x - L["u1"]))
		if d < bd:
			bd = d
			best = side
	s["post"] = p
	s["side"] = best
	s["u"] = clampf(lane_uv(best, p).x, D.LANES[best]["u0"] + 0.4, D.LANES[best]["u1"] - 0.4)
	s["repairing"] = false
	_stop_fixing(s)
	s["route"] = route
	s["path_t"] = 0.0
	s["state"] = "moving"
	if not s["is_player"]:
		moved_crew = true
	return {"ok": true, "msg": ("You head" if s["is_player"] else s["name"] + " heads") + " over there."}


## You, walking with the keys: dir is the way to go on the ground (x, y),
## any length up to 1. Anywhere in the yard or up on the walkways, round the
## buildings; not out past the walls or the fence.
func walk_player(dir: Vector2, dt: float, peer := 1) -> void:
	if crew.is_empty() or dir == Vector2.ZERO:
		return
	var s = me(peer)
	if s == null or not s["is_player"] or s["hp"] <= 0.0 or not s["state"] in ["wall", "moving"]:
		return
	if dir.length() > 1.0:
		dir = dir.normalized()
	var here := Vector2(s["x"], s["y"])
	# Facing one way and walking the other: a slower backpedal (a little
	# slower sideways, full pace forward).
	var facing := Vector2.from_angle(s["aim"])
	var back := smoothstep(0.0, -0.85, dir.normalized().dot(facing))
	var step := dir * D.PLAYER_SPEED * lerpf(1.0, D.BACKPEDAL, back) * dt
	var to := here + step
	if not walkable(to):
		# Slide along whatever's in the way.
		to = here + Vector2(step.x, 0.0)
		if not walkable(to):
			to = here + Vector2(0.0, step.y)
			if not walkable(to):
				return
	s["x"] = to.x
	s["y"] = to.y
	s["state"] = "wall"
	s["route"] = []
	s["repairing"] = false
	_stop_fixing(s)
	_take_spot(s, to)


## A player's character (peer 1 is the host; co-op friends have their own
## network ids), or null if they have none (they fell and were left behind).
func me(peer := 1) -> Variant:
	for s in crew:
		if s["is_player"] and s.get("peer", 1) == peer:
			return s
	return null


## Every player's character still standing.
func players_alive() -> Array:
	return crew.filter(func(s): return s["is_player"] and s["hp"] > 0.0 and s["state"] != "dead")


## A co-op friend joins: their own character on the wall, a pistol, the
## scout's look in their own colour. Returns it.
func add_player(peer: int, pname: String) -> Dictionary:
	var s := add_survivor(pname, "pistol", true)
	s["peer"] = peer
	s["skills"] = crew[0]["skills"].duplicate()   # the team's camp skills (the host has them)
	s["jacket"] = D.PLAYER_COLOURS[(peer * 7) % D.PLAYER_COLOURS.size()]
	inputs[peer] = {"aim": null, "firing": false}
	_changed()
	return s


## A co-op friend leaves: their character goes too.
func remove_player(peer: int) -> void:
	var s = me(peer)
	if s != null and peer != 1:
		crew.erase(s)
		inputs.erase(peer)
		_changed()


## Somewhere you can stand: the yard or a walkway, clear of buildings,
## turrets and the parked army truck.
func walkable(p: Vector2) -> bool:
	if not in_base(p) and not on_deck(p, 0.15):
		return false
	for r in D.BLOCKERS:
		if r.position == D.GATE_PATH.position:
			continue   # just kept clear for the gate
		if r.grow(0.15).has_point(p):
			return false
	for t in turrets:
		if Vector2(t["x"] - p.x, t["y"] - p.y).length() < 0.55:
			return false
	if evac >= 2.0 and evac_go < 0.0 and absf(p.x - TRUCK_STOP.x) < 1.25 and p.y > TRUCK_STOP.y - 3.2 and p.y < TRUCK_STOP.y + 3.2:
		return false
	return true


## Makes p a survivor's spot: on a walkway, that wall and place on it;
## in the yard, the wall they're nearest (for facing and the bot).
func _take_spot(s: Dictionary, p: Vector2) -> void:
	var spot := deck_spot(p)
	if on_deck(p) and not spot.is_empty():
		s.erase("post")
		s["side"] = spot["side"]
		s["u"] = spot["u"]
		return
	var best := 0
	var bd := INF
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var uv := lane_uv(side, p)
		var d := absf(uv.y - D.WALK_Y) + maxf(0.0, maxf(L["u0"] - uv.x, uv.x - L["u1"]))
		if d < bd:
			bd = d
			best = side
	s["post"] = p
	s["side"] = best
	s["u"] = clampf(lane_uv(best, p).x, D.LANES[best]["u0"] + 0.4, D.LANES[best]["u1"] - 0.4)


func free_name() -> String:
	var used := {}
	for s in crew:
		used[s["name"]] = true
	var pool: Array = []
	for n in D.NAMES:
		if not used.has(n):
			pool.append(n)
	if pool.size() > 0:
		return pool.pick_random()
	# Everyone's taken: the same names again, numbered.
	var n := 2
	while true:
		for nm in D.NAMES:
			if not used.has("%s %d" % [nm, n]):
				return "%s %d" % [nm, n]
		n += 1
	return "Sam"


# A survivor's effective numbers, from their role and the gear they carry.
func survivor_stats(s: Dictionary) -> Dictionary:
	var dmg: float = 1.0 if s["is_player"] else mods["crew_dmg"]
	var rate: float = 1.0 if s["is_player"] else 1.15 * mods["crew_rate"]
	var hollow := 0
	for g in s["gear"]:
		if g == null:
			continue
		match g["key"]:
			"hollow": hollow += 1
			"trigger": rate *= 0.85
	dmg *= 1.0 + 0.25 * hollow
	dmg *= D.skill_fx(s, "aim")
	rate *= D.skill_fx(s, "quick")
	if hungry:
		rate *= 1.0 + (D.HUNGRY_SLOWDOWN - 1.0) * research_mul("hunger")
	if hot_meal > 0.0:
		rate *= D.HOT_MEAL["rate"]
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	var per_shot: float = w["dmg"] * w["pellets"] * dmg
	var reload: float = w["reload"] * D.skill_fx(s, "quick")   # quick hands reload faster too
	# Damage a second over a whole magazine, reload included.
	var cycle: float = w["mag"] * w["rate"] * rate + reload
	return {
		"dmg": dmg, "rate": rate, "interval": w["rate"] * rate, "mag": int(w["mag"]), "reload": reload,
		"dps": int(round(per_shot * w["mag"] / cycle)),
	}


# --- Ammo -------------------------------------------------------------------
# Every gun holds a magazine (WEAPONS mag) and takes a while to reload (reload).
# A gun that's just been handed over comes loaded.
const TOP_UP_AFTER := 1.5     # seconds with nothing to shoot before topping up the magazine


## Makes sure a survivor's ammo matches the gun they're holding.
func _check_ammo(s: Dictionary) -> void:
	if s.get("ammo_for", "") != s["weapon"]:
		s["ammo_for"] = s["weapon"]
		s["ammo"] = int(D.WEAPONS[s["weapon"]]["mag"])
		s["reload"] = 0.0
		s["idle"] = 0.0


func is_reloading(s: Dictionary) -> bool:
	return s.get("reload", 0.0) > 0.0


## Starts a reload, unless they're already reloading or the magazine is full.
func start_reload(s: Dictionary) -> bool:
	_check_ammo(s)
	if is_reloading(s) or s["ammo"] >= int(D.WEAPONS[s["weapon"]]["mag"]) or not (s["state"] == "wall" or s.get("fighting", false)):
		return false
	var t: float = survivor_stats(s)["reload"]
	s["reload"] = t
	s["reload_max"] = t
	sound.emit("reload")
	# The spent magazine drops out.
	burst(s["x"], s["y"], 1, {"colors": [Color("2a2a2a")], "spread": 0.4, "up": 40.0, "life": 1.1, "size": 2.4, "z": 26.0})
	return true


const RACK_LEAD := 0.105   # seconds from the start of the reload sound to its slam

## Ticks a reload along; true while they're still busy reloading.
func _tick_reload(s: Dictionary, dt: float) -> bool:
	if not is_reloading(s):
		return false
	var before: float = s["reload"]
	s["reload"] -= dt
	# The rack-and-slam starts just early enough for the slam to land as
	# the gun's ready (Sfx's RACK_SLAM).
	if s["is_player"] and before > RACK_LEAD and s["reload"] <= RACK_LEAD:
		sound.emit("reloaded")
	if s["reload"] <= 0.0:
		s["reload"] = 0.0
		s["ammo"] = int(D.WEAPONS[s["weapon"]]["mag"])
		return false
	return true


## Fires at (x, y) and uses up a round; reloads when the magazine is empty.
func _shoot(s: Dictionary, x: float, y: float, k: Dictionary) -> void:
	fire(s, x, y, k["dmg"])
	s["cd"] = k["interval"]
	s["ammo"] -= 1
	s["idle"] = 0.0
	if s["ammo"] <= 0:
		start_reload(s)


# --- Zombies ----------------------------------------------------------------
func spawn_zombie(type: String, hp_mul: float, spd_mul: float, side := 0, v := -999.0) -> Dictionary:
	var T: Dictionary = ZT(type)
	var hp := roundf(T["hp"] * hp_mul)
	var L: Dictionary = D.LANES[side]
	# Fresh ones step out of one of the lane's sewer pipes, then spread out
	# across the lane (to u "tu") as they come.
	var from_pipe := v <= -900.0
	var u: float = L["u0"] + 0.4 + randf() * (L["u1"] - L["u0"] - 0.8)
	var tu := u
	if from_pipe:
		u = D.PIPES[side].pick_random() + randf_range(-0.45, 0.45)
		v = D.PIPE_SPAWN_V
	var at := lane_point(side, u, v)
	var z := {
		"id": zid, "type": type, "side": side, "u": 0.0, "v": 0.0,
		"x": at.x, "y": at.y,
		"hp": hp, "max_hp": hp, "spd": spd_mul * (0.9 + randf() * 0.2),
		"cd": randf() * T["rate"], "t": randf() * 10.0, "sway": randf() * TAU,
		"burn": 0.0, "hit": 0.0, "atk": 0.0, "held": 0.0, "slow": 1.0,
		"shirt": randi() % T["shirts"].size(), "groan": 2.0 + randf() * 10.0,
	}
	if from_pipe:
		z["tu"] = tu
	zid += 1
	zombies.append(z)
	return z


static func ZT(type: String) -> Dictionary:
	return D.ZTYPES[type]


## A zombie at a wall (side, u along it) does dmg to it.
func hit_wall(side: int, u: float, dmg: float) -> void:
	if over:
		return
	var w: Dictionary = walls[side]
	var L: Dictionary = D.LANES[side]
	w["hp"] -= dmg
	var seg := clampi(int(floor(u - L["u0"])), 0, w["hurt"].size() - 1)
	w["hurt"][seg] = 0.15
	var at := lane_point(side, u, D.WALL_Y - 0.05)
	burst(at.x, at.y, 3, {"colors": wall_mat()["chips"], "spread": 1.0, "up": 90.0, "life": 0.45, "size": 2.2, "z": 16.0})
	sound.emit("hit")
	if w["hp"] <= 0 and not w.get("breached", false):
		w["hp"] = 0.0
		w["breached"] = true
		# The gap: where it gave way, kept clear of the wall's ends.
		w["gap"] = clampf(u, L["u0"] + D.GAP_HALF, L["u1"] - D.GAP_HALF)
		shake = 1.0
		if evac_go < 0.0:   # (no warning once everyone's in the truck and away)
			toast.emit("The %s wall is down! They're getting in. Shoot them, or repair the gap to close it." % L["name"].to_lower(), "danger")
		for k in 6:
			var p := lane_point(side, u + (randf() - 0.5) * 3.0, D.WALL_Y)
			burst(p.x, p.y, 12, {"colors": wall_mat()["chips"], "spread": 3.0, "up": 180.0, "life": 1.0, "size": 4.0, "z": 18.0})
		sound.emit("crash")
		wall_breached.emit(side, u)


# --- Inside the base ----------------------------------------------------------
## People the dead can get at: everyone in the base or walking in it.
func defenders() -> Array:
	return crew.filter(func(s): return s["state"] in ["wall", "moving", "arriving", "returning", "boarding"] and s["hp"] > 0.0)


func any_breach() -> bool:
	for w in walls:
		if w.get("breached", false):
			return true
	return false


## A zombie that's got into the base hunts: the nearest person or turret for
## most, another one for a few (so they spread out), chosen again every second
## or so, and reached by a path around the buildings.
func _zombie_inside(z: Dictionary, T: Dictionary, dt: float) -> void:
	z["retarget"] = z.get("retarget", 0.0) - dt
	var best = z.get("prey", null)
	if best == null or z["retarget"] <= 0.0 or not _prey_alive(best):
		best = _choose_prey(z)
		z["prey"] = best
		z["retarget"] = randf_range(D.RETARGET.x, D.RETARGET.y)
		z.erase("path")
		var bid: int = best.get("id", -1) if best != null else -2
		if bid != z.get("approach_for", -3):
			z.erase("approach")   # a new target: a new way in
			z.erase("best_d")
			z["stall"] = 0.0
			z["approach_for"] = bid
	if best == null:
		return
	var tower: bool = turrets.has(best)
	var to := Vector2(best["x"] - z["x"], best["y"] - z["y"])
	var bd := to.length() - (0.35 if tower else 0.0)   # a tower's legs stand round it
	var reach: float = T["r"] + 0.45
	if bd > reach:
		var step: float = T["speed"] * z["spd"] * z["slow"] * 1.15 * dt
		var goal := _next_waypoint(z, _flank_goal(z, Vector2(best["x"], best["y"]), bd, dt))
		var dv := goal - Vector2(z["x"], z["y"])
		var dl := dv.length()
		if dl > 0.001:
			# Straight at the prey: stop at arm's length. Following a path: to the waypoint.
			var direct := goal.is_equal_approx(Vector2(best["x"], best["y"]))
			step = minf(step, (bd - reach) if direct else dl)
			z["x"] += dv.x / dl * step
			z["y"] += dv.y / dl * step
			z["face"] = atan2(dv.x, dv.y)
		return
	z["face"] = atan2(to.x, to.y)
	z["cd"] -= dt
	if z["cd"] <= 0.0:
		z["cd"] = T["rate"]
		z["atk"] = 0.25
		sound.emit("snarl")
		if tower:
			hurt_turret(best, T["dmg"])
		else:
			hurt_survivor(best, T["dmg"] * D.BITE)


## Where a zombie inside heads for on its way to its target at prey: while
## it's still some way off, a point out to its own side of the target (each
## has its own side and how far: z["flank"], -1..1), closing in as it nears,
## so a pack fans out round the buildings and comes at you from all sides
## instead of queueing up the same path. Up close, the target itself.
func _flank_goal(z: Dictionary, prey: Vector2, dist: float, dt: float) -> Vector2:
	if dist < D.FLANK_CLOSE:
		return prey
	if not z.has("flank"):
		z["flank"] = randf_range(-1.0, 1.0)
	# Not getting any closer (hemmed in round a corner)? Then straight for them.
	if dist < z.get("best_d", INF) - 0.2:
		z["best_d"] = dist
		z["stall"] = 0.0
	else:
		z["stall"] = z.get("stall", 0.0) + dt
	if z["stall"] > 2.5:
		return prey
	# A spot on a ring round the target, turned off its own bearing by its own
	# angle (up to FLANK_TURN either way): it comes at you from there. The ring
	# shrinks as it closes in. Blocked or outside? Turn less, same side.
	var p := Vector2(z["x"], z["y"])
	var back := (p - prey) / maxf(dist, 0.001)
	if not z.has("approach"):
		# Set when it picks its target (cleared on choosing again): a fixed
		# bearing, so it closes in from there rather than circling.
		z["approach"] = back.angle() + z["flank"] * D.FLANK_TURN
	var r := minf((dist - D.FLANK_CLOSE) * D.FLANK + D.FLANK_CLOSE * 0.6, D.FLANK_MAX)
	var straight := back.angle()
	for k in 3:   # turned less...
		var ang: float = lerp_angle(straight, z["approach"], [1.0, 0.6, 0.3][k])
		for rk: float in [1.0, 0.65, 0.4]:   # ...or nearer in
			var g := prey + Vector2.from_angle(ang) * r * rk
			if (in_base(g) or on_deck(g)) and not _blocked(g):
				return g
	return prey


## Somewhere the dead can't stand (the same as their paths go round)?
static func _blocked(p: Vector2) -> bool:
	for blk in D.BLOCKERS:
		if blk.position != D.GATE_PATH.position and blk.grow(0.3).has_point(p):
			return true
	return false


## Who a zombie inside goes for: usually whatever's nearest (person or turret);
## for a share of them, the second or third nearest instead.
func _choose_prey(z: Dictionary):
	var cands: Array = []
	var p := Vector2(z["x"], z["y"])
	for s in defenders():
		cands.append([p.distance_to(Vector2(s["x"], s["y"])), s])
	for t in turrets:
		cands.append([p.distance_to(Vector2(t["x"], t["y"])) - 0.35, t])
	if cands.is_empty():
		return null
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var k := 0
	if cands.size() > 1 and randf() < D.SPREAD_CHANCE:
		k = randi_range(1, mini(2, cands.size() - 1))
	return cands[k][1]


func _prey_alive(p: Dictionary) -> bool:
	if turrets.has(p):
		return true
	return crew.has(p) and p["hp"] > 0.0 and p["state"] in ["wall", "moving", "arriving", "returning", "boarding"]


# --- Paths inside the base ------------------------------------------------------
# A grid over the base (and a strip outside each wall, where the dead come in),
# with the buildings blocked out. Straight at the target when nothing's in the
# way; otherwise A* round the buildings, recomputed when they choose again.
const NAV_CELL := 0.5
const NAV_AREA := Rect2(-1.0, 12.0, 24.0, 17.0)
static var _nav: AStarGrid2D


static func nav() -> AStarGrid2D:
	if _nav == null:
		_nav = AStarGrid2D.new()
		_nav.region = Rect2i(0, 0, int(NAV_AREA.size.x / NAV_CELL), int(NAV_AREA.size.y / NAV_CELL))
		_nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
		_nav.offset = NAV_AREA.position + Vector2(NAV_CELL, NAV_CELL) * 0.5
		_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_nav.update()
		for blk in D.BLOCKERS:
			if blk.position == D.GATE_PATH.position:
				continue   # only kept clear for the truck: the dead walk over it
			var r: Rect2 = blk.grow(0.3)
			for cx in range(int((r.position.x - NAV_AREA.position.x) / NAV_CELL), int(ceil((r.end.x - NAV_AREA.position.x) / NAV_CELL))):
				for cy in range(int((r.position.y - NAV_AREA.position.y) / NAV_CELL), int(ceil((r.end.y - NAV_AREA.position.y) / NAV_CELL))):
					if _nav.is_in_boundsv(Vector2i(cx, cy)):
						_nav.set_point_solid(Vector2i(cx, cy))
	return _nav


static func _nav_cell(p: Vector2) -> Vector2i:
	var c := Vector2i(((p - NAV_AREA.position) / NAV_CELL).floor())
	return c.clamp(Vector2i.ZERO, nav().region.size - Vector2i.ONE)


## True if the straight line from a to b crosses no building.
static func clear_line(a: Vector2, b: Vector2) -> bool:
	for blk in D.BLOCKERS:
		if blk.position == D.GATE_PATH.position:
			continue   # only kept clear for the truck
		var r: Rect2 = blk.grow(0.3)   # a body's width round each building
		# Slab test of the segment against the rectangle.
		var t0 := 0.0
		var t1 := 1.0
		var d := b - a
		var hit := true
		for ax in 2:
			var lo: float = r.position[ax]
			var hi: float = r.end[ax]
			if absf(d[ax]) < 0.00001:
				if a[ax] < lo or a[ax] > hi:
					hit = false
					break
			else:
				var ta := (lo - a[ax]) / d[ax]
				var tb := (hi - a[ax]) / d[ax]
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
				if t0 > t1:
					hit = false
					break
		if hit:
			return false
	return true


## The open cell nearest c (c itself if it's open).
static func _free_near(c: Vector2i) -> Vector2i:
	var a := nav()
	if not a.is_point_solid(c):
		return c
	for rr in range(1, 6):
		for dx in range(-rr, rr + 1):
			for dy in range(-rr, rr + 1):
				var n := c + Vector2i(dx, dy)
				if a.is_in_boundsv(n) and not a.is_point_solid(n):
					return n
	return c


## Where a zombie inside should head next on its way to goal.
func _next_waypoint(z: Dictionary, goal: Vector2) -> Vector2:
	var p := Vector2(z["x"], z["y"])
	if clear_line(p, goal):
		z.erase("path")
		return goal
	if not z.has("path"):
		var a := nav()
		# Brushing a building's corner, or the target right by one: use the
		# nearest open cell.
		var from := _free_near(_nav_cell(p))
		var to := _free_near(_nav_cell(goal))
		var pts := a.get_point_path(from, to, true)
		z["path"] = Array(pts)
	var path: Array = z["path"]
	# Skip ahead to the furthest waypoint in plain sight.
	while path.size() > 1 and clear_line(p, path[1]):
		path.pop_front()
	if path.is_empty():
		return goal
	if p.distance_to(path[0]) < 0.25:
		path.pop_front()
		if path.is_empty():
			return goal
	return path[0]


func hurt_survivor(s: Dictionary, dmg: float) -> void:
	if s["hp"] <= 0.0:
		return
	s["hp"] -= dmg
	s["hurt"] = 0.2
	s["repairing"] = false
	_stop_fixing(s)
	burst(s["x"], s["y"], 4, {"colors": [Color("6a2a22"), Color("8a3a2c")], "spread": 0.8, "up": 70.0, "life": 0.4, "size": 2.2, "z": 24.0})
	sound.emit("hit")
	if s["hp"] <= 0.0:
		_kill_survivor(s)


func _kill_survivor(s: Dictionary) -> void:
	s["hp"] = 0.0
	burst(s["x"], s["y"], 14, {"colors": [Color("5a2a26"), Color("7a3a2c")], "spread": 2.0, "up": 120.0, "life": 0.8, "size": 2.8, "z": 20.0})
	sound.emit("die")
	if s["is_player"]:
		s["state"] = "dead"   # you stay where you fell; the crew fights on
		toast.emit("You're down. The crew fights on without you.", "danger")
	else:
		crew.erase(s)
		toast.emit("%s has been killed." % s["name"], "danger")
		_changed()
	survivor_killed.emit(s["name"])


## Survivors get their breath back when no zombie is near; the run ends
## once a breach has let the dead in and nobody in the base is left alive.
func update_health(dt: float) -> void:
	for s in crew:
		s["hurt"] = maxf(0.0, s.get("hurt", 0.0) - dt)
		if s["hp"] <= 0.0 or s["hp"] >= s["max_hp"]:
			continue
		var clear := true
		for z in zombies:
			if z.get("inside", false) and Vector2(z["x"] - s["x"], z["y"] - s["y"]).length() < D.HEAL_CLEAR:
				clear = false
				break
		if clear:
			s["hp"] = minf(s["max_hp"], s["hp"] + D.HEAL_PER_SECOND * dt)
	# (Anyone already in the army truck is safe: it'll drive off with them.)
	var aboard := crew.any(func(c): return c["state"] == "aboard")
	if not over and not aboard and defenders().is_empty() and (any_breach() or players_alive().is_empty()):
		over = true
		shake = 1.0
		sound.emit("crash")


## Shoves a zombie back down its lane, away from the wall.
func knock_back(z: Dictionary, d: float) -> void:
	if d <= 0.0 or z["type"] == "brute":
		return
	var n: Vector2 = D.LANES[z["side"]]["n"]
	var uv := lane_uv(z["side"], Vector2(z["x"], z["y"]))
	var back := minf(d, maxf(0.0, uv.y - D.LANE_START))
	z["x"] -= n.x * back
	z["y"] -= n.y * back


func update_zombies(dt: float) -> void:
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
			sound.emit("groan_" + z["type"])

		if z.get("inside", false):
			_zombie_inside(z, T, dt)
			continue
		var front: float = D.WALL_Y - T["r"]
		var L: Dictionary = D.LANES[z["side"]]
		var uv := lane_uv(z["side"], Vector2(z["x"], z["y"]))
		var broken: bool = walls[z["side"]].get("breached", false)
		if z["held"] > 0:
			z["held"] -= dt  # caught in a bear trap
		elif broken:
			# Make for the gap and squeeze through it: the rest of the wall still
			# stands, so those beside it shuffle along the wall to the hole.
			var gap: float = walls[z["side"]].get("gap", uv.x)
			var r: float = T["r"]
			var lo := gap - D.GAP_HALF + r
			var hi := gap + D.GAP_HALF - r
			var in_gap := uv.x >= lo - 0.05 and uv.x <= hi + 0.05
			var aim := Vector2(clampf(uv.x, lo + 0.25, hi - 0.25), D.WALL_Y + 1.0)
			if not in_gap and uv.y > front - 1.2:
				aim.y = front   # along the wall to the hole, not into the wall
			var dv := aim - uv
			var step: float = T["speed"] * z["spd"] * z["slow"] * dt
			uv += dv.normalized() * minf(step, dv.length())
			if not in_gap:
				uv.y = minf(uv.y, front)
			if in_gap and uv.y >= D.WALL_Y - 0.3:
				z["inside"] = true   # through the gap: from here they hunt (see _zombie_inside)
		elif uv.y < front - 0.01:
			var slow: float = z["slow"]
			var step: float = minf(front, uv.y + T["speed"] * z["spd"] * slow * dt) - uv.y
			if z.has("tu"):
				# Fanning out from the pipe: walk on a slant toward their spot across
				# the lane, at their normal pace (no sidestepping), facing that way.
				var go := Vector2(clampf(z["tu"] - uv.x, -1.0, 1.0), 1.3).normalized() * step   # at most ~37° off the lane
				uv.x += go.x
				step = go.y
				var w: Vector2 = L["t"] * go.x + L["n"] * go.y
				z["face"] = atan2(w.x, w.y)
				if absf(uv.x - z["tu"]) < 0.05:
					z.erase("tu")
					z.erase("face")
			else:
				uv.x += sin(z["t"] * 0.8 + z["sway"]) * 0.18 * dt * slow
			uv.y += step
		else:
			uv.y = front
			if z.has("tu"):   # at the wall: done fanning out, face it square
				z.erase("tu")
				z.erase("face")
			z["cd"] -= dt
			if z["cd"] <= 0:
				z["cd"] = T["rate"]
				z["atk"] = 0.25
				if randf() < 0.35:
					sound.emit("snarl")
				# A turret close behind the wall gets clawed at instead.
				var tt = turret_near(lane_point(z["side"], uv.x, D.WALL_Y), D.TURRET_REACH)
				if tt != null:
					hurt_turret(tt, T["dmg"])
				else:
					hit_wall(z["side"], uv.x, T["dmg"])
		var p := lane_point(z["side"], uv.x, uv.y)
		z["x"] = p.x
		z["y"] = p.y

	# Separation so the crowd piles up along the wall instead of stacking.
	# Each zombie is only checked against those in its own and the eight
	# neighbouring 1 m cells (no two are ever pushed apart from further than
	# 0.71 m), not against every other zombie: a big horde stays cheap.
	var n := zombies.size()
	var cells := {}
	for i in n:
		var c := Vector2i(floori(zombies[i]["x"]), floori(zombies[i]["y"]))
		if cells.has(c):
			cells[c].append(i)
		else:
			cells[c] = [i]
	for i in n:
		var a: Dictionary = zombies[i]
		var ra: float = ZT(a["type"])["r"]
		var ca := Vector2i(floori(a["x"]), floori(a["y"]))
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				var near = cells.get(ca + Vector2i(ox, oy))
				if near == null:
					continue
				for j in near:
					if j <= i:
						continue   # each pair once, as before
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
	# Keep everyone inside their lane and in front of its wall (unless the
	# wall is down, or they're already in).
	for z in zombies:
		var r: float = ZT(z["type"])["r"]
		var L: Dictionary = D.LANES[z["side"]]
		var uv := lane_uv(z["side"], Vector2(z["x"], z["y"]))
		if z.get("inside", false):
			z["u"] = uv.x
			z["v"] = uv.y
			continue
		uv.x = clampf(uv.x, L["u0"] + r, L["u1"] - r)
		var wl: Dictionary = walls[z["side"]]
		if not wl.get("breached", false) or absf(uv.x - wl.get("gap", uv.x)) > D.GAP_HALF - r:
			uv.y = minf(uv.y, D.WALL_Y - r)   # only the gap lets them through
		var p := lane_point(z["side"], uv.x, uv.y)
		z["x"] = p.x
		z["y"] = p.y
		z["u"] = uv.x
		z["v"] = uv.y
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
		if kill_scrap > 0:
			scrap += kill_scrap * (2 if z["type"] == "brute" else 1)
		zombie_died.emit(z["x"], z["y"], z["type"])
		burst(z["x"], z["y"], 10 + int(round(T["scale"] * 6)), {"colors": [Color("5a2a26"), Color("7a3a2c"), T["skin"]], "spread": 2.2, "up": 130.0, "life": 0.8, "size": 2.6 * T["scale"], "z": 14.0 * T["scale"]})
		sound.emit("zdie")


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
		var score: float = lane_uv(z["side"], Vector2(z["x"], z["y"])).y + (1.5 if z["type"] == "brute" else 0.0)
		if score > by:
			by = score
			best = z
	return best


const BULLET_SPEED := 70.0        # metres a second (a gun can set its own)
const BULLETS_MAX := 400           # in flight at once; past that the oldest go
const BULLET_AIM_H := 1.05         # bullets drop toward this height at the aimed distance (a chest)
const MUZZLE_UP := 1.41            # the muzzle's height above a shooter's feet (a pistol's; weapons set their own)
const MUZZLE_SIDE := -0.05         # and how far it's off to the side of their aim
const TURRET_MUZZLE := Vector2(0.88, 2.0)   # a turret's: forward, height
const SHOT_MAX := 90.0  # how far a bullet flies (the whole map: no range cap)
const AUTO_REACH := 1.5 # auto-fire takes on targets out to this many times a gun's reach
const AUTO_REACH_STEADY := 3.0   # (or this, for a gun that holds its aim, like the rifle)


## How much wider a gun's spread is at distance d: no worse up to half its
## reach, then steadily worse (not at all for a gun with no falloff).
static func spread_mul(w: Dictionary, d: float) -> float:
	return 1.0 + w.get("falloff", 1.0) * maxf(0.0, d / w["range"] - 0.5)


const NPC_AIM_SLOP := 0.3        # metres a crewmate's aim strays, like a hand on a mouse...
const NPC_AIM_SLOP_PER_M := 0.035 # ...and more per metre out

## A crewmate's aim is human, not perfect: where they put their sights is
## off the zombie by a random amount (more for further, moving targets), on
## top of the gun's own spread, so they hit about as often as a player does.
static func npc_aim_error(s: Dictionary, z: Dictionary) -> Vector2:
	var d := Vector2(z["x"] - s["x"], z["y"] - s["y"]).length()
	var r := (NPC_AIM_SLOP + NPC_AIM_SLOP_PER_M * d) * (2.0 - D.skill_fx(s, "aim"))
	return Vector2(randfn(0.0, r), randfn(0.0, r))


## How far auto-fire (crew, not turrets) will reach out with gun w.
static func auto_reach(w: Dictionary) -> float:
	return w["range"] * (AUTO_REACH_STEADY if w.get("falloff", 1.0) <= 0.0 else AUTO_REACH)


func fire(s: Dictionary, tx: float, ty: float, dmg_mul: float, w = null) -> void:
	if w == null:
		w = D.WEAPONS[s["weapon"]]
	var ang := atan2(ty - s["y"], tx - s["x"])
	s["aim"] = ang
	s["flash"] = 0.06
	s["recoil"] = 0.1
	sound.emit(w["sound"])
	var mz := muzzle_point(s, w, ang)
	var dist := Vector2(tx - mz.x, ty - mz.z).length()
	if dist > 0.3:
		ang = atan2(ty - mz.z, tx - mz.x)   # from the barrel's end, so a true shot meets the mark
	var wide := spread_mul(w, dist) * (2.0 - D.skill_fx(s, "aim"))   # (as aim_spread)
	if w.has("splash"):
		# Lobbed: further out it lands wider of the mark, and long or short.
		var ga: float = ang + (randf() * 2.0 - 1.0) * w["spread"] * wide
		var d := dist * (1.0 + (randf() * 2.0 - 1.0) * 0.06 * (wide - 1.0))
		shots.append({"kind": "grenade", "x0": mz.x, "y0": mz.z, "h0": mz.y, "x1": mz.x + cos(ga) * d, "y1": mz.z + sin(ga) * d,
			"t": 0.0, "dur": 0.25 + d / 12.0, "dmg": w["dmg"] * dmg_mul, "splash": w["splash"]})
		return
	# Real bullets: out of the barrel, flying on until they hit (see update_bullets).
	# They drop from the muzzle toward a body's chest height at the aimed distance.
	# Heights are world heights (not over the ground below), so a bullet flies
	# dead straight over the lanes' rolls instead of bobbing along them.
	var h0 := mz.y + Terrain.sample(s["x"], s["y"])
	# At a zombie: its chest. At bare ground: the ground itself, so a miss
	# kicks up dirt right where you aimed.
	var at_body := false
	for z in zombies:
		if z["hp"] > 0 and Vector2(z["x"] - tx, z["y"] - ty).length() < ZT(z["type"])["r"] + 0.45:
			at_body = true
			break
	var aim_h := (BULLET_AIM_H if at_body else 0.0) + Terrain.sample(tx, ty)
	var drop := (aim_h - h0) / maxf(dist, 0.5)
	var width: float = 1.0 if w["pellets"] > 1 else (2.4 if s.get("weapon", "") == "rifle" else 1.6)
	for p in int(w["pellets"]):
		var a: float = ang + (randf() * 2.0 - 1.0) * w["spread"] * wide
		bullets.append({"x": mz.x, "y": mz.z, "h": h0, "drop": drop, "dx": cos(a), "dy": sin(a),
			"speed": w.get("bullet_speed", BULLET_SPEED) * randf_range(0.95, 1.05), "flown": 0.0,
			"dmg": w["dmg"] * dmg_mul, "pierce": int(w["pierce"]), "knock": w["knock"], "hit": {}, "w": width})
	if bullets.size() > BULLETS_MAX:
		bullets = bullets.slice(bullets.size() - BULLETS_MAX)


## How far off (radians, either side) a shot from s at a point dist away
## can stray: the gun's spread, worse with distance, better with aim skill.
## (The reticle's ticks show this.)
static func aim_spread(s: Dictionary, dist: float) -> float:
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	return w["spread"] * spread_mul(w, dist) * (2.0 - D.skill_fx(s, "aim"))


## A bullet striking the ground: a small kick of dirt and grit.
func _ground_puff(x: float, y: float) -> void:
	burst(x, y, 6, {"colors": [Color("6b5a44"), Color("8a7458"), Color("4f4232")], "spread": 0.9, "up": 70.0, "life": 0.5, "size": 2.2, "z": 1.0, "grav": 260.0})
	burst(x, y, 3, {"colors": [Color(0.5, 0.45, 0.37), Color(0.44, 0.4, 0.33)], "spread": 0.4, "up": 26.0, "life": 0.8, "size": 4.2, "z": 1.0, "grav": 10.0})


## Where a shot leaves the gun (x, height, y in metres): the end of the
## barrel, measured off the models (survivor.gd's muzzle, turret.gd's).
static func muzzle_point(s: Dictionary, w: Dictionary, ang: float) -> Vector3:
	var fwd := Vector2(cos(ang), sin(ang))
	var side := Vector2(-fwd.y, fwd.x)
	var p := Vector2(s["x"], s["y"])
	if not s.has("is_player"):
		# A turret: the bore, up on its tower.
		p += fwd * TURRET_MUZZLE.x
		return Vector3(p.x, TURRET_MUZZLE.y, p.y)
	p += fwd * w.get("muzzle", 0.9) + side * w.get("muzzle_side", MUZZLE_SIDE)
	var ground := D.DECK_H if on_deck(Vector2(s["x"], s["y"])) else 0.0
	return Vector3(p.x, ground + w.get("muzzle_up", MUZZLE_UP), p.y)


## Moves every bullet in flight; each hits the zombies in its path in turn,
## up to its pierce, and flies on until it's spent.
func update_bullets(dt: float) -> void:
	for b in bullets:
		var step: float = b["speed"] * dt
		var dx: float = b["dx"]
		var dy: float = b["dy"]
		var hits: Array = []
		for z in zombies:
			if z["hp"] <= 0 or b["hit"].has(z["id"]):
				continue
			var rx: float = z["x"] - b["x"]
			var ry: float = z["y"] - b["y"]
			var t := rx * dx + ry * dy
			if t < -0.3 or t > step:
				continue
			if absf(rx * dy - ry * dx) < ZT(z["type"])["r"] + 0.1:
				hits.append([t, z])
		hits.sort_custom(func(a1, b1): return a1[0] < b1[0])
		var moved := step
		for h in hits:
			var z: Dictionary = h[1]
			b["hit"][z["id"]] = true
			damage(z, b["dmg"])
			if z["type"] != "brute":
				knock_back(z, b["knock"])
			burst(z["x"], z["y"], 2, {"colors": [Color("6a2a22"), Color("8a3a2c")], "spread": 1.0, "up": 60.0, "life": 0.35, "size": 2.0, "z": 16.0})
			b["pierce"] -= 1
			if b["pierce"] <= 0:
				moved = maxf(0.0, h[0])
				b["done"] = true
				break
		b["x"] += dx * moved
		b["y"] += dy * moved
		b["flown"] += moved
		b["h"] += b["drop"] * moved
		if not b.has("done") and b["h"] <= Terrain.sample(b["x"], b["y"]):
			# Into the dirt: a little puff where it lands.
			b["done"] = true
			_ground_puff(b["x"], b["y"])
		elif b["flown"] >= SHOT_MAX:
			b["done"] = true
	bullets = bullets.filter(func(b): return not b.has("done"))


## Turns a shooter's aim toward want at rate (radians a second). True once
## it's lined up closely enough to fire.
static func swivel(s: Dictionary, want: float, rate: float, dt: float) -> bool:
	var diff := wrapf(want - s["aim"], -PI, PI)
	var turn := clampf(diff, -rate * dt, rate * dt)
	s["aim"] = wrapf(s["aim"] + turn, -PI, PI)
	return absf(diff - turn) <= D.AIM_TOLERANCE


func update_crew(dt: float) -> void:
	for s in crew:
		s["flash"] = maxf(0.0, s["flash"] - dt)
		s["recoil"] = maxf(0.0, s["recoil"] - dt)
		if s["state"] != "wall":
			continue
		s["cd"] -= dt
		_check_ammo(s)
		if _tick_reload(s, dt):
			continue
		if s.get("repairing", false) or s.get("fixing", false):
			continue
		var w: Dictionary = D.WEAPONS[s["weapon"]]
		var k := survivor_stats(s)
		s["idle"] = s.get("idle", 0.0) + dt

		if s["is_player"]:
			# Holding the mouse aims at the cursor; otherwise you face the cursor.
			# (input_auto is the test bots' stand-in: it shoots on its own.)
			var peer: int = s.get("peer", 1)
			var aim_at = input_aim if peer == 1 else inputs.get(peer, {}).get("aim", null)
			var firing: bool = input_firing if peer == 1 else inputs.get(peer, {}).get("firing", false)
			var manual: bool = firing and aim_at != null
			var target = null
			var lined_up := false
			if not manual and input_auto and peer == 1:
				target = auto_target(s, auto_reach(w))
				if target != null:
					lined_up = swivel(s, atan2(target["y"] - s["y"], target["x"] - s["x"]), D.TURN_RATE, dt)
			elif aim_at != null:
				lined_up = swivel(s, atan2(aim_at.y - s["y"], aim_at.x - s["x"]), D.TURN_RATE_MANUAL, dt)
			s["auto_target"] = target["id"] if target != null else -1
			if manual or target != null:
				s["idle"] = 0.0
			elif s["idle"] > TOP_UP_AFTER:
				start_reload(s)   # nothing to shoot: top the magazine up
			if s["cd"] > 0 or not lined_up:
				continue
			if manual:
				_shoot(s, aim_at.x, aim_at.y, k)
			elif target != null:
				_shoot(s, target["x"], target["y"], k)
		else:
			var z = _lob_target(s, w, dt) if w.has("splash") else auto_target(s, auto_reach(w))
			if z == null:
				if s["idle"] > TOP_UP_AFTER:
					start_reload(s)   # nothing to shoot: top the magazine up
				continue
			s["idle"] = 0.0
			var ready := swivel(s, atan2(z["y"] - s["y"], z["x"] - s["x"]), D.TURN_RATE, dt)
			if s["cd"] <= 0 and ready:
				var miss := npc_aim_error(s, z)
				_shoot(s, z["x"] + miss.x, z["y"] + miss.y, k)
				s["lob"] = -1   # (a launcher picks a fresh bunch for the next one)


## A launcher's pick, looked for again a few times a second (it's a costly
## search through a big horde), and dropped once its grenade is away.
func _lob_target(s: Dictionary, w: Dictionary, dt: float) -> Variant:
	s["lob_t"] = s.get("lob_t", 0.0) - dt
	var z = null
	var id: int = s.get("lob", -1)
	if id >= 0 and s["lob_t"] > 0.0:
		for o in zombies:
			if o["id"] == id and o["hp"] > 0:
				z = o
				break
	if z == null:
		z = splash_target(s, auto_reach(w), w["splash"])
		s["lob"] = z["id"] if z != null else -1
		s["lob_t"] = 0.25
	return z


## Where a crewmate with a launcher lobs next: the thickest knot of the dead
## in reach, but never one a grenade in the air is already coming down on
## (theirs or anyone's), so two of them don't both shell the same bunch.
func splash_target(s: Dictionary, rng: float, splash: float) -> Variant:
	var taken: Array[Vector2] = []
	for sh in shots:
		if sh["kind"] == "grenade" and sh["t"] < sh["dur"]:
			taken.append(Vector2(sh["x1"], sh["y1"]))
	var best = null
	var bs := -INF
	for z in zombies:
		if z["hp"] <= 0:
			continue
		var p := Vector2(z["x"], z["y"])
		if p.distance_squared_to(Vector2(s["x"], s["y"])) > rng * rng:
			continue
		var skip := false
		for t in taken:
			if p.distance_to(t) < splash * 1.5:
				skip = true
				break
		if skip:
			continue
		var n := 0.0
		for o in zombies:
			if o["hp"] > 0 and p.distance_squared_to(Vector2(o["x"], o["y"])) < splash * splash:
				n += 1.0
		var score: float = n * 2.0 + lane_uv(z["side"], p).y * 0.1 + (1.5 if z["type"] == "brute" else 0.0)
		if score > bs:
			bs = score
			best = z
	return best


func crowd_centre() -> Variant:
	var best = null
	var bn := 0.0
	for z in zombies:
		var v: float = lane_uv(z["side"], Vector2(z["x"], z["y"])).y
		if v < 4:
			continue
		var n := 0.0
		for o in zombies:
			if pow(o["x"] - z["x"], 2) + pow(o["y"] - z["y"], 2) < 2.2:
				n += 1.0
		n += v / 20.0
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
		# (The flames themselves are the fire scene's own: scenes/fx/fire.tscn,
		# the same as the fire barrel in the yard.)
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
				knock_back(z, 0.3 * (1.0 - d / splash))
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


## True if (x, y) is open ground in front of a wall whose lane is open.
func trap_ground(x: float, y: float) -> bool:
	var side := field_side(Vector2(x, y), 0.5)
	if side < 0 or not sides_open[side]:
		return false
	var v := lane_uv(side, Vector2(x, y)).y
	return v >= D.LANE_START + 1.0 and v <= D.WALL_Y - 0.7


func can_place_trap(x: float, y: float, ignore_uid := -1) -> Dictionary:
	if not trap_ground(x, y):
		return {"msg": "Traps go on open ground in front of a wall."}
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
	if it["key"] == "wire" and traps.filter(func(t): return t["key"] == "wire").size() >= D.WIRE_LIMIT:
		return {"msg": "Only %d coils of wire can be out at once." % D.WIRE_LIMIT}
	items.remove_at(i)
	traps.append({"uid": it["uid"], "key": it["key"], "x": x, "y": y, "uses": it["uses"], "max": float(D.ITEMS[it["key"]]["uses"]), "hold": -1, "rearm": 0.0, "t": 0.0,
		"dir": _strip_dir(x, y)})
	_changed()
	sound.emit("build")
	return {"ok": true}


## Coils of wire: out on the ground and in storage.
func wire_count() -> int:
	return traps.filter(func(t): return t["key"] == "wire").size() + storage["items"].filter(func(it): return it["key"] == "wire").size()


## Which way a strip trap lies at (x, y): along the wall of the lane it's in.
func _strip_dir(x: float, y: float) -> Vector2:
	var side := field_side(Vector2(x, y), 0.5)
	return Vector2(D.LANES[maxi(side, 0)]["t"])


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
	t["dir"] = _strip_dir(x, y)
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
	var d := Vector2(z["x"] - t["x"], z["y"] - t["y"])
	var r: float = ZT(z["type"])["r"] * 0.6
	if D.TRAP_SIZE.has(t["key"]):
		# A strip across the lane: a rectangle.
		var a: Vector2 = t.get("dir", Vector2.RIGHT)
		var size: Vector2 = D.TRAP_SIZE[t["key"]]
		return absf(d.dot(a)) < size.x * 0.5 + r and absf(d.dot(Vector2(-a.y, a.x))) < size.y * 0.5 + r
	return d.length() < D.TRAP_R[t["key"]] + r


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
			"wire":
				for z in zombies:
					if z["hp"] <= 0 or not _within(z, t):
						continue
					damage(z, 7.0 * dt, true)
					z["slow"] = minf(z["slow"], 0.4)
					t["uses"] -= dt * (2.0 if z["type"] == "brute" else 1.0)
					if randf() < dt * 3.0:
						burst(z["x"], z["y"], 1, {"colors": [Color("6a2a22")], "spread": 0.5, "up": 40.0, "life": 0.3, "size": 1.8, "z": 6.0})
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
			return {"msg": "That gets used from storage, not carried." if kind == "supply" or kind == "throw" else "Only guns go in the weapon slot."}
		return {"ok": true}
	if kind != "mod":
		return {"msg": "That gets used from storage, not carried." if kind == "supply" or kind == "throw" else "Only gear goes in these slots: hollow points and hair triggers."}
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
	_changed()
	return {"ok": true}


func use_supply(i: int) -> Dictionary:
	var items: Array = storage["items"]
	if i >= items.size() or D.item_kind(items[i]["key"]) != "supply":
		return {"msg": ""}
	var it: Dictionary = items[i]
	sound.emit("build")
	items.remove_at(i)
	_changed()
	return {"ok": true, "msg": D.item_name(it["key"]) + " used."}


## Index in storage of the item with this uid, or -1.
func storage_index(item_uid: int) -> int:
	var items: Array = storage["items"]
	for i in items.size():
		if items[i]["uid"] == item_uid:
			return i
	return -1


## Throws a molotov or pipe bomb from storage at (x, y). Whoever is on a wall
## nearest the spot throws it; it's used up.
func throw_item(item_uid: int, x: float, y: float) -> Dictionary:
	var i := storage_index(item_uid)
	if i < 0 or D.item_kind(storage["items"][i]["key"]) != "throw":
		return {"msg": ""}
	var key: String = storage["items"][i]["key"]
	var target := Vector2(x, y)
	var best = null
	var bd := INF
	for s in crew:
		if s["state"] != "wall":
			continue
		var d := target.distance_to(Vector2(s["x"], s["y"]))
		if d < bd:
			bd = d
			best = s
	if best == null:
		return {"msg": "Nobody on the walls to throw it."}
	if bd > D.THROW_RANGE:
		return {"msg": "Too far to throw from any wall."}
	storage["items"].remove_at(i)
	var dur := 0.35 + bd / 14.0
	best["aim"] = atan2(y - best["y"], x - best["x"])
	if key == "molotov":
		shots.append({"kind": "molotov", "x0": best["x"], "y0": best["y"], "x1": x, "y1": y, "t": 0.0, "dur": dur})
	else:
		shots.append({"kind": "grenade", "x0": best["x"], "y0": best["y"], "x1": x, "y1": y, "t": 0.0, "dur": dur,
			"dmg": D.PIPEBOMB["dmg"], "splash": D.PIPEBOMB["splash"]})
	sound.emit("launch")
	_changed()
	return {"ok": true}


# --- Tearing things down ----------------------------------------------------
## Scrap you get for breaking an item down: about 40% of what it costs to build.
static func salvage_value(key: String) -> int:
	if D.SHOP.has(key):
		return maxi(3, int(round(D.SHOP[key]["cost"] * D.SALVAGE_SHARE)))
	return 4   # the pistol, which you can't buy


## Breaks down the item at a storage or gear slot for scrap.
func salvage(loc: Dictionary) -> Dictionary:
	var it = item_at(loc)
	if it == null:
		return {"msg": ""}
	if loc["where"] == "weapon":
		return {"msg": "Everyone keeps a gun. Swap it for another first."}
	if loc["where"] == "gear" and crew[loc["s"]]["state"] != "wall":
		return {"msg": crew[loc["s"]]["name"] + " isn't on the wall right now."}
	var got := salvage_value(it["key"])
	if loc["where"] == "storage":
		storage["items"].remove_at(loc["i"])
	else:
		crew[loc["s"]]["gear"][loc["g"]] = null
	scrap += got
	sound.emit("coin")
	_changed()
	return {"ok": true, "msg": "%s torn down for %d scrap." % [D.item_name(it["key"]), got]}


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
			elif kind == "throw":
				var c = crowd_centre()
				if c != null:
					moved = throw_item(items[i]["uid"], c["x"], c["y"]).has("ok")
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
	s["route"] = pass_route(s)
	var walk := route_length(s["route"]) / D.WALK_SPEED
	s["repairing"] = false
	s["state"] = "leaving"
	s["path_t"] = 0.0
	var gone: float = trip_seconds(s, site_key)
	trip = {"who": s, "site": site_key, "away": maxf(5.0, gone - walk * 2.0), "t": 0.0, "walk": walk}
	toast.emit("%s heads out through the pass to the %s." % [s["name"], site["name"]], "info")
	_changed()
	return {"ok": true}


## How long a survivor would be gone to a site, there and back.
func trip_seconds(s: Dictionary, site_key: String) -> float:
	return D.SITES[site_key]["gone"] * D.skill_fx(s, "fleet")


## True if a trip starting now would be back on the wall before nightfall.
func back_before_dark(s: Dictionary, site_key: String) -> bool:
	return not is_night() and trip_seconds(s, site_key) < time_to_change()


## Chance (0..1) that a survivor sent to a site never comes back.
func death_chance(s: Dictionary, site_key: String) -> float:
	var base: float = D.SCAVENGE_DEATH * D.SITES[site_key]["gone"] / D.SCAVENGE_DEATH_REF
	return clampf(base * D.skill_fx(s, "careful") * death_mul, 0.0, 1.0)


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
			if randf() < death_chance(s, trip["site"]):
				_lose_scavenger()
				return
			trip["report"] = _roll_loot(trip["site"], s)
			s["state"] = "returning"
			s["path_t"] = 1.0
			if trip["report"]["survivor"] != "":
				var ranger: bool = trip["report"]["site"] == "ranger_cabin"
				var n := add_survivor(trip["report"]["survivor"], "shotgun" if ranger else "pistol", false)
				if ranger:
					n["model"] = "ranger"   # the one who radioed for help: hat, pack and a shotgun
				n["state"] = "arriving"
				n["route"] = pass_route(n)
				n["path_t"] = 1.12   # a few steps behind
				n["x"] = D.PASS_PATH[-1].x
				n["y"] = D.PASS_PATH[-1].y


## Moves everyone who is walking: to another spot on the walls, or between
## their spot and the pass.
func update_walkers(dt: float) -> void:
	for s in crew:
		var st: String = s["state"]
		if st == "wall" or st == "away" or st == "dead" or st == "aboard":
			continue
		s["fighting"] = _fight_on_the_way(s, dt)
		if s["fighting"]:
			continue   # stood their ground: they walk on once it's clear
		var length := maxf(0.01, route_length(s["route"]))
		var dp := D.WALK_SPEED * dt / length
		if st == "moving":
			s["path_t"] = minf(1.0, s["path_t"] + dp)
			if s["path_t"] >= 1.0:
				s["state"] = "wall"
				s["cd"] = 0.3
				s["aim"] = outward(s["side"])
				_changed()
		elif st == "leaving":
			s["path_t"] = minf(1.0, s["path_t"] + dp)
			if s["path_t"] >= 1.0:
				s["state"] = "away"
		elif st == "boarding":
			s["path_t"] = minf(1.0, s["path_t"] + dp)
			if s["path_t"] >= 1.0:
				s["state"] = "aboard"
				toast.emit(("You climb" if s["is_player"] else s["name"] + " climbs") + " into the truck.", "info")
				_changed()
		else:
			s["path_t"] = maxf(0.0, s["path_t"] - dp)
			if s["path_t"] <= 0.0:
				s["state"] = "wall"
				s["cd"] = 0.5
				s["aim"] = outward(s["side"])
				if st == "returning":
					_deliver_trip()
				else:
					survivor_arrived.emit(s["name"])
					toast.emit("%s made it through the pass and joins you on the wall. Skills: %s." % [s["name"], skills_text(s)], "good")
					sound.emit("coin")
				_changed()
		var p := route_point(s["route"], minf(1.0, s["path_t"]))
		s["x"] = p.x
		s["y"] = p.y


## Someone walking (back from the pass, to another spot, to the truck) with
## the dead inside the base and in range: they stop and shoot, and walk on
## once there's nothing left to shoot. True while they're fighting.
func _fight_on_the_way(s: Dictionary, dt: float) -> bool:
	if s["hp"] <= 0.0 or not (in_base(Vector2(s["x"], s["y"])) or on_deck(Vector2(s["x"], s["y"]))):
		return false
	var inside := false
	for z in zombies:
		if z.get("inside", false) and z["hp"] > 0:
			inside = true
			break
	if not inside:
		return false
	s["cd"] -= dt
	_check_ammo(s)
	if _tick_reload(s, dt):
		return true
	var w: Dictionary = D.WEAPONS[s["weapon"]]
	var z = auto_target(s, auto_reach(w))
	if z == null:
		return false
	var ready := swivel(s, atan2(z["y"] - s["y"], z["x"] - s["x"]), D.TURN_RATE, dt)
	if s["cd"] <= 0.0 and ready:
		_shoot(s, z["x"], z["y"], survivor_stats(s))
	return true


## The scavenger didn't make it: they, their gun and their gear are gone.
func _lose_scavenger() -> void:
	var s: Dictionary = trip["who"]
	var site: Dictionary = D.SITES[trip["site"]]
	crew.erase(s)
	trip = null
	toast.emit("%s never came back from the %s." % [s["name"], site["name"]], "danger")
	sound.emit("horn")
	scavenger_lost.emit(s["name"], site["name"])
	_changed()


func _roll_loot(site_key: String, who = null) -> Dictionary:
	var site: Dictionary = D.SITES[site_key]
	var tier: Array = D.SCRAP_TIERS[site["scrap"]]
	var luck: float = D.skill_fx(who, "scrounge") if who != null else 1.0
	var scrap_luck := luck * (1.0 + D.SCAV_EYE_SCRAP * scav_eye)
	luck *= 1.0 + D.SCAV_EYE_FIND * scav_eye   # the camp's Scavenger's eye
	var r := {"site": site_key, "scrap": int(round(randi_range(tier[0], tier[1]) * scrap_luck)), "weapon": "", "food": 0, "survivor": "", "throwables": []}
	if randf() < site["throw_chance"] * luck:
		for k in randi_range(1, 2):
			r["throwables"].append(["molotov", "pipebomb"].pick_random())
	if randf() < site["weapon_chance"] * luck:
		r["weapon"] = ["smg", "shotgun", "rifle", "launcher", "smg", "shotgun", "rifle"].pick_random()
	var forage: float = D.skill_fx(who, "forager") if who != null else 1.0
	if randf() < site["food_chance"] * forage * research_mul("food_find") * (1.0 + D.SCAV_EYE_FIND * scav_eye):
		r["food"] = int(round(randi_range(2, 5) * sqrt(forage) * research_mul("food_yield")))
	elif researched.has("foraging"):
		r["food"] = int(round(1 * research_mul("food_yield")))   # foraging: never empty-handed
	if site["survivor_chance"] >= 1.0 or randf() < site["survivor_chance"] * luck:
		r["survivor"] = free_name()   # (a site at 1 has someone waiting: they radioed for help)
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
	var kept := 0
	for key in r["throwables"]:
		if add_to_storage(key):
			kept += 1
	if r["throwables"].size() > 0:
		var names: PackedStringArray = []
		for key in r["throwables"]:
			names.append("a " + D.item_name(key).to_lower())
		found.append(" and ".join(names) + ("" if kept == r["throwables"].size() else " (some left behind: storage is full)"))
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


## Wall restored per second by everyone repairing right now.
func repair_rate() -> float:
	var r := 0.0
	for s in crew:
		if s.get("repairing", false):
			r += D.REPAIR_PER_SECOND * D.skill_fx(s, "repair")
	return r


func toggle_repair(i: int) -> Dictionary:
	if i < 0 or i >= crew.size():
		return {"msg": ""}
	var s: Dictionary = crew[i]
	if s.get("repairing", false):
		s["repairing"] = false
		return {"ok": true, "msg": "You go back to shooting." if s["is_player"] else s["name"] + " goes back to shooting."}
	if s["state"] != "wall":
		return {"msg": s["name"] + " isn't on the wall right now."}
	if s.has("post"):
		return {"msg": ("You need" if s["is_player"] else s["name"] + " needs") + " to be on a walkway to repair the wall."}
	var w: Dictionary = walls[s["side"]]
	if w["hp"] >= w["max_hp"]:
		return {"msg": "This wall doesn't need repairs."}
	if scrap <= 0 and _repair_debt <= 0.0:
		return {"msg": "No scrap to repair with."}
	s["repairing"] = true
	s["repair_fx"] = 0.0
	sound.emit("build")
	return {"ok": true, "msg": ("You start" if s["is_player"] else s["name"] + " starts") + " repairing the wall."}


## The turret (index in turrets) whose tower is at p, or -1.
func turret_at(p: Vector2, reach := 0.8) -> int:
	for i in turrets.size():
		if p.distance_to(Vector2(turrets[i]["x"], turrets[i]["y"])) < reach:
			return i
	return -1


## Sends survivor i to patch up turret ti: they walk over, kneel at the foot of
## its tower and hammer away (for scrap) till it's whole.
func repair_turret(i: int, ti: int) -> Dictionary:
	if i < 0 or i >= crew.size() or ti < 0 or ti >= turrets.size():
		return {"msg": ""}
	var s: Dictionary = crew[i]
	var t: Dictionary = turrets[ti]
	if t["hp"] >= t["max_hp"]:
		return {"msg": "That turret doesn't need repairs."}
	if scrap <= 0:
		return {"msg": "No scrap to repair with."}
	if s["state"] != "wall" and s["state"] != "moving":
		return {"msg": s["name"] + " isn't on the wall right now."}
	# A spot at the foot of the tower, on the yard side.
	var tp := Vector2(t["x"], t["y"])
	var spot := tp + (D.HUB - tp).normalized() * 0.95
	var here := Vector2(s["x"], s["y"])
	var route: Array = [here]
	if on_deck(here) and s["state"] == "wall" and not s.has("post"):
		route.append(yard_point(s["side"], s["u"]))
	route.append(spot)
	s["post"] = spot
	s["repairing"] = false
	s["route"] = route
	s["path_t"] = 0.0
	s["state"] = "moving"
	s["fix_turret"] = t
	s["fixing"] = false   # once they get there
	s["repair_fx"] = 0.0
	return {"ok": true, "msg": ("You head" if s["is_player"] else s["name"] + " heads") + " over to repair the turret."}


func _stop_fixing(s: Dictionary) -> void:
	s.erase("fix_turret")
	s["fixing"] = false


func _update_turret_repairs(dt: float) -> void:
	for s in crew:
		if not s.has("fix_turret"):
			continue
		var t: Dictionary = s["fix_turret"]
		if not turrets.has(t) or s["hp"] <= 0.0:
			_stop_fixing(s)
			continue
		if s["state"] != "wall":
			continue   # still on the way
		s["fixing"] = true
		if t["hp"] >= t["max_hp"]:
			_stop_fixing(s)
			toast.emit(("You finish" if s["is_player"] else s["name"] + " finishes") + " repairing the turret.", "good")
			sound.emit("build")
			continue
		if scrap <= 0 and _repair_debt <= 0.0:
			_stop_fixing(s)
			toast.emit("Out of scrap. Repairs have stopped.", "danger")
			continue
		var gain := minf(D.TURRET_REPAIR * D.skill_fx(s, "repair") * dt, t["max_hp"] - t["hp"])
		t["hp"] += gain
		_repair_debt += gain / (D.TURRET_PER_SCRAP * D.skill_fx(s, "thrift"))
		while _repair_debt >= 1.0 and scrap > 0:
			_repair_debt -= 1.0
			scrap -= 1
		s["repair_fx"] -= dt
		if s["repair_fx"] <= 0.0:
			s["repair_fx"] = 0.35 + randf() * 0.2
			burst(t["x"] + randf_range(-0.3, 0.3), t["y"] + randf_range(-0.3, 0.3), 4, {"colors": [Color("ffe08a"), Color("ffb347")], "spread": 0.8, "up": 90.0, "life": 0.35, "size": 1.6, "z": 18.0, "glow": true})
			sound.emit("hit")


func update_repairs(dt: float) -> void:
	_update_turret_repairs(dt)
	for s in crew:
		if not s.get("repairing", false):
			continue
		if s["state"] != "wall":
			s["repairing"] = false
			continue
		var w: Dictionary = walls[s["side"]]
		if w["hp"] >= w["max_hp"]:
			s["repairing"] = false
			toast.emit(("You finish" if s["is_player"] else s["name"] + " finishes") + " repairing. The %s wall is at full strength." % D.LANES[s["side"]]["name"].to_lower(), "good")
			continue
		if scrap <= 0:
			s["repairing"] = false
			toast.emit("Out of scrap. Repairs have stopped.", "danger")
			continue
		var gain := minf(D.REPAIR_PER_SECOND * D.skill_fx(s, "repair") * dt, w["max_hp"] - w["hp"])
		w["hp"] += gain
		_repair_debt += gain / (D.WALL_PER_SCRAP * D.skill_fx(s, "thrift"))
		while _repair_debt >= 1.0 and scrap > 0:
			_repair_debt -= 1.0
			scrap -= 1
		# A broken wall built back up far enough closes the gap.
		if w.get("breached", false) and w["hp"] >= w["max_hp"] * D.PATCH_AT:
			w["breached"] = false
			toast.emit("The %s wall is patched. The gap is closed." % D.LANES[s["side"]]["name"].to_lower(), "good")
			sound.emit("build")
			wall_patched.emit(s["side"])
		# Sparks where they're working, and the odd hammer blow.
		s["repair_fx"] -= dt
		if s["repair_fx"] <= 0.0:
			s["repair_fx"] = 0.35 + randf() * 0.2
			var sp := lane_point(s["side"], s["u"] + randf_range(-0.3, 0.3), D.WALL_Y + D.WALL_T)
			burst(sp.x, sp.y, 4, {"colors": [Color("ffe08a"), Color("ffb347")], "spread": 0.8, "up": 90.0, "life": 0.35, "size": 1.6, "z": 14.0, "glow": true})
			sound.emit("hit")


# --- Strangers --------------------------------------------------------------
# One survivor always finds the outpost and walks in through the pass early
# on. After that, strangers only come down the pass if you've lost everyone:
# while you're alone, one turns up every so often.
var first_stranger_done := false


func update_arrivals(dt: float) -> void:
	# The radio station: now and then someone hears it and comes.
	if radio != null and first_stranger_done and randf() < dt / D.RADIO_EVERY:
		_stranger_arrives("Someone heard your radio. They're coming down the mountain pass…")
		return
	if not first_stranger_done:
		if time >= D.FIRST_STRANGER_AT:
			first_stranger_done = true
			_stranger_arrives()
		return
	# Survivors out scavenging or walking in still count as alive.
	if crew.size() == 1 and randf() < dt / D.STRANGER_EVERY_WHEN_ALONE:
		_stranger_arrives()


func _stranger_arrives(msg := "Someone is coming down the mountain pass…") -> void:
	var n := add_survivor(free_name(), "pistol", false)
	n["state"] = "arriving"
	n["route"] = pass_route(n)
	n["path_t"] = 1.0
	var p := route_point(n["route"], 1.0)
	n["x"] = p.x
	n["y"] = p.y
	toast.emit(msg, "info")


# --- Food -------------------------------------------------------------------
# Everyone eats all the time: each survivor, you included and anyone out
# scavenging, gets through FOOD_PER_MINUTE. When the stock runs out the whole
# crew is hungry and shoots slower until food comes in.

## Food eaten per minute by the whole crew right now.
func food_per_minute() -> float:
	return crew.filter(func(s): return s["state"] != "dead").size() * D.FOOD_PER_MINUTE * eat_mul()


## How fast the crew eats compared to normal: Rationing, the Pantry, and the
## best cook who's at the base (cooks don't stack).
func eat_mul() -> float:
	var m := research_mul("eat") * (D.PANTRY["eat"] if pantry else 1.0)
	var cook := 1.0
	for s in crew:
		if s["state"] == "wall" or s["state"] == "moving":
			cook = minf(cook, D.skill_fx(s, "cook"))
	return m * cook


## Seconds until the food runs out at the current rate.
func food_time_left() -> float:
	var rate := food_per_minute()
	return INF if rate <= 0.0 else food / rate * 60.0


func update_food(dt: float) -> void:
	hot_meal = maxf(0.0, hot_meal - dt)
	food = maxf(0.0, food - food_per_minute() / 60.0 * dt)
	if food <= 0.0 and not hungry:
		hungry = true
		toast.emit("The food has run out. The crew is hungry and shoots slower.", "danger")
	elif food > 0.0 and hungry:
		hungry = false
		toast.emit("There's food again. The crew is back to full strength.", "good")


# --- Research ---------------------------------------------------------------
# Spend scrap to start a project; it finishes after a while and unlocks things
# in the workshop, or upgrades turrets and provisions straight away. One at a time.
func research_state(id: String) -> String:
	if researched.has(id):
		return "done"
	if research_cur == id:
		return "active"
	for n in D.RESEARCH[id]["needs"]:
		if not researched.has(n):
			return "locked"
	return "open"


func can_research(id: String) -> Dictionary:
	match research_state(id):
		"done":
			return {"msg": "Already researched."}
		"active":
			return {"msg": "Being researched now."}
		"locked":
			var missing: PackedStringArray = []
			for n in D.RESEARCH[id]["needs"]:
				if not researched.has(n):
					missing.append(D.RESEARCH[n]["name"])
			return {"msg": "Research %s first." % " and ".join(missing)}
	if research_cur != "":
		return {"msg": "Already researching %s." % D.RESEARCH[research_cur]["name"]}
	if scrap < D.RESEARCH[id]["cost"]:
		return {"msg": "Not enough scrap (%d needed)." % D.RESEARCH[id]["cost"]}
	return {"ok": true}


func start_research(id: String) -> Dictionary:
	var chk := can_research(id)
	if not chk.has("ok"):
		return chk
	scrap -= D.RESEARCH[id]["cost"]
	research_cur = id
	research_t = 0.0
	sound.emit("build")
	return {"ok": true}


func research_left() -> float:
	return 0.0 if research_cur == "" else maxf(0.0, D.RESEARCH[research_cur]["time"] - research_t)


func update_research(dt: float) -> void:
	if research_cur == "":
		return
	research_t += dt
	if research_t >= D.RESEARCH[research_cur]["time"]:
		var id := research_cur
		researched[id] = true
		research_count += 1
		research_cur = ""
		research_t = 0.0
		var unlocked: PackedStringArray = []
		for k in D.SHOP:
			if D.SHOP[k].get("needs", "") == id:
				unlocked.append(D.SHOP[k]["name"])
		var text := "Research done: %s." % D.RESEARCH[id]["name"]
		if unlocked.size() > 0:
			text += " %s now in the workshop (B)." % " and ".join(unlocked)
		toast.emit(text, "good")
		sound.emit("coin")
		research_done.emit(id)


## The combined effect of every finished upgrade of one kind (1.0 if none).
func research_mul(fx: String) -> float:
	var m := 1.0
	for id in researched:
		m *= D.RESEARCH[id].get("fx", {}).get(fx, 1.0)
	return m


func is_unlocked(shop_id: String) -> bool:
	var need: String = D.SHOP[shop_id].get("needs", "")
	return need == "" or researched.has(need)


# --- Turrets ----------------------------------------------------------------
func turret_stats() -> Dictionary:
	var t: Dictionary = D.TURRET.duplicate()
	t["dmg"] *= research_mul("turret_dmg")
	t["rate"] *= research_mul("turret_rate")
	t["range"] *= research_mul("turret_range")
	return t


## A fresh turret at (x, y).
func new_turret(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y, "cd": 0.5, "aim": -PI * 0.5, "flash": 0.0, "recoil": 0.0,
		"hp": D.TURRET_HP, "max_hp": D.TURRET_HP, "hurt": 0.0}


## The nearest turret within reach of p, or null.
func turret_near(p: Vector2, reach: float):
	var best = null
	var bd := reach
	for t in turrets:
		var d := p.distance_to(Vector2(t["x"], t["y"]))
		if d < bd:
			bd = d
			best = t
	return best


## The dead clawing at a turret's tower. Torn down at 0.
func hurt_turret(t: Dictionary, dmg: float) -> void:
	var i := turrets.find(t)
	if i < 0:
		return
	t["hp"] -= dmg
	t["hurt"] = 0.2
	burst(t["x"], t["y"], 3, {"colors": [Color("6b4f33"), Color("3a3f44")], "spread": 0.6, "up": 90.0, "life": 0.45, "size": 2.2, "z": 30.0})
	sound.emit("hit")
	if t["hp"] <= 0.0:
		turrets.remove_at(i)
		burst(t["x"], t["y"], 16, {"colors": [Color("6b4f33"), Color("3a3f44"), Color("5a6b3a")], "spread": 1.6, "up": 160.0, "life": 0.9, "size": 3.2, "z": 30.0})
		shake = maxf(shake, 0.5)
		sound.emit("crash")
		toast.emit("The dead have torn down a turret! Build another in the workshop (B).", "danger")
		turret_destroyed.emit(i)
		_changed()


func update_turrets(dt: float) -> void:
	if turrets.is_empty():
		return
	var w := turret_stats()
	for t in turrets:
		t["hurt"] = maxf(0.0, t.get("hurt", 0.0) - dt)
		t["flash"] = maxf(0.0, t["flash"] - dt)
		t["recoil"] = maxf(0.0, t["recoil"] - dt)
		t["cd"] -= dt
		var z = auto_target(t, w["range"])
		if z == null:
			continue
		var ready := swivel(t, atan2(z["y"] - t["y"], z["x"] - t["x"]), D.TURRET_TURN, dt)
		if t["cd"] <= 0.0 and ready:
			fire(t, z["x"], z["y"], 1.0, w)
			t["cd"] = w["rate"]


# --- Workshop ---------------------------------------------------------------
## Current price of a workshop entry (some get dearer each time you buy them).
func shop_cost(id: String) -> int:
	return int(round(_base_cost(id) * price_mul))


func _base_cost(id: String) -> int:
	var base: int = D.SHOP[id]["cost"]
	match id:
		"drill":
			return int(round(base * (1.0 + 0.7 * drills)))
		"shelves":
			return base + 15 * shelves
		"turret":
			return base + 40 * turrets.size()
	return base


## A wall tier's full strength, Tough upgrades included.
func tier_hp(stage: int) -> float:
	return roundf(D.WALL_TIERS[stage]["hp"] * wall_mul)


## True once a one-off or limited workshop entry has been built as far as it goes.
func shop_maxed(id: String) -> bool:
	match id:
		"wall_wood":
			return wall["stage"] >= 1
		"wall_stone":
			return wall["stage"] >= 2
		"turret":
			return turrets.size() >= D.MAX_TURRETS
		"radio":
			return radio != null
	return false


## The ground a building would cover if centred on (x, y).
static func footprint(id: String, x: float, y: float) -> Rect2:
	var sz: Vector2 = D.BUILD_SIZE[id]
	return Rect2(x - sz.x / 2, y - sz.y / 2, sz.x, sz.y)


## Checks a spot in the yard for a turret (not the cost).
func can_build_at(id: String, x: float, y: float) -> Dictionary:
	var r := footprint(id, x, y)
	var yard := Rect2(D.BASE_X0 + 0.2, D.WALL_Y + 0.25, D.BASE_X1 - D.BASE_X0 - 0.4, D.BASE_Y1 - D.WALL_Y - 0.45)
	if not yard.encloses(r):
		return {"msg": "Build it inside the base."}
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var a := lane_point(side, L["u0"] - 0.3, D.WALL_Y - 0.1)
		var b := lane_point(side, L["u1"] + 0.3, D.WALK_Y + 0.8)
		var deck := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
		if deck.intersects(r):
			return {"msg": "Not on a walkway: the crew needs it."}
	for blk in D.BLOCKERS:
		if blk.intersects(r):
			return {"msg": "Something's already there."}
	for t in turrets:
		if footprint("turret", t["x"], t["y"]).intersects(r):
			return {"msg": "Too close to a turret."}
	if radio != null and footprint("radio", radio.x, radio.y).intersects(r):
		return {"msg": "Too close to the radio station."}
	return {"ok": true}


## Pays for a turret and puts it at (x, y).
func build(id: String, x: float, y: float) -> Dictionary:
	var chk := can_buy(id)
	if not chk.has("ok"):
		return chk
	chk = can_build_at(id, x, y)
	if not chk.has("ok"):
		return chk
	scrap -= shop_cost(id)
	if id == "radio":
		radio = Vector2(x, y)
	else:
		turrets.append(new_turret(x, y))
	purchases.append(D.SHOP[id]["name"])
	sound.emit("build")
	_changed()
	return {"ok": true}


## The first free suggested spot for a building, or null.
func default_spot(id: String) -> Variant:
	for p in ([D.RADIO_SPOT] if id == "radio" else D.TURRET_SPOTS):
		if can_build_at(id, p.x, p.y).has("ok"):
			return p
	return null


func can_buy(id: String) -> Dictionary:
	var cost := shop_cost(id)
	if not is_unlocked(id):
		return {"msg": "Research %s first (T)." % D.RESEARCH[D.SHOP[id]["needs"]]["name"]}
	if id == "wall_wood" and wall["stage"] >= 1:
		return {"msg": "Already built."}
	if id == "wall_stone":
		if wall["stage"] >= 2:
			return {"msg": "Already built."}
		if wall["stage"] < 1:
			return {"msg": "Build the wooden wall first."}
	if id == "turret" and turrets.size() >= D.MAX_TURRETS:
		return {"msg": "That's as many turrets as the crew can keep fed with ammo."}
	if id == "radio" and radio != null:
		return {"msg": "The radio station is already built."}
	if id == "shelves" and storage["cap"] >= D.STORAGE_MAX:
		return {"msg": "Storage can't get any bigger."}
	if id == "drill" and crew.size() < 2:
		return {"msg": "You need a crew to drill."}
	if D.ITEMS.has(id) and storage_free() <= 0:
		return {"msg": "Storage is full."}
	if id == "wire" and wire_count() >= D.WIRE_LIMIT:
		return {"msg": "You have %d coils already: that's the most." % D.WIRE_LIMIT}
	if scrap < cost:
		return {"msg": "Not enough scrap (%d needed)." % cost}
	return {"ok": true}


func buy(id: String) -> Dictionary:
	if D.BUILD_SIZE.has(id):
		# Without a spot, use the first free suggested one.
		var spot = default_spot(id)
		if spot == null:
			return {"msg": "There's no room left for it."} if can_buy(id).has("ok") else can_buy(id)
		return build(id, spot.x, spot.y)
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
			"wall_wood", "wall_stone":
				var stage := 1 if id == "wall_wood" else 2
				for w in walls:
					w["stage"] = stage
					var add: float = tier_hp(stage) - w["max_hp"]
					w["max_hp"] += add
					w["hp"] += add

	purchases.append(D.SHOP[id]["name"])
	sound.emit("build")
	_changed()
	return {"ok": true}


# Puts someone on every open wall that has nobody. Used by the balance test.
func auto_defend() -> void:
	for side in D.LANES.size():
		if not sides_open[side]:
			continue
		var manned := false
		for s in crew:
			if s["side"] == side and (s["state"] == "wall" or s["state"] == "moving"):
				manned = true
		if manned:
			continue
		# Take someone from the busiest wall (not you, if there's a choice).
		var count := {}
		for s in crew:
			if s["state"] == "wall":
				count[s["side"]] = count.get(s["side"], 0) + 1
		var pick := -1
		for i in crew.size():
			var s: Dictionary = crew[i]
			if s["state"] == "wall" and count.get(s["side"], 0) > 1:
				if pick < 0 or crew[pick]["is_player"]:
					pick = i
		if pick >= 0:
			var L: Dictionary = D.LANES[side]
			move_survivor(pick, side, (L["u0"] + L["u1"]) / 2.0)


# Sets someone repairing when the wall is low. Used by the automated balance test.
func auto_repair() -> void:
	var busy := 0
	for s in crew:
		if s.get("repairing", false):
			busy += 1
	var w := weakest_wall()
	if w["hp"] < w["max_hp"] * 0.6 and busy == 0 and scrap >= 5:
		for i in range(crew.size() - 1, -1, -1):
			if crew[i]["state"] == "wall" and crew[i]["side"] == w["side"]:
				toggle_repair(i)
				return


# The order the balance-test bot researches things in.
const BOT_RESEARCH := ["firearms", "carpentry", "spikes", "turrets", "radio", "foraging", "shotguns", "rifles", "turret_ammo", "masonry", "rationing", "reloading", "turret_feed", "gunsmith", "beartraps", "explosives", "drills", "smokehouse", "turret_optics", "launchers"]


# Spends scrap sensibly. Used by the automated balance test.
func auto_shop() -> void:
	auto_defend()
	auto_repair()
	var guard := 0
	while guard < 20:
		guard += 1
		var want := ""
		var worst := 99
		for c in crew:
			worst = mini(worst, RANK[c["weapon"]])
		if weakest_wall()["hp"] < weakest_wall()["max_hp"] * 0.6:
			break   # save scrap for repairs
		# Research the next thing on the list when it can be afforded;
		# until then, only buy what matters most.
		var saving := false
		if research_cur == "":
			for id in BOT_RESEARCH:
				if research_state(id) == "open":
					saving = not start_research(id).has("ok")
					break
		if worst < 2 and storage_free() > 0 and is_unlocked("smg"):
			want = "rifle" if is_unlocked("rifle") and scrap >= shop_cost("rifle") else "smg"
		elif can_buy("wall_wood").has("ok"):
			want = "wall_wood"
		elif can_buy("turret").has("ok"):
			want = "turret"
		elif can_buy("radio").has("ok") and crew.size() < 6:   # (the bot stops at six)
			want = "radio"
		elif can_buy("wall_stone").has("ok"):
			want = "wall_stone"
		elif crew.size() > 1 and drills < 3 and is_unlocked("drill"):
			want = "drill"
		else:
			var pool: Array = ["hollow", "trigger", "mine", "spikes", "launcher"].filter(func(k): return is_unlocked(k))
			if pool.is_empty() or saving:
				break
			want = pool.pick_random()
		if not buy(want).has("ok"):
			break
	auto_equip()


## Sends someone out if nobody is out. Used by the automated balance test.
func auto_scavenge() -> void:
	var who := available_scavengers()
	var sites := open_sites()
	if trip != null or who.is_empty() or sites.is_empty():
		return
	var s: int = who.pick_random()
	# Only trips that are back before dark (and none at night).
	sites = sites.filter(func(k): return back_before_dark(crew[s], k))
	if sites.is_empty():
		return
	send_scavenger(s, sites.pick_random())

# --- Director ---------------------------------------------------------------
static func spawn_rate(t: float) -> float:
	return D.SPAWN_BASE + t * D.SPAWN_LINEAR + pow(t / D.SPAWN_CURVE, 2) * 0.6


static func hp_mul(t: float) -> float:
	return 1.0 + t / D.HP_LINEAR + pow(t / D.HP_CURVE, 2)


static func spd_mul(t: float) -> float:
	return 1.0 + minf(0.35, t / D.SPEED_RAMP)


func _pick_type(t: float) -> String:
	var r := randf()
	var pb := minf(0.14, 0.03 + (t - D.BRUTES_FROM) / 2000.0) if t > D.BRUTES_FROM else 0.0
	var pr := minf(0.35, 0.08 + (t - D.RUNNERS_FROM) / 700.0) if t > D.RUNNERS_FROM else 0.0
	if r < pb:
		return "brute"
	if r < pb + pr:
		return "runner"
	return "walker"


func _spawn_one() -> void:
	var type := _pick_type(time)
	spawn_zombie(type, hp_mul(time) * (1.0 + D.HEAT_HP * heat) * D.LEVELS[level - 1].get("hp", 1.0), spd_mul(time), _pick_side())
	spawned += 1
	if not seen.has(type):
		seen[type] = true
		if type == "runner":
			toast.emit("Runners. Fast and fragile. Get them before they reach the wall.", "danger")
		elif type == "brute":
			toast.emit("A brute. Slow, huge, and it hits the wall hard.", "danger")


## The run opens with a couple of zombies already partway down the front
## lane, so things get going straight away. Called when a run is set up.
func spawn_opening() -> void:
	for i in D.EARLY_CLOSE:
		spawn_zombie("walker", hp_mul(0.0) * (1.0 + D.HEAT_HP * heat), spd_mul(0.0), 0, randf_range(D.EARLY_V[0], D.EARLY_V[1]))
		spawned += 1
	update_zombies(0.0)   # settle them into place


## True once the dead are actually coming down a lane (open, and past its grace).
func side_live(side: int) -> bool:
	return sides_open[side] and time >= side_live_at[side]


## Which open lane the next zombie comes down, weighted by the lanes' sizes.
func _pick_side() -> int:
	var total := 0.0
	for side in D.LANES.size():
		if side_live(side):
			total += D.LANES[side]["weight"]
	var r := randf() * total
	for side in D.LANES.size():
		if side_live(side):
			r -= D.LANES[side]["weight"]
			if r < 0.0:
				return side
	return 0


func in_lull() -> bool:
	return time < lull_until


## Starts and ends the quiet spells.
## Lulls only happen by day, and never run into the night.
func update_lulls() -> void:
	if lull_until > 0.0 and time >= lull_until:
		lull_until = -1.0
		next_lull = time + randf_range(D.LULL_EVERY[0], D.LULL_EVERY[1])
		if not is_night():
			toast.emit("They're coming again.", "danger")
	elif lull_until < 0.0 and time >= next_lull and horde_left == 0 and not is_night() and time_to_change() > 30.0:
		lull_until = minf(time + randf_range(D.LULL_LENGTH[0], D.LULL_LENGTH[1]), time + time_to_change() - 5.0)
		toast.emit("The dead thin out. A moment to breathe: repair, rearrange, send someone out.", "good")


# --- Day and night ----------------------------------------------------------
## Seconds into the current day/night cycle.
func cycle_pos() -> float:
	return fmod(time, D.CYCLE)


func is_night() -> bool:
	return cycle_pos() >= D.DAY_LENGTH


## Which day (or night) it is: day 1 and night 1, then day 2...
func day_number() -> int:
	return int(time / D.CYCLE) + 1


## Seconds until nightfall (by day) or dawn (by night).
func time_to_change() -> float:
	var pos := cycle_pos()
	return D.CYCLE - pos if pos >= D.DAY_LENGTH else D.DAY_LENGTH - pos


## How big the horde at nightfall is right now.
func horde_size() -> int:
	return int((D.HORDE_SIZE[0] + int(time / D.HORDE_SIZE[1])) * (1.0 + D.HEAT_SPAWN * heat))


func _once(key: String) -> bool:
	if _cycle_done.has(key):
		return false
	_cycle_done[key] = true
	return true


## The light, and the warnings and hordes as the days turn.
func update_cycle() -> void:
	var pos := cycle_pos()
	var n := day_number()
	# Held out long enough: at dawn the army truck comes. On the last level it's
	# the rescue; otherwise it carries everyone to the next level's base.
	# On the endless Last Stand, holding out that long wins the run (Grit for
	# the win, the next Heat); it goes on until they get in.
	if is_endless() and time >= D.WIN_NIGHTS * D.CYCLE and not won:
		won = true
		toast.emit("Day %d. You've held the Last Stand %d nights: the run counts as won. How long can you last?" % [day_number(), D.WIN_NIGHTS], "good")
		sound.emit("levelup")
	if time >= D.WIN_NIGHTS * D.CYCLE and not over and evac < 0.0 and not is_endless():
		if level >= D.LEVELS.size():
			won = true
			over = true
			toast.emit("Dawn. The army truck rolls in to take you all to safety. You held out %d nights." % (nights_before + D.WIN_NIGHTS), "good")
			sound.emit("levelup")
			run_won.emit()
			return
		evac = 0.0
		toast.emit("Dawn on day %d. An army truck is coming down the pass to move you all to %s, but the horde isn't letting up." % [day_number(), D.LEVELS[level]["name"]], "good")
		sound.emit("levelup")
		truck_coming.emit(level + 1)
	# Darkness: fades in over the last stretch of the day, out over the last of the night.
	var k := 0.0
	if pos < D.DAY_LENGTH:
		k = clampf((pos - (D.DAY_LENGTH - D.TWILIGHT)) / D.TWILIGHT, 0.0, 1.0)
	else:
		k = 1.0 - clampf((pos - (D.CYCLE - D.TWILIGHT)) / D.TWILIGHT, 0.0, 1.0)
	night = smoothstep(0.0, 1.0, k)
	dark = lerpf(0.12, 0.58, night)
	if not is_night():
		if n > 1 and evac < 0.0 and _once("dawn%d" % n):
			toast.emit("Dawn. Day %d. The dead thin out with the light." % n, "good")
			new_day.emit(n)
			sound.emit("coin")
		if pos >= D.DAY_LENGTH - D.DUSK_WARNING and _once("dusk%d" % n):
			toast.emit("The sun is going down. The horde comes with the dark.", "danger")
	else:
		if _once("night%d" % n):
			if researched.has("kitchen") and food > 0.0:
				hot_meal = D.HOT_MEAL["seconds"]
				toast.emit("A hot meal from the field kitchen. The crew's fired up.", "good")
			lull_until = -1.0
			next_lull = maxf(next_lull, n * D.CYCLE + 20.0)   # no lulls until after dawn
			horde_left += horde_size()
			toast.emit("Night %d. Here they come." % n, "danger")
			sound.emit("horn")
			shake = maxf(shake, 0.3)
		if pos >= D.DAY_LENGTH + D.NIGHT_LENGTH / 2.0 and _once("midnight%d" % n):
			horde_left += int(horde_size() * D.MIDNIGHT_WAVE)
			toast.emit("Midnight. Another wave.", "danger")
			sound.emit("horn")


func update_director(dt: float) -> void:
	time += dt
	threat = 1 + int(time / D.THREAT_EVERY)
	update_cycle()
	if evac_go >= 0.0:
		return   # everyone's in the truck: nobody left to come for
	# The last night's horde never stops: they keep coming while the truck's here.
	var last_night := evac >= 0.0 or (not is_endless() and is_night() and day_number() == D.WIN_NIGHTS)
	if evac < 0.0:
		update_lulls()
	# Winding down before dawn: the rest of the horde never comes, and only
	# stragglers, so daylight finds the night's dead mostly put down.
	var winding := is_night() and D.CYCLE - cycle_pos() < D.NIGHT_WIND_DOWN and not last_night
	if winding:
		horde_left = 0
	var share: float = D.NIGHT_SPAWN if last_night or (is_night() and not winding) else (D.WIND_DOWN_SPAWN if winding else D.DAY_SPAWN)
	var rate: float = spawn_rate(time) * share * (1.0 + D.HEAT_SPAWN * heat) * D.LEVELS[level - 1].get("spawn", 1.0)
	if evac >= 0.0:
		rate += EVAC_HORDE
	if in_lull() and evac < 0.0:
		rate = minf(D.LULL_RATE, rate)
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		_spawn_one()
	if horde_left > 0:
		horde_acc += dt * 6.0
		while horde_acc >= 1.0 and horde_left > 0:
			horde_acc -= 1.0
			horde_left -= 1
			_spawn_one()


# --- Runs and the camp ------------------------------------------------------
const _PLAYER_SKILLS := {"p_repair": "repair", "p_thrift": "thrift", "p_aim": "aim", "p_quick": "quick"}


## Sets up a new run with what's been bought at the camp: {"levels": {id: n}, "heat": n}.
## Call it straight after Game.new(), before the first step.
func apply_meta(m: Dictionary) -> void:
	var lv: Dictionary = m.get("levels", {})
	heat = int(m.get("heat", 0))
	level = clampi(int(m.get("level", 2)), 1, D.LEVELS.size())
	open_at = D.LEVELS[level - 1]["open_at"].duplicate()
	# Your skills (in co-op, every player's: the camp's upgrades are the team's).
	for p in crew.filter(func(c): return c["is_player"]):
		for id in _PLAYER_SKILLS:
			var n: int = lv.get(id, 0)
			if n > 0:
				p["skills"][_PLAYER_SKILLS[id]] = maxi(p["skills"].get(_PLAYER_SKILLS[id], 0), n)
	mods["crew_dmg"] += 0.1 * lv.get("commander", 0)
	wall_mul = 1.0 + 0.1 * lv.get("tough", 0)
	price_mul = 1.0 - 0.08 * lv.get("quartermaster", 0)
	kill_scrap = lv.get("salvager", 0)
	scav_eye = lv.get("scav_eye", 0)
	# Base.
	var stage := 1 if lv.get("base_wood", 0) > 0 else 0
	start_stage = stage
	for w in walls:
		w["stage"] = stage
		w["max_hp"] = tier_hp(stage)
		w["hp"] = w["max_hp"]
	storage["cap"] = mini(D.STORAGE_MAX, storage["cap"] + 4 * lv.get("base_shelves", 0))
	if lv.get("base_pantry", 0) > 0:
		pantry = true
		food += D.PANTRY["food"]
	if lv.get("base_turret", 0) > 0:
		var tp: Vector2 = D.TURRET_SPOTS[0]
		turrets.append(new_turret(tp.x, tp.y))
	# Blueprints.
	for id in D.META:
		if D.META[id].has("research") and lv.get(id, 0) > 0:
			researched[D.META[id]["research"]] = true
	# Starting kit.
	scrap += 25 * lv.get("kit_scrap", 0)
	food += 4.0 * lv.get("kit_food", 0)
	if lv.get("kit_smg", 0) > 0:
		for p in crew.filter(func(c): return c["is_player"]):
			p["weapon"] = "smg"
	for i in 2 * lv.get("kit_traps", 0):
		add_to_storage("spikes")
	for i in lv.get("kit_survivor", 0):
		add_survivor(free_name(), "pistol", false)
	_changed()


## An upgrade bought at the camp in the middle of this run, now at level lv:
## the ones in D.META_LIVE take hold straight away. Returns true if it did.
func apply_live(id: String, lv: int) -> bool:
	if not id in D.META_LIVE or over:
		return false
	if _PLAYER_SKILLS.has(id):
		var k: String = _PLAYER_SKILLS[id]
		for p in crew.filter(func(c): return c["is_player"]):
			p["skills"][k] = maxi(p["skills"].get(k, 0), lv)
	match id:
		"commander":
			mods["crew_dmg"] += 0.1   # one more level
		"tough":
			var old := wall_mul
			wall_mul = 1.0 + 0.1 * lv
			for w in walls:
				w["max_hp"] = tier_hp(w["stage"])
				w["hp"] = minf(w["max_hp"], w["hp"] * wall_mul / old)
		"quartermaster":
			price_mul = 1.0 - 0.08 * lv
		"salvager":
			kill_scrap = lv
		"scav_eye":
			scav_eye = lv
	_changed()
	return true


# --- Saving and loading a run ------------------------------------------------
# Everything about a run lives in this object's variables, as plain data, so a
# save is those variables written out. The few that point at each other (who a
# zombie inside is after, which turret someone is repairing, who's out
# scavenging) are saved as ids and linked up again on loading. What's only for
# show (particles, tracers, floating text) isn't kept.
const _NOT_SAVED := ["parts", "tracers", "bullets", "texts", "input_aim", "input_firing", "inputs", "input_auto", "shake", "death_mul", "wall"]
const SAVE_VERSION := 1


## The run as plain data, for scripts/saves.gd to write out.
func to_save() -> Dictionary:
	var data := {}
	for prop in get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = prop["name"]
		if key in _NOT_SAVED:
			continue
		data[key] = _plain(get(key))
	# The links, as ids.
	for i in zombies.size():
		var z: Dictionary = zombies[i]
		var zd: Dictionary = data["zombies"][i]
		zd.erase("prey")
		zd.erase("path")
		var prey = z.get("prey", null)
		if prey != null:
			zd["prey_ref"] = ["turret", turrets.find(prey)] if turrets.has(prey) else ["crew", prey.get("id", -1)]
	for i in crew.size():
		var cd: Dictionary = data["crew"][i]
		cd.erase("fix_turret")
		if crew[i].has("fix_turret"):
			cd["fix_turret_ref"] = turrets.find(crew[i]["fix_turret"])
	if trip != null:
		data["trip"].erase("who")
		data["trip"]["who_id"] = trip["who"]["id"]
	data["_version"] = SAVE_VERSION
	return data


## Picks up a run from to_save()'s data. Call it on a fresh Game.new().
func from_save(data: Dictionary) -> void:
	for key in data:
		if key != "_version" and key in self:
			set(key, data[key])
	wall = walls[0]
	for z in zombies:
		if z.has("prey_ref"):
			var r: Array = z["prey_ref"]
			if r[0] == "turret" and r[1] >= 0 and r[1] < turrets.size():
				z["prey"] = turrets[r[1]]
			elif r[0] == "crew":
				for c in crew:
					if c["id"] == r[1]:
						z["prey"] = c
			z.erase("prey_ref")
	for c in crew:
		if c.has("fix_turret_ref"):
			var ti: int = c["fix_turret_ref"]
			if ti >= 0 and ti < turrets.size():
				c["fix_turret"] = turrets[ti]
			c.erase("fix_turret_ref")
	if trip != null and trip.has("who_id"):
		for c in crew:
			if c["id"] == trip["who_id"]:
				trip["who"] = c
		trip.erase("who_id")
		if not trip.has("who"):
			trip = null
	_changed()


## A one-line summary of the run, for the save slots.
func save_summary() -> Dictionary:
	return {"day": day_number(), "night": is_night(), "time": time, "kills": kills, "level": level,
		"crew": crew.filter(func(c): return c["hp"] > 0.0).size(), "heat": heat}


## A deep copy that only plain data survives: dictionaries and arrays copied,
## everything else (numbers, strings, vectors, colours) as it is.
static func _plain(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _plain(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_plain(x))
		return a
	return v


## Nights held out so far this run, over every level played.
func nights_survived() -> int:
	if is_endless():
		return nights_before + day_number() - 1   # no limit on the last level
	return nights_before + (D.WIN_NIGHTS if won else mini(day_number() - 1, D.WIN_NIGHTS))


## The endless last level: no truck, the waves never stop.
func is_endless() -> bool:
	return D.LEVELS[level - 1].get("endless", false)


# --- The army truck: on to the next level -------------------------------------------
# At dawn after the last night the truck backs down the mountain pass into the
# yard. The dead don't stop: the player has to send everyone over to climb in
# the back (board_truck), and once they're all on, it drives off up the pass.
# As it rolls out through the gate the level ends.
const TRUCK_ARRIVES := 9.0     # seconds after it's called that it's parked in the yard
const TRUCK_STOP := Vector2(11.2, 24.4)   # where it parks, nose to the gate
const TRUCK_BOARD := Vector2(11.2, 20.7)  # the tailgate, where the crew climb in
const TRUCK_OUT := 3.5         # seconds from pulling away to rolling out through the gate
const TRUCK_GONE := 5.0        # and to the next level
const EVAC_HORDE := 1.2        # extra dead a second while the truck's here: the night's horde never stops
var evac_go := -1.0            # seconds since it pulled away with everyone (-1: not yet)


## True once the truck is parked and waiting for the crew.
func truck_waiting() -> bool:
	return evac >= TRUCK_ARRIVES and evac_go < 0.0


## Who still has to get on: everyone alive who isn't aboard yet.
func left_to_board() -> int:
	var n := 0
	for c in crew:
		if c["state"] != "dead" and c["state"] != "aboard" and c["hp"] > 0.0:
			n += 1
	return n


## Sends a survivor to climb into the back of the truck.
func board_truck(i: int) -> Dictionary:
	if i < 0 or i >= crew.size():
		return {"msg": ""}
	if not truck_waiting():
		return {"msg": "The truck isn't here yet."}
	var s: Dictionary = crew[i]
	if s["state"] == "boarding" or s["state"] == "aboard":
		return {"msg": ""}
	if s["state"] != "wall" and s["state"] != "moving":
		return {"msg": s["name"] + " can't get to the truck right now."}
	var here := Vector2(s["x"], s["y"])
	var route: Array = [here]
	if on_deck(here) and s["state"] == "wall" and not s.has("post"):
		route.append(yard_point(s["side"], s["u"]))
	route.append(TRUCK_BOARD + Vector2(randf_range(-0.3, 0.3), -0.3))
	route.append(TRUCK_BOARD)
	s.erase("post")
	s["repairing"] = false
	_stop_fixing(s)
	s["route"] = route
	s["path_t"] = 0.0
	s["state"] = "boarding"
	_changed()
	return {"ok": true, "msg": ("You head" if s["is_player"] else s["name"] + " heads") + " for the truck."}


## Everyone at once (the G key / the HUD button).
func board_all() -> Dictionary:
	var sent := 0
	for i in crew.size():
		if board_truck(i).has("ok"):
			sent += 1
	if sent == 0:
		return {"msg": "" if truck_waiting() else "The truck isn't here yet."}
	return {"ok": true, "msg": "Everyone to the truck!" if sent > 1 else "To the truck!"}


## The truck backs in, waits, then drives off once everyone's in.
func update_evac(dt: float) -> void:
	if evac < 0.0:
		return
	var before := evac
	evac += dt
	if before < TRUCK_ARRIVES and evac >= TRUCK_ARRIVES:
		toast.emit("The truck's here! Pick your people and click the truck, or press G: everyone in the back, and the dead aren't stopping.", "good")
		sound.emit("horn")
		if trip != null:
			trip["who"]["state"] = "aboard"   # picked up on the road
			trip = null
			_changed()
	if truck_waiting() and left_to_board() == 0:
		evac_go = 0.0
		toast.emit("Everyone's in. Go, go, go!", "good")
		sound.emit("levelup")
	if evac_go >= 0.0:
		evac_go += dt
		if evac_go >= TRUCK_GONE:
			advance_level()


## Everyone alive moves to the next level's base: a fresh start there (day 1,
## new walls, nothing built), keeping the crew and their guns, gear and
## skills, scrap, food, storage, research and the camp's upgrades.
func advance_level() -> void:
	nights_before += D.WIN_NIGHTS
	level += 1
	open_at = D.LEVELS[level - 1]["open_at"].duplicate()
	evac = -1.0
	evac_go = -1.0
	time = 0.0
	threat = 1
	sides_open = [true, false, false]
	side_live_at = [0.0, INF, INF]
	_side_warned = [true, false, false]
	zombies.clear()
	shots.clear()
	fires.clear()
	parts.clear()
	tracers.clear()
	bullets.clear()
	texts.clear()
	traps.clear()
	turrets.clear()
	radio = null
	looted = {}
	mods["wire"] = 0.0
	horde_left = 0
	horde_acc = 0.0
	spawn_acc = 0.0
	next_lull = D.FIRST_LULL
	lull_until = -1.0
	hot_meal = 0.0
	_cycle_done = {}
	trip = null
	_repair_debt = 0.0
	for w in walls:
		w["stage"] = start_stage
		w["max_hp"] = tier_hp(start_stage)
		w["hp"] = w["max_hp"]
		w["breached"] = false
		w.erase("gap")
		for i in w["hurt"].size():
			w["hurt"][i] = 0.0
	# The crew: healed and up on the front walkway. Whoever fell stays behind.
	var kept: Array = []
	for c in crew:
		if c["is_player"] or c["hp"] > 0.0:
			kept.append(c)
	crew = kept
	for c in crew:
		c.erase("post")
		_stop_fixing(c)
		c["repairing"] = false
		c["route"] = []
		c["path_t"] = 0.0
		if c["hp"] > 0.0:
			c["hp"] = c["max_hp"]
			c["state"] = "wall"
			c["side"] = -1
			c["ammo"] = int(D.WEAPONS[c["weapon"]]["mag"])
			c["reload"] = 0.0
		else:
			c["x"] = -200.0   # you fell, but the crew carried on: you stay behind
			c["y"] = -200.0
	layout_crew()
	spawn_opening()
	toast.emit("Level %d: %s. %s" % [level, D.LEVELS[level - 1]["name"], D.LEVELS[level - 1]["desc"]], "info")
	level_started.emit(level)
	_changed()


## What this run is worth in Grit, line by line.
func run_result() -> Dictionary:
	var nights := nights_survived()
	var parts := {
		"base": D.GRIT["base"],
		"nights": nights * D.GRIT["night"],
		"kills": kills / D.GRIT["kills_per"],
		"research": research_count * D.GRIT["research"],
		"survivors": (crew.size() - 1) * D.GRIT["survivor"],
		"win": D.GRIT["win"] if won else 0,
	}
	var sum := 0
	for k in parts:
		sum += parts[k]
	var total := int(round(sum * (1.0 + D.HEAT_GRIT * heat) * D.LEVELS[level - 1]["grit"]))
	return {"parts": parts, "total": total, "won": won, "nights": nights, "heat": heat, "level": level}


# --- Main step --------------------------------------------------------------
# Advances the world by dt seconds. Does nothing while a card choice is open.
func step(dt: float) -> void:
	if over:
		update_parts(dt)
		return
	update_director(dt)
	update_evac(dt)
	update_sides()
	update_trip(dt)
	update_walkers(dt)
	update_arrivals(dt)
	update_food(dt)
	update_research(dt)
	update_repairs(dt)
	update_traps(dt)
	update_zombies(dt)
	update_health(dt)
	update_crew(dt)
	update_turrets(dt)
	update_bullets(dt)
	update_shots(dt)
	update_parts(dt)
