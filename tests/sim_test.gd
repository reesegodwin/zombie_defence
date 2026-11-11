# Headless checks and balance runs.
# Run from the project folder:
#   godot --headless --script res://tests/sim_test.gd
extends SceneTree

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/defs.gd")

var failures := 0


func check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond:
		failures += 1


func _init() -> void:
	print("Unit checks")
	_unit_checks()
	print("Balance runs (auto-fire, auto-equip, random cards)")
	var times: Array = []
	for run in int(OS.get_environment("RUNS") if OS.get_environment("RUNS") != "" else "6"):
		var r := _sim_run(1500.0)
		times.append(r["time"])
		print("  run %d: survived %.0fs, level %d, kills %d, crew %s" % [run + 1, r["time"], r["level"], r["kills"], str(r["crew"])])
	times.sort()
	print("  median survival: %.0fs" % times[times.size() / 2])
	check(times[0] > 60.0, "every run lasts over a minute")
	check(times[-1] < 1500.0, "the game eventually overwhelms the defence")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _unit_checks() -> void:
	var g = Game.new()
	check(g.crew.size() == 1 and g.crew[0]["weapon"] == "pistol", "you start alone with a pistol")

	# Shooting a walker straight ahead kills it.
	var z: Dictionary = g.spawn_zombie("walker", 1.0, 1.0)
	z["x"] = g.crew[0]["x"]; z["y"] = 10.0
	for i in 5:
		g.fire(g.crew[0], z["x"], z["y"], 1.0)
	check(z["hp"] <= 0, "five pistol shots kill a walker")
	check(g.kills == 1 and g.xp == 1, "a kill gives experience")

	# Zombies reach the wall and damage it.
	g = Game.new()
	var z2: Dictionary = g.spawn_zombie("brute", 1.0, 1.0)
	z2["y"] = D.WALL_Y - 0.5
	var hp0: float = g.wall["hp"]
	for i in 120:
		g.update_zombies(1.0 / 30.0)
	check(g.wall["hp"] < hp0, "a zombie at the wall damages it")

	# Inventory: cards put items in storage, items move into slots.
	g = Game.new()
	g.apply_card({"id": "item", "key": "smg", "title": "SMG"})
	check(g.storage["items"].size() == 1, "a weapon card adds the gun to storage")
	var r: Dictionary = g.move_item({"where": "storage", "i": 0}, {"where": "weapon", "s": 0})
	check(r.has("ok") and g.crew[0]["weapon"] == "smg" and g.storage["items"][0]["key"] == "pistol", "dragging a gun onto a survivor swaps it with theirs")
	g.add_to_storage("hollow")
	r = g.move_item({"where": "storage", "i": 1}, {"where": "weapon", "s": 0})
	check(not r.has("ok"), "gear cannot go in a weapon slot")
	r = g.move_item({"where": "storage", "i": 1}, {"where": "gear", "s": 0, "g": 0})
	check(r.has("ok") and g.crew[0]["gear"][0]["key"] == "hollow", "gear goes in a gear slot")
	check(g.survivor_stats(g.crew[0])["dmg"] > 1.2, "hollow points raise damage")
	g.apply_card({"id": "hire", "name": "Dana", "weapon": "pistol", "title": "Take in Dana"})
	check(g.crew.size() == 2 and g.crew[1]["weapon"] == "pistol", "new survivors start with pistols")

	# Supplies.
	g.wall["hp"] = 100.0
	g.add_to_storage("repair")
	var idx: int = g.storage["items"].size() - 1
	g.use_supply(idx)
	check(g.wall["hp"] == 350.0, "a repair kit restores half the wall")

	# Traps.
	g = Game.new()
	g.add_to_storage("mine")
	check(not g.place_trap(0, 10.0, 15.0).has("ok"), "traps cannot go behind the wall")
	check(g.place_trap(0, 10.0, 8.0).has("ok") and g.traps.size() == 1, "a trap goes on the field")
	var w: Dictionary = g.spawn_zombie("walker", 1.0, 1.0)
	w["x"] = 10.0; w["y"] = 8.0
	g.update_traps(0.1)
	check(w["hp"] <= 0 and g.traps.is_empty(), "a landmine kills a walker and is used up")
	g.add_to_storage("beartrap")
	g.place_trap(0, 9.0, 6.0)
	var b: Dictionary = g.spawn_zombie("brute", 1.0, 1.0)
	b["x"] = 9.0; b["y"] = 6.0
	g.update_traps(0.1)
	check(b["held"] > 0 and g.traps[0]["uses"] == 5.0, "a bear trap holds a brute")
	check(not g.pick_up_trap(g.traps[0]["uid"]).has("ok"), "a trap holding a zombie cannot be picked up")

	# Level-up.
	g = Game.new()
	g.xp = 10
	g.step(0.01)
	check(g.cards.size() == 3 and g.level == 2, "levelling up offers three cards")
	var t0: float = g.time
	g.step(0.5)
	check(g.time == t0, "the game waits while cards are shown")
	g.choose_card(0)
	check(g.cards.is_empty(), "choosing a card resumes the game")


func _sim_run(limit: float) -> Dictionary:
	var g = Game.new()
	g.input_auto = true
	var dt := 1.0 / 30.0
	while not g.over and g.time < limit:
		if not g.cards.is_empty():
			g.choose_card(randi() % g.cards.size())
			g.auto_equip()
			continue
		g.step(dt)
	var weapons: Array = []
	for s in g.crew:
		weapons.append(s["weapon"])
	return {"time": g.time, "level": g.level, "kills": g.kills, "crew": weapons}
