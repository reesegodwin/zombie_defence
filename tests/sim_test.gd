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
	print("Balance runs (auto-fire; a bot scavenges at random sites, shops and equips)")
	var times: Array = []
	for run in int(OS.get_environment("RUNS") if OS.get_environment("RUNS") != "" else "6"):
		var r := _sim_run(1500.0)
		times.append(r["time"])
		print("  run %d: survived %.0fs, kills %d, purchases %d, hungry %s, crew %s" % [run + 1, r["time"], r["kills"], r["scrap_spent"], str(r["hungry"]), str(r["crew"])])
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
	check(g.kills == 1, "kills are counted")

	# With auto-fire on you face what you're shooting, not the cursor.
	g = Game.new()
	g.input_auto = true
	var you: Dictionary = g.crew[0]
	var za: Dictionary = g.spawn_zombie("walker", 1.0, 0.0)
	za["x"] = 6.0; za["y"] = 10.0
	g.input_aim = Vector2(16.0, 9.0)          # cursor off to the right
	g.update_crew(0.016)
	var want := atan2(za["y"] - you["y"], za["x"] - you["x"])
	check(absf(angle_difference(you["aim"], want)) < 0.01, "with auto-fire on you aim at your target, not the cursor")
	g.input_firing = true
	g.update_crew(0.016)
	var cur := atan2(9.0 - you["y"], 16.0 - you["x"])
	check(absf(angle_difference(you["aim"], cur)) < 0.01, "holding the mouse button aims at the cursor even with auto-fire on")
	g.input_firing = false
	g.input_auto = false
	g.update_crew(0.016)
	check(absf(angle_difference(you["aim"], cur)) < 0.01, "with auto-fire off you aim at the cursor")

	# Zombies reach the wall and damage it.
	g = Game.new()
	var z2: Dictionary = g.spawn_zombie("brute", 1.0, 1.0)
	z2["y"] = D.WALL_Y - 0.5
	var hp0: float = g.wall["hp"]
	for i in 120:
		g.update_zombies(1.0 / 30.0)
	check(g.wall["hp"] < hp0, "a zombie at the wall damages it")

	# Inventory: bought items go to storage, items move into slots.
	g = Game.new()
	g.scrap = 1000
	check(g.buy("smg").has("ok") and g.storage["items"].size() == 1, "buying a gun puts it in storage")
	var r: Dictionary = g.move_item({"where": "storage", "i": 0}, {"where": "weapon", "s": 0})
	check(r.has("ok") and g.crew[0]["weapon"] == "smg" and g.storage["items"][0]["key"] == "pistol", "dragging a gun onto a survivor swaps it with theirs")
	g.add_to_storage("hollow")
	r = g.move_item({"where": "storage", "i": 1}, {"where": "weapon", "s": 0})
	check(not r.has("ok"), "gear cannot go in a weapon slot")
	r = g.move_item({"where": "storage", "i": 1}, {"where": "gear", "s": 0, "g": 0})
	check(r.has("ok") and g.crew[0]["gear"][0]["key"] == "hollow", "gear goes in a gear slot")
	check(g.survivor_stats(g.crew[0])["dmg"] > 1.2, "hollow points raise damage")
	var n: Dictionary = g.add_survivor("Dana", "pistol", false)
	check(g.crew.size() == 2 and n["weapon"] == "pistol", "new survivors start with pistols")

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

	# Workshop.
	g = Game.new()
	g.scrap = 10
	check(not g.buy("rifle").has("ok") and g.scrap == 10, "you can't buy what you can't afford")
	g.scrap = 500
	var maxhp0: float = g.wall["max_hp"]
	var c0: int = g.shop_cost("reinforce")
	g.buy("reinforce")
	check(g.wall["max_hp"] > maxhp0 and g.wall["stage"] == 1 and g.scrap == 500 - c0, "reinforcing the wall costs scrap and makes it tougher")
	check(g.shop_cost("reinforce") > c0, "each wall upgrade costs more")

	# Scavenging.
	g = Game.new()
	check(not g.send_scavenger(0, "gas_station").has("ok"), "you can't send yourself")
	g.add_survivor("Dana", "pistol", false)
	var dana: Dictionary = g.crew[1]
	check(g.send_scavenger(1, "gas_station").has("ok") and dana["state"] == "leaving", "a survivor can be sent out")
	g.add_survivor("Kofi", "pistol", false)
	check(not g.send_scavenger(2, "farmhouse").has("ok"), "only one survivor can be out at a time")
	var gone: float = D.SITES["gas_station"]["gone"]
	check(absf(g.trip_time_left() - gone) < 0.5, "the trip takes as long as the map says")
	var scrap0: int = g.scrap
	var seen_away := false
	var t := 0.0
	while g.trip != null and t < gone + 10:
		g.update_trip(0.1)
		g.update_walkers(0.1)
		g.update_crew(0.1)
		if dana["state"] == "away":
			seen_away = true
		t += 0.1
	check(seen_away, "the survivor disappears while away")
	check(g.trip == null and dana["state"] == "wall" and absf(t - gone) < 1.0, "they come back after the trip time")
	check(g.scrap - scrap0 >= D.SCRAP_TIERS[0][0] and g.scrap - scrap0 <= D.SCRAP_TIERS[0][1], "they bring back scrap in the site's range")
	# Lucky finds over many trips at a rich site.
	var finds := {"weapon": 0, "food": 0, "survivor": 0, "high": 0}
	for k in 400:
		var lr: Dictionary = g._roll_loot("police_station")
		if lr["weapon"] != "": finds["weapon"] += 1
		if lr["food"] > 0: finds["food"] += 1
		if lr["survivor"] != "": finds["survivor"] += 1
		if lr["scrap"] >= D.SCRAP_TIERS[2][0]: finds["high"] += 1
	print("    police station, 400 trips: ", finds)
	check(finds["high"] == 400, "high-scrap sites always give high scrap")
	check(finds["weapon"] > 70 and finds["weapon"] < 170, "weapon finds match the site's odds")

	# Strangers: one walks in at 30 seconds; after that only if you're alone.
	g = Game.new()
	while g.time < D.FIRST_STRANGER_AT - 0.5:
		g.time += 0.1
		g.update_arrivals(0.1)
	check(g.crew.size() == 1, "nobody comes through the pass before 30 seconds")
	g.time += 1.0
	g.update_arrivals(0.1)
	check(g.crew.size() == 2 and g.crew[1]["state"] == "arriving", "a survivor comes down the pass at 30 seconds")
	for i in 6000:
		g.time += 0.1
		g.update_arrivals(0.1)
	check(g.crew.size() == 2, "no more strangers while you still have a survivor")
	g.crew.resize(1)   # everyone else is gone
	var came := false
	for i in 3000:
		g.update_arrivals(0.1)
		if g.crew.size() > 1:
			came = true
			break
	check(came, "once you've lost everyone, strangers come again")

	# Food.
	g = Game.new()
	g.add_survivor("Dana", "pistol", false)
	g.food = 1
	g.update_food(D.MEAL_EVERY + 0.1)
	check(g.hungry and g.survivor_stats(g.crew[0])["interval"] > D.WEAPONS["pistol"]["rate"], "without enough food the crew is hungry and slower")
	g.food = 5
	g.update_food(D.MEAL_EVERY + 0.1)
	check(not g.hungry and g.food == 3, "a meal costs one food each and ends the hunger")


func _sim_run(limit: float) -> Dictionary:
	var g = Game.new()
	g.input_auto = true
	var dt := 1.0 / 30.0
	var next_think := 0.0
	while not g.over and g.time < limit:
		g.step(dt)
		if g.time >= next_think:
			next_think = g.time + 2.0
			g.auto_scavenge()
			g.auto_shop()
	var weapons: Array = []
	for s in g.crew:
		weapons.append(s["weapon"])
	return {"time": g.time, "kills": g.kills, "crew": weapons, "scrap_spent": g.purchases.size(), "food": g.food, "hungry": g.hungry}
