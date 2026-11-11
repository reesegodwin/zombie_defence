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
		print("  run %d: survived %.0fs, kills %d, purchases %d, places looted %d, crew %s" % [run + 1, r["time"], r["kills"], r["scrap_spent"], r["looted"], str(r["crew"])])
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
	za["x"] = 9.0; za["y"] = 11.5
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
	var n: Dictionary = g.add_survivor("Dana", "pistol", false, {})
	check(g.crew.size() == 2 and n["weapon"] == "pistol", "new survivors start with pistols")

	# Repairing the wall.
	g = Game.new()
	g.add_survivor("Dana", "pistol", false, {})
	g.wall["hp"] = 100.0
	g.scrap = 100
	check(g.toggle_repair(1).has("ok") and g.crew[1]["repairing"], "clicking a survivor sets them repairing")
	var rz: Dictionary = g.spawn_zombie("walker", 50.0, 0.0)
	rz["x"] = g.crew[1]["x"]; rz["y"] = 12.0
	g.input_auto = false
	for i in 100:                      # 10 seconds
		g.update_repairs(0.1)
		g.update_crew(0.1)
	var gained: float = g.wall["hp"] - 100.0
	check(absf(gained - D.REPAIR_PER_SECOND * 10.0) < 1.0, "repairs take time: %d wall in 10 seconds" % int(gained))
	check(absi((100 - g.scrap) - int(round(gained / D.WALL_PER_SCRAP))) <= 1, "repairs cost scrap: %d spent for %d wall" % [100 - g.scrap, int(gained)])
	check(rz["hp"] >= rz["max_hp"], "a survivor who is repairing doesn't shoot")
	g.toggle_repair(1)
	check(not g.crew[1]["repairing"], "clicking them again stops the repairs")
	g.toggle_repair(1)
	g.scrap = 0
	g._repair_debt = 0.0
	g.update_repairs(0.1)
	check(not g.crew[1]["repairing"], "repairs stop when the scrap runs out")
	g.scrap = 1000
	g.toggle_repair(1)
	g.toggle_repair(0)
	for i in 600:
		g.update_repairs(0.1)
	check(g.wall["hp"] == g.wall["max_hp"] and g.repairers() == 0, "repairs stop when the wall is whole")
	check(not g.toggle_repair(1).has("ok"), "a whole wall can't be repaired")

	# Supplies.
	g = Game.new()
	g.add_to_storage("wire")
	g.use_supply(0)
	check(g.mods["wire"] > 0 and g.storage["items"].is_empty(), "wire gets strung along the wall")

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
	g.death_mul = 0.0
	check(not g.send_scavenger(0, "gas_station").has("ok"), "you can't send yourself")
	g.add_survivor("Dana", "pistol", false, {})
	var dana: Dictionary = g.crew[1]
	check(g.send_scavenger(1, "gas_station").has("ok") and dana["state"] == "leaving", "a survivor can be sent out")
	g.add_survivor("Kofi", "pistol", false, {})
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
	check(g.looted.has("gas_station") and not g.site_open("gas_station"), "a looted place is marked as picked clean")
	check(not g.send_scavenger(1, "gas_station").has("ok"), "a looted place can't be visited again")
	check(g.send_scavenger(1, "farmhouse").has("ok"), "other places are still open")
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

	# Skills.
	var counts := {}
	var levels := [0, 0, 0]
	var player_ok := true
	for i in 600:
		var sk: Dictionary = Game.roll_skills(false)
		counts[sk.size()] = counts.get(sk.size(), 0) + 1
		for k in sk:
			levels[sk[k] - 1] += 1
		for k in Game.roll_skills(true):
			if not D.SKILLS[k]["player"]:
				player_ok = false
	print("    600 survivors, skills per head: ", counts, "  levels I/II/III: ", levels)
	check(counts.get(1, 0) > 0 and counts.get(2, 0) > 0 and counts.get(3, 0) > 0 and not counts.has(0) and not counts.has(4), "survivors get one to three random skills")
	check(levels[0] > levels[1] and levels[1] > levels[2] and levels[2] > 0, "skills come in three degrees, stronger ones rarer")
	check(player_ok, "you never roll scavenging skills")
	g = Game.new()
	var plain: Dictionary = g.add_survivor("Ada", "pistol", false, {})
	var ace: Dictionary = g.add_survivor("Sol", "pistol", false, {"aim": 3, "quick": 2})
	var ks: Dictionary = g.survivor_stats(plain)
	var ka: Dictionary = g.survivor_stats(ace)
	check(ka["dmg"] > ks["dmg"] and ka["interval"] < ks["interval"], "sharpshooters hit harder and quick hands shoot faster")
	var fixer: Dictionary = g.add_survivor("Lev", "pistol", false, {"repair": 2, "thrift": 3})
	g.wall["hp"] = 100.0
	g.scrap = 100
	g.toggle_repair(3)
	for i in 100:
		g.update_repairs(0.1)
	var fixed: float = g.wall["hp"] - 100.0
	check(absf(fixed - D.REPAIR_PER_SECOND * 1.5 * 10.0) < 1.0, "a handy survivor repairs faster: %d wall in 10 seconds" % int(fixed))
	check(100 - g.scrap < int(fixed / D.WALL_PER_SCRAP) - 5, "a thrifty survivor uses less scrap: %d for %d wall" % [100 - g.scrap, int(fixed)])
	var runner: Dictionary = g.add_survivor("Imke", "pistol", false, {"fleet": 3, "careful": 3})
	check(g.trip_seconds(runner, "police_station") < g.trip_seconds(plain, "police_station"), "fleet-footed survivors make shorter trips")
	check(g.death_chance(runner, "police_station") < g.death_chance(plain, "police_station") * 0.5, "careful survivors are less likely to die")
	check(g.death_chance(plain, "police_station") > 0.0 and g.death_chance(plain, "police_station") < 0.15, "there's a slight chance of dying on a trip")
	var rich := {"scrap": 0, "weapon": 0}
	var poor := {"scrap": 0, "weapon": 0}
	var scrounger := {"skills": {"scrounge": 3}}
	for k in 400:
		var la: Dictionary = g._roll_loot("police_station", scrounger)
		var lb: Dictionary = g._roll_loot("police_station", plain)
		rich["scrap"] += la["scrap"]; poor["scrap"] += lb["scrap"]
		if la["weapon"] != "": rich["weapon"] += 1
		if lb["weapon"] != "": poor["weapon"] += 1
	check(rich["scrap"] > poor["scrap"] * 1.4 and rich["weapon"] > poor["weapon"], "scroungers bring back more")

	# Dying while scavenging.
	g = Game.new()
	var doomed: Dictionary = g.add_survivor("Rosa", "rifle", false, {})
	g.add_survivor("Kofi", "pistol", false, {})
	g.death_mul = 1000.0
	var lost := []
	g.scavenger_lost.connect(func(nm, _site): lost.append(nm))
	var scrap1: int = g.scrap
	g.send_scavenger(1, "gas_station")
	for i in 2000:
		g.update_trip(0.1)
		g.update_walkers(0.1)
		if g.trip == null:
			break
	check(lost == ["Rosa"] and g.crew.size() == 2 and not g.crew.has(doomed), "a scavenger can die and never come back")
	check(g.scrap == scrap1 and not g.looted.has("gas_station"), "nothing comes back, and the place is still there to loot")
	check(g.crew[1]["name"] == "Kofi" and g.crew[1]["state"] == "wall", "the rest of the crew carries on")

	# Food.
	g = Game.new()
	g.add_survivor("Dana", "pistol", false, {})
	g.food = 10.0
	check(absf(g.food_per_minute() - 2 * D.FOOD_PER_MINUTE) < 0.001, "every survivor eats, you included")
	for i in 600:
		g.update_food(0.1)       # one minute
	check(absf(g.food - (10.0 - 2 * D.FOOD_PER_MINUTE)) < 0.01, "the stock drops by the crew's rate each minute")
	g.food = 0.05
	g.crew[0]["skills"] = {}
	for i in 100:
		g.update_food(0.1)
	check(g.hungry and g.food == 0.0 and g.survivor_stats(g.crew[0])["interval"] > D.WEAPONS["pistol"]["rate"], "with no food the crew is hungry and slower")
	g.food = 4.0
	g.update_food(0.1)
	check(not g.hungry, "food coming in ends the hunger")


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
	return {"looted": g.looted.size(), "time": g.time, "kills": g.kills, "crew": weapons, "scrap_spent": g.purchases.size(), "food": g.food, "hungry": g.hungry}
