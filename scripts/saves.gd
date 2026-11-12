# Saved runs: an autosave (made at every dawn, and whenever you quit to the
# title), a quick save (F5), and three slots of your own. Each is one file in
# user://saves/ holding a short summary (for the slot list) and the run itself
# (Game.to_save()).
extends RefCounted

const SLOTS := ["auto", "quick", "1", "2", "3"]
const NAMES := {"auto": "Autosave", "quick": "Quick save", "1": "Slot 1", "2": "Slot 2", "3": "Slot 3"}

## Where the files go (tests point this somewhere else).
static var dir := "user://saves/"


static func path(slot: String) -> String:
	return dir + "save_%s.dat" % slot


static func write(slot: String, game) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	var info: Dictionary = game.save_summary()
	info["when"] = Time.get_datetime_string_from_system(false, true)
	info["stamp"] = Time.get_unix_time_from_system()
	f.store_var({"info": info, "run": game.to_save()})
	return true


## {"info", "run"}, or {} if there's no save there (or it can't be read).
static func read(slot: String) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	if not (d is Dictionary) or not d.has("run") or not d.has("info"):
		return {}
	return d


## Just the summary (or {}), for the slot list.
static func info(slot: String) -> Dictionary:
	var d := read(slot)
	return d.get("info", {})


static func erase(slot: String) -> void:
	if FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(path(slot))


## The slot saved most recently, or "" if there are none.
static func latest() -> String:
	var best := ""
	var bt := -1.0
	for s in SLOTS:
		var i := info(s)
		if not i.is_empty() and float(i.get("stamp", 0.0)) > bt:
			bt = float(i["stamp"])
			best = s
	return best


## "Day 3 (night) · 14:05 · 212 kills · crew 3 · Heat 1", and when it was saved.
static func describe(i: Dictionary) -> String:
	if i.is_empty():
		return "Empty"
	var t := int(i.get("time", 0.0))
	var txt := "Day %d%s  ·  %d:%02d  ·  %d kills  ·  crew %d" % [i.get("day", 1), " (night)" if i.get("night", false) else "", t / 60, t % 60, i.get("kills", 0), i.get("crew", 1)]
	if int(i.get("heat", 0)) > 0:
		txt += "  ·  Heat %d" % i["heat"]
	return txt + "\nsaved " + str(i.get("when", "")).replace("T", " ")
