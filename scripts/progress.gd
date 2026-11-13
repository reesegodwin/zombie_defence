# What carries over from run to run: Grit, the camp upgrades bought with it,
# the Heat levels unlocked by winning, and a few records. Saved to
# user://progress.cfg. Tests make one with a different path.
extends RefCounted

const D = preload("res://scripts/defs.gd")

var path := "user://progress.cfg"
var grit := 0
var levels := {}          # upgrade id (D.META) -> level bought
var heat := 0             # the Heat chosen for the next run
var map_level := 1        # the level chosen for the next run (D.LEVELS, from 1)
var level_wins := {}      # level -> wins there
var reached := 1          # the furthest level the truck has carried you to: only those can be picked
var max_heat := 0         # the highest Heat unlocked
var runs := 0
var wins := 0
var best_nights := 0


static func open(p := "user://progress.cfg") -> RefCounted:
	var pr = load("res://scripts/progress.gd").new()
	pr.path = p
	pr.load_file()
	return pr


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	grit = cfg.get_value("camp", "grit", 0)
	levels = cfg.get_value("camp", "levels", {})
	heat = cfg.get_value("camp", "heat", 0)
	map_level = cfg.get_value("camp", "level", 1)
	level_wins = cfg.get_value("records", "level_wins", {})
	reached = cfg.get_value("records", "reached", 1)
	for lv in level_wins:   # (from before this was kept: a win there means the next was reached)
		reached = maxi(reached, mini(int(lv) + 1, D.LEVELS.size()))
	map_level = clampi(map_level, 1, reached)
	max_heat = cfg.get_value("camp", "max_heat", 0)
	runs = cfg.get_value("records", "runs", 0)
	wins = cfg.get_value("records", "wins", 0)
	best_nights = cfg.get_value("records", "best_nights", 0)
	# Upgrades that no longer exist (the game changed) are refunded.
	for id in levels.keys():
		if not D.META.has(id):
			grit += _refund(id, levels[id])
			levels.erase(id)


## Grit paid for upgrades that have since been removed from the game.
const _OLD_COSTS := {"bp_farming": [30], "base_farm": [40]}


func _refund(id: String, lv: int) -> int:
	var total := 0
	var costs: Array = _OLD_COSTS.get(id, [])
	for k in mini(lv, costs.size()):
		total += costs[k]
	return total


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("camp", "grit", grit)
	cfg.set_value("camp", "levels", levels)
	cfg.set_value("camp", "heat", heat)
	cfg.set_value("camp", "level", map_level)
	cfg.set_value("records", "level_wins", level_wins)
	cfg.set_value("records", "reached", reached)
	cfg.set_value("camp", "max_heat", max_heat)
	cfg.set_value("records", "runs", runs)
	cfg.set_value("records", "wins", wins)
	cfg.set_value("records", "best_nights", best_nights)
	cfg.save(path)


## Everything back to the start (Grit, upgrades, Heat and records).
func reset() -> void:
	grit = 0
	levels = {}
	heat = 0
	max_heat = 0
	map_level = 1
	level_wins = {}
	reached = 1
	runs = 0
	wins = 0
	best_nights = 0
	save()


func level(id: String) -> int:
	return levels.get(id, 0)


func max_level(id: String) -> int:
	return D.META[id]["costs"].size()


## Grit for the next level of an upgrade, or -1 if it's maxed out.
func next_cost(id: String) -> int:
	var lv := level(id)
	return -1 if lv >= max_level(id) else int(D.META[id]["costs"][lv])


func can_buy(id: String) -> Dictionary:
	if next_cost(id) < 0:
		return {"msg": "Fully upgraded."}
	for n in D.META[id].get("needs", []):
		if level(n) == 0:
			return {"msg": "Needs %s first." % D.META[n]["name"]}
	if grit < next_cost(id):
		return {"msg": "Not enough Grit (%d needed)." % next_cost(id)}
	return {"ok": true}


func buy(id: String) -> Dictionary:
	var chk := can_buy(id)
	if not chk.has("ok"):
		return chk
	grit -= next_cost(id)
	levels[id] = level(id) + 1
	save()
	return {"ok": true}


## Banks a finished run: its Grit, a win (which unlocks the next Heat) and
## records. Returns true if the win unlocked a new Heat level.
func bank(result: Dictionary) -> bool:
	grit += int(result["total"])
	runs += 1
	best_nights = maxi(best_nights, int(result["nights"]))
	var unlocked := false
	if result["won"]:
		wins += 1
		var lv: int = result.get("level", map_level)
		level_wins[lv] = int(level_wins.get(lv, 0)) + 1
		if heat >= max_heat and max_heat < D.MAX_HEAT:
			max_heat += 1
			unlocked = true
	save()
	return unlocked


## The truck brought you to level lv: from now on it can be picked.
func reach(lv: int) -> void:
	if lv > reached:
		reached = mini(lv, D.LEVELS.size())
		save()


## What a new run starts with (handed to the game's apply_meta).
func meta() -> Dictionary:
	return {"levels": levels.duplicate(), "heat": heat, "level": map_level, "first_run": runs == 0}
