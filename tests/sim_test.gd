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
		_fly(g)
	check(z["hp"] <= 0, "five pistol shots kill a walker")
	check(g.kills == 1, "kills are counted")

	# The tutorial's steps: when each is ready, and when it's done.
	var Tut = load("res://scenes/ui/tutorial.gd")
	var gt = Game.new()
	check(not Tut.step_ready("rescue", gt), "tutorial: no rescue hint while you're alone")
	gt.add_survivor("Bea", "pistol", false)
	check(Tut.step_ready("rescue", gt) and not Tut.step_done("rescue", gt), "tutorial: once someone can go, point them at the ranger cabin")
	gt.send_scavenger(1, "ranger_cabin")
	check(Tut.step_done("rescue", gt), "tutorial: done when they set off for the cabin")
	gt.scrap = D.RESEARCH["firearms"]["cost"]
	check(Tut.step_ready("research", gt), "tutorial: research is pointed out once you can afford the SMG")
	gt.start_research("firearms")
	check(Tut.step_done("research", gt), "tutorial: done once research starts")
	gt.research_cur = ""
	gt.researched["firearms"] = true
	check(Tut.step_ready("buy_smg", gt) and not Tut.step_done("buy_smg", gt), "tutorial: SMG researched: point at the workshop")
	gt.add_to_storage("smg")
	check(Tut.step_done("buy_smg", gt) and Tut.step_ready("equip", gt) and not Tut.step_done("equip", gt), "tutorial: built: now hand it out")
	gt.crew[0]["weapon"] = "smg"
	check(Tut.step_done("equip", gt), "tutorial: done when someone holds it")
	gt.walls[0]["hp"] = gt.walls[0]["max_hp"] * 0.4
	gt.scrap = 50
	check(Tut.step_ready("repair", gt) and not Tut.step_done("repair", gt), "tutorial: a battered wall: point at someone to repair it")
	# Building things: research, a turret, the radio; and spending Grit.
	var gb2 = Game.new()
	gb2.researched["firearms"] = true
	gb2.researched["carpentry"] = true
	gb2.scrap = 500
	check(Tut.step_ready("research_build", gb2) and Tut.build_project(gb2) == "turrets", "tutorial: with carpentry done, point out the auto-turret research")
	gb2.start_research("turrets")
	check(Tut.step_done("research_build", gb2), "tutorial: done once it starts")
	gb2.research_cur = ""
	gb2.researched["turrets"] = true
	gb2.researched["radio"] = true
	check(Tut.step_ready("turret", gb2) and not Tut.step_done("turret", gb2), "tutorial: turrets researched: show how to build one")
	check(Tut.step_ready("radio", gb2) and not Tut.step_done("radio", gb2), "tutorial: the radio station too")
	var tspot := Vector2.ZERO
	for x in [8.0, 14.0, 6.0]:
		if gb2.can_build_at("turret", x, D.WALK_Y + 2.2).has("ok"):
			tspot = Vector2(x, D.WALK_Y + 2.2)
			break
	check(gb2.build("turret", tspot.x, tspot.y).has("ok"), "a turret can be put up where the arrow points")
	check(Tut.step_done("turret", gb2), "tutorial: done once a turret stands")
	var prt = load("res://scripts/progress.gd").open("user://test_progress_tut.cfg")
	prt.reset() if prt.has_method("reset") else null
	prt.grit = 0
	check(not Tut.grit_ready(prt), "tutorial: no camp hint with no Grit")
	prt.grit = 500
	check(Tut.grit_ready(prt) and not Tut.grit_done(prt), "tutorial: Grit to spend: point at the camp")
	var cheap := ""
	for id in D.META:
		if prt.can_buy(id).has("ok") and (cheap == "" or prt.next_cost(id) < prt.next_cost(cheap)):
			cheap = id
	prt.buy(cheap)
	check(Tut.grit_done(prt), "tutorial: done once something's bought there")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress_tut.cfg"))
	var grp = Game.new()
	grp.walls[0]["hp"] = grp.walls[0]["max_hp"] * 0.94
	grp.scrap = 20
	grp.add_survivor("Bea", "pistol", false)
	check(Tut.step_ready("repair", grp), "tutorial: the repair tip comes once a wall is 5% down")
	var mid := (D.X0 + D.X1) / 2.0
	check(absf(grp.crew[1]["u"] - mid) <= 2.1 and grp.crew[1]["side"] == 0, "the first of the crew stands near the middle of the front wall (%.1f m off)" % absf(grp.crew[1]["u"] - mid))
	var gmv = Game.new()
	gmv.crew[0]["u"] = mid + 2.0   # you've walked off along the wall
	gmv.add_survivor("Dot", "pistol", false)
	check(absf(gmv.crew[1]["u"] - mid) <= 2.1, "they still go to the middle, wherever you've walked to")
	# Walking through the yard with the dead inside: stop, shoot, walk on.
	var gfw = Game.new()
	var wk: Dictionary = gfw.add_survivor("Ada", "pistol", false)
	var spot_w := Vector2(wk["x"], wk["y"])
	gfw.walls[0]["hp"] = 0.0
	gfw.walls[0]["breached"] = true
	gfw.walls[0]["gap"] = 11.0
	wk["state"] = "moving"
	wk["route"] = [Vector2(11.2, 26.0), Vector2(11.2, 22.5), spot_w]
	wk["path_t"] = 0.6
	var pwk := Game.route_point(wk["route"], 0.6)
	wk["x"] = pwk.x; wk["y"] = pwk.y
	var zin: Dictionary = gfw.spawn_zombie("walker", 1.0, 0.0, 0)
	zin["x"] = pwk.x + 3.0; zin["y"] = pwk.y - 2.0
	zin["inside"] = true
	var twk0: float = wk["path_t"]
	gfw.update_walkers(0.05)
	var held: bool = wk["path_t"] == twk0 and wk.get("fighting", false)
	for i in 40:
		gfw.update_walkers(0.05)
		gfw.update_bullets(0.05)
	check(held and zin["hp"] <= 0, "someone walking back through a breached base stops and shoots the dead in range")
	for i in 400:
		gfw.update_walkers(0.05)
	check(wk["state"] == "wall" and Vector2(wk["x"], wk["y"]).distance_to(spot_w) < 0.1, "then walks on to the wall they were at")
	var prl = load("res://scripts/progress.gd").open("user://test_progress_lv.cfg")
	prl.reset()
	check(prl.reached == 1, "only level 1 can be picked at first")
	prl.reach(2)
	var prl2 = load("res://scripts/progress.gd").open("user://test_progress_lv.cfg")
	check(prl2.reached == 2, "once the truck takes you to level 2 it can be picked, and that's kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress_lv.cfg"))
	var gmov = Game.new()
	gmov.add_survivor("Ada", "pistol", false)
	check(Tut.step_ready("move", gmov) and not Tut.step_done("move", gmov), "tutorial: with someone on the wall, show how to move them")
	gmov.move_survivor(1, 0, 6.0)
	check(Tut.step_done("move", gmov), "tutorial: done once one of the crew is sent somewhere")
	# Its settings: on/off and what's been done carry over, in their own file.
	var tpath := "user://test_settings.cfg"
	var st = load("res://scripts/settings.gd").load_or_detect(tpath)
	st.tutorial = false
	st.tutorial_done = ["walk", "rescue"]
	st.save()
	var st2 = load("res://scripts/settings.gd").load_or_detect(tpath)
	check(st2.tutorial == false and st2.tutorial_done == ["walk", "rescue"], "tutorial settings are saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tpath))

	# Bullets fly: out of the end of the barrel, taking time to get there.
	var gb = Game.new()
	var bt_sh: Dictionary = gb.crew[0]
	var bt_tz: Dictionary = gb.spawn_zombie("walker", 100.0, 0.0)
	bt_tz["x"] = bt_sh["x"]; bt_tz["y"] = bt_sh["y"] - 5.0
	var bt_hp_b: float = bt_tz["hp"]
	gb.fire(bt_sh, bt_tz["x"], bt_tz["y"], 1.0)
	var bt_b0: Dictionary = gb.bullets[0]
	var bt_out := Vector2(bt_b0["x"] - bt_sh["x"], bt_b0["y"] - bt_sh["y"])
	check(bt_out.length() > 0.7 and bt_out.length() < 1.0 and bt_out.normalized().dot(Vector2(0, -1)) > 0.99, "a bullet starts at the end of the barrel, not the body (%.2f m out)" % bt_out.length())
	check(absf(bt_b0["h"] - (D.DECK_H + Game.MUZZLE_UP + Game.Terrain.sample(bt_sh["x"], bt_sh["y"]))) < 0.01, "at gun height, up on the walkway")
	# Its path is a straight line, not bobbing over the ground beneath it.
	var gs = Game.new()
	gs.fire(gs.crew[0], gs.crew[0]["x"] + 3.0, gs.crew[0]["y"] - 40.0, 1.0)
	var hs: Array = []
	for k in 20:
		hs.append(gs.bullets[0]["h"])
		gs.update_bullets(0.02)
	var straight := true
	for k in range(2, hs.size()):
		if absf((hs[k] - hs[k - 1]) - (hs[k - 1] - hs[k - 2])) > 0.001:
			straight = false
	check(straight, "a bullet flies in a straight line")
	check(bt_tz["hp"] == bt_hp_b, "it hasn't hit anything the moment it's fired")
	gb.update_bullets(0.03)
	check(bt_tz["hp"] == bt_hp_b and gb.bullets.size() == 1, "nor a moment later: it's still on its way")
	_fly(gb)
	for k in 4:   # (a stray one can miss)
		gb.fire(bt_sh, bt_tz["x"], bt_tz["y"], 1.0)
		_fly(gb)
	check(bt_tz["hp"] < bt_hp_b and gb.bullets.is_empty(), "then it lands")
	# A miss ends in the dirt, with a little puff where it lands.
	var gpf = Game.new()
	gpf.fire(gpf.crew[0], gpf.crew[0]["x"], gpf.crew[0]["y"] - 6.0, 1.0)
	var parts0: int = gpf.parts.size()
	var flew := 0
	while not gpf.bullets.is_empty() and flew < 200:
		gpf.update_bullets(0.02)
		flew += 1
	check(gpf.parts.size() > parts0 and flew < 100, "a bullet that misses hits the ground (after %d steps) and kicks up a puff" % flew)
	# The ranger cabin: someone radioed for help, and they're always there.
	var gcab = Game.new()
	var always := true
	for i in 30:
		if gcab._roll_loot("ranger_cabin", gcab.crew[0])["survivor"] == "":
			always = false
	check(D.SITES.has("ranger_cabin") and always, "the ranger cabin always has the survivor who radioed for help")
	var grs = Game.new()
	var scout: Dictionary = grs.add_survivor("Bea", "pistol", false)
	grs.death_mul = 0.0   # (they always make it back, for this test)
	grs.send_scavenger(1, "ranger_cabin")
	var guard := 0
	while not grs.crew.any(func(c): return c.get("model", "") == "ranger") and guard < 4000:
		grs.step(0.1)
		grs.zombies.clear()
		scout["hp"] = scout["max_hp"]
		guard += 1
	var rangers: Array = grs.crew.filter(func(c): return c.get("model", "") == "ranger")
	check(rangers.size() == 1 and rangers[0]["weapon"] == "shotgun", "the one rescued from the cabin is the ranger, with a shotgun")
	var Surv = load("res://scenes/actors/survivor.gd")
	var others_plain := true
	for i in 40:
		var lk: Dictionary = Surv.look_of({"id": i, "name": "Kofi", "is_player": false, "skin": Color.WHITE, "jacket": Color.GRAY})
		if lk.get("hat", false) or lk.get("pack", "") != "":
			others_plain = false
	check(others_plain, "nobody else gets the ranger's hat or a pack")

	# A rifle round passes through several, and never hits the same one twice.
	gb.crew[0]["weapon"] = "rifle"
	gb.zombies.clear()
	var bt_line: Array = []
	for k in 4:
		var lz: Dictionary = gb.spawn_zombie("walker", 100.0, 0.0)
		lz["x"] = bt_sh["x"]; lz["y"] = bt_sh["y"] - 6.0 - k * 1.2
		bt_line.append(lz)
	var bt_hp0: float = bt_line[0]["hp"]
	gb.fire(bt_sh, bt_sh["x"], bt_sh["y"] - 8.0, 1.0)
	var bt_steps := 0
	while not gb.bullets.is_empty() and bt_steps < 500:
		gb.update_bullets(0.004)   # tiny bt_steps: each walker crossed many times over
		bt_steps += 1
	var bt_hp_line: float = bt_line[0]["hp"]
	check(bt_line[0]["hp"] < bt_hp0 and bt_line.all(func(lz): return absf(lz["hp"] - bt_hp_line) < 0.01), "a rifle round passes through the line, each hit exactly once (%s)" % str(bt_line.map(func(lz): return snapped(lz["hp"], 0.1))))

	# Walking with WASD: you go where you're steered, round buildings, and
	# never out past the walls or fence.
	var gwk = Game.new()
	var pme: Dictionary = gwk.crew[0]
	var wstart := Vector2(pme["x"], pme["y"])
	pme["aim"] = PI / 2   # facing the way they walk (backwards would be slower)
	for i in 60:
		gwk.walk_player(Vector2(0, 1), 1.0 / 60.0)
	check(pme["y"] > wstart.y + 2.5 and pme["state"] == "wall" and pme.has("post"), "WASD walks you down off the walkway into the yard (%.1f -> %.1f)" % [wstart.y, pme["y"]])
	for i in 600:
		gwk.walk_player(Vector2(0, 1), 1.0 / 60.0)
	check(pme["y"] < D.BASE_Y1 and gwk.walkable(Vector2(pme["x"], pme["y"])), "but not out through the back fence")
	pme["x"] = 2.0; pme["y"] = 17.8   # beside the bunker
	for i in 120:
		gwk.walk_player(Vector2(1, 0), 1.0 / 60.0)
	check(pme["x"] < 3.6, "the bunker's in the way")
	pme["x"] = 11.0; pme["y"] = 17.0
	for i in 200:
		gwk.walk_player(Vector2(0, -1), 1.0 / 60.0)
	check(Game.on_deck(Vector2(pme["x"], pme["y"])) and not pme.has("post") and pme["side"] == 0 and pme["y"] > D.WALL_Y, "walking up onto the front walkway puts you on that wall, not over it")

	# Walking backwards (away from where you aim) is a slower backpedal.
	var gbk = Game.new()
	var bk: Dictionary = gbk.crew[0]
	bk["x"] = 11.0; bk["y"] = 20.0; bk["post"] = Vector2(11, 20)
	bk["aim"] = -PI / 2   # aiming at the front wall (up)
	var y0: float = bk["y"]
	gbk.walk_player(Vector2(0, -1), 0.2)
	var fwd: float = y0 - bk["y"]
	y0 = bk["y"]
	gbk.walk_player(Vector2(0, 1), 0.2)
	var bwd: float = bk["y"] - y0
	check(fwd > 0.6 and absf(bwd / fwd - D.BACKPEDAL) < 0.02, "walking backwards is slower (%.2f vs %.2f m)" % [bwd, fwd])

	# No range cap: a bullet carries on past a gun's reach. Aim gets worse with
	# distance, except with the hunting rifle.
	var pw: Dictionary = D.WEAPONS["pistol"]
	var rw: Dictionary = D.WEAPONS["rifle"]
	check(Game.spread_mul(pw, pw["range"] * 0.4) == 1.0 and Game.spread_mul(pw, pw["range"] * 3.0) > 2.0, "the pistol is accurate close in and much worse far out")
	check(Game.spread_mul(rw, rw["range"] * 4.0) == 1.0, "the hunting rifle holds its aim at any distance")
	var gr = Game.new()
	gr.crew[0]["weapon"] = "rifle"
	var farz: Dictionary = gr.spawn_zombie("walker", 1.0, 1.0)
	farz["x"] = gr.crew[0]["x"]; farz["y"] = gr.crew[0]["y"] - rw["range"] * 2.5
	for i in 6:
		gr.fire(gr.crew[0], farz["x"], farz["y"], 1.0)
		_fly(gr)
	check(farz["hp"] <= 0, "a rifle shot kills a walker well past its listed reach")
	var gp = Game.new()
	var hits := 0
	for i in 200:
		var pz: Dictionary = gp.spawn_zombie("walker", 100.0, 0.0)
		pz["x"] = gp.crew[0]["x"]; pz["y"] = gp.crew[0]["y"] - pw["range"] * 4.0
		var hp0: float = pz["hp"]
		gp.fire(gp.crew[0], pz["x"], pz["y"], 1.0)
		_fly(gp)
		if pz["hp"] < hp0:
			hits += 1
		gp.zombies.clear()
	check(hits > 0 and hits < 160, "pistol shots far past its reach sometimes land, often miss (%d/200)" % hits)

	# With auto-fire on you face what you're shooting, not the cursor; turning
	# onto it takes a moment, and you don't fire till you're lined up.
	g = Game.new()
	g.input_auto = true
	var you: Dictionary = g.crew[0]
	var za: Dictionary = g.spawn_zombie("walker", 1.0, 0.0)
	za["x"] = 9.0; za["y"] = 11.5
	g.input_aim = Vector2(16.0, 9.0)          # cursor off to the right
	you["aim"] = atan2(9.0 - you["y"], 16.0 - you["x"]) + 1.2   # looking well away
	var want := atan2(za["y"] - you["y"], za["x"] - you["x"])
	g.update_crew(0.016)
	check(absf(angle_difference(you["aim"], want)) > 0.3 and g.bullets.is_empty(), "swinging onto a new target takes time, and nobody fires till lined up")
	for i in 90:
		g.update_crew(0.016)
	check(absf(angle_difference(you["aim"], want)) < 0.1, "with auto-fire on you aim at your target, not the cursor")
	g.input_firing = true
	for i in 60:
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
	_research_all(g)
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
	check(not g.buy("smg").has("ok") and g.storage["items"].is_empty(), "nothing in the workshop until it's researched")

	# Research.
	check(not g.start_research("shotguns").has("ok"), "a project needs the ones before it")
	check(g.start_research("firearms").has("ok") and g.scrap == 500 - D.RESEARCH["firearms"]["cost"], "research costs scrap up front")
	check(not g.start_research("spikes").has("ok"), "one project at a time")
	check(not g.is_unlocked("smg"), "nothing unlocks until the research is done")
	var rt := 0.0
	while g.research_cur != "" and rt < 100.0:
		g.update_research(0.1)
		rt += 0.1
	check(g.researched.has("firearms") and absf(rt - D.RESEARCH["firearms"]["time"]) < 0.3, "research takes its time: %.1fs" % rt)
	check(g.is_unlocked("smg") and g.buy("smg").has("ok"), "finished research unlocks things in the workshop")
	check(g.research_state("shotguns") == "open" and g.research_state("rifles") == "locked", "it opens up the next projects")
	var every_shop_item_researchable := true
	for k in D.SHOP:
		if not D.RESEARCH.has(D.SHOP[k].get("needs", "")):
			every_shop_item_researchable = false
	check(every_shop_item_researchable, "every workshop entry is unlocked by a research project")
	var tree_ok := true
	for k in D.RESEARCH:
		for need in D.RESEARCH[k]["needs"]:
			if not D.RESEARCH.has(need):
				tree_ok = false
	check(tree_ok, "every prerequisite in the tree exists")

	# Walls: fence, then wooden wall, then stone wall.
	g = Game.new()
	g.scrap = 1000
	_research_all(g)
	check(g.wall_name() == "Fence" and g.wall["max_hp"] == D.WALL_TIERS[0]["hp"], "the wall starts as a fence")
	check(not g.buy("wall_stone").has("ok"), "stone needs the wooden wall first")
	g.wall["hp"] = 300.0
	check(g.buy("wall_wood").has("ok") and g.wall_name() == "Wooden wall" and g.wall["max_hp"] == D.WALL_TIERS[1]["hp"], "a wooden wall is tougher")
	check(g.wall["hp"] == 300.0 + D.WALL_TIERS[1]["hp"] - D.WALL_TIERS[0]["hp"], "rebuilding patches the wall up by the difference")
	check(g.buy("wall_stone").has("ok") and g.wall_name() == "Stone wall" and not g.buy("wall_stone").has("ok"), "then stone, and that's the top")

	# Turrets.
	g = Game.new()
	g.scrap = 1000
	_research_all(g)
	var t0: int = g.shop_cost("turret")
	check(g.buy("turret").has("ok") and g.turrets.size() == 1 and g.shop_cost("turret") > t0, "turrets can be built, dearer each time")
	for i in D.MAX_TURRETS:
		g.buy("turret")
	check(g.turrets.size() == D.MAX_TURRETS and not g.buy("turret").has("ok"), "there's a limit on turrets")
	var tz: Dictionary = g.spawn_zombie("walker", 1.0, 0.0)
	tz["x"] = 6.0; tz["y"] = 10.0
	for i in 60:
		g.update_turrets(0.1)
		g.update_bullets(0.1)
	check(tz["hp"] <= 0, "turrets shoot the dead on their own")
	var g2 = Game.new()
	var base_t: Dictionary = g2.turret_stats()
	var up_t: Dictionary = g.turret_stats()
	check(up_t["dmg"] > base_t["dmg"] and up_t["rate"] < base_t["rate"] and up_t["range"] > base_t["range"], "turret research makes them hit harder, faster and further")

	# The dead can tear turrets down: from the wall when one stands close behind
	# it, and anywhere once they're inside.
	g = Game.new()
	g.scrap = 1000
	_research_all(g)
	check(g.buy("turret").has("ok"), "a turret goes up in the front corner")
	var tw: Dictionary = g.turrets[0]   # at D.TURRET_SPOTS[0], just behind the front wall's end
	var clawer: Dictionary = g.spawn_zombie("brute", 1.0, 1.0, 0, D.WALL_Y - 0.5)
	clawer["x"] = 4.3
	var wall_hp: float = g.wall["hp"]
	var torn := [false]
	g.turret_destroyed.connect(func(_i): torn[0] = true)
	for i in 600:
		g.update_zombies(0.1)
		if torn[0]:
			break
	check(tw["hp"] < D.TURRET_HP and g.wall["hp"] == wall_hp, "a zombie at the wall claws at a turret right behind it, not the wall")
	check(torn[0] and g.turrets.is_empty(), "and tears it down in the end")
	g = Game.new()
	g.scrap = 1000
	_research_all(g)
	var spot: Vector2 = D.TURRET_SPOTS[2]
	check(g.build("turret", spot.x, spot.y).has("ok"), "a turret goes up in the yard")
	g.crew[0]["state"] = "away"   # nobody else to go for
	var inside: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALK_Y + 1.5)
	inside["x"] = spot.x; inside["y"] = spot.y - 1.6; inside["inside"] = true
	for i in 100:
		g.update_zombies(0.1)
	check(g.turrets.size() == 1 and g.turrets[0]["hp"] < D.TURRET_HP, "the dead inside the base go for a turret when it's the nearest thing")

	# Once a wall's down, the dead go for the people on it, not past them; round
	# the buildings to reach someone behind one; and not all for the same person.
	g = Game.new()
	g.walls[0]["breached"] = true
	you = g.crew[0]
	you["x"] = 11.0; you["y"] = D.WALK_Y
	var breacher: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALL_Y - 1.0)
	breacher["x"] = 11.0
	var furthest := 0.0
	for i in 120:
		g.update_zombies(0.05)
		furthest = maxf(furthest, breacher["y"])
	check(furthest < D.WALK_Y + 0.3, "through a broken wall they go for the crew on it, not past them")
	check(Game.clear_line(Vector2(2.0, 20.0), Vector2(2.0, 26.0)) and not Game.clear_line(Vector2(5.0, 15.6), Vector2(5.0, 20.5)), "the paths know where the buildings are")
	g = Game.new()
	you = g.crew[0]
	you["state"] = "wall"; you["x"] = 5.0; you["y"] = 20.6   # behind the bunker
	var hunter: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALK_Y)
	hunter["x"] = 5.0; hunter["y"] = 15.6; hunter["inside"] = true
	var into_bunker := false
	var bunker: Rect2 = D.BLOCKERS[0]
	for i in 400:
		g.update_zombies(0.05)
		into_bunker = into_bunker or bunker.has_point(Vector2(hunter["x"], hunter["y"]))
	check(not into_bunker and Vector2(hunter["x"] - 5.0, hunter["y"] - 20.6).length() < 1.0, "a zombie inside walks round the bunker to reach someone behind it")
	g = Game.new()
	g.add_survivor("Ann", "pistol", false)
	g.add_survivor("Bo", "pistol", false)
	var pos := [Vector2(6.0, 15.2), Vector2(11.0, 15.2), Vector2(16.0, 15.2)]
	for i in 3:
		g.crew[i]["state"] = "wall"; g.crew[i]["x"] = pos[i].x; g.crew[i]["y"] = pos[i].y
	var picks := {}
	for i in 200:
		var zz: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALK_Y)
		zz["x"] = 6.2; zz["y"] = 16.0; zz["inside"] = true
		var prey = g._choose_prey(zz)
		picks[prey["name"]] = picks.get(prey["name"], 0) + 1
	check(picks.size() >= 2 and picks.get(g.crew[0]["name"], 0) > 100, "most go for the nearest, some spread out to others (%s)" % str(picks))

	# A broken wall has one gap, where it gave way; the rest still stands, so
	# the dead shuffle along the wall to it and squeeze through.
	g = Game.new()
	g.crew[0]["x"] = 6.0; g.crew[0]["y"] = 30.0   # out of the way
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 6.0, 5.0)
	check(g.walls[0]["breached"] and absf(g.walls[0]["gap"] - 6.0) < 0.01, "a broken wall has a gap where it gave way")
	var far: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALL_Y - 2.0)
	far["x"] = 15.0
	var crossed_u := -100.0
	for i in 600:
		g.update_zombies(0.05)
		if far.get("inside", false):
			crossed_u = Game.lane_uv(0, Vector2(far["x"], far["y"])).x
			break

	check(far.get("inside", false) and absf(crossed_u - 6.0) <= D.GAP_HALF, "a zombie down the wall from the gap walks along to it and in through it (crossed at u=%.1f)" % crossed_u)

	# The crew can repair a damaged turret, for scrap.
	g = Game.new()
	g.scrap = 500
	_research_all(g)
	check(g.buy("turret").has("ok"), "a turret to repair")
	var fixt: Dictionary = g.turrets[0]
	fixt["hp"] = 40.0
	var fix_scrap0: int = g.scrap
	var fixr: Dictionary = g.repair_turret(0, 0)
	check(fixr.has("ok"), "a survivor can be sent to repair a turret")
	for i in 600:
		g.update_walkers(0.05)
		g.update_repairs(0.05)
	check(fixt["hp"] >= fixt["max_hp"] and g.scrap < fix_scrap0 and not g.crew[0].has("fix_turret"), "they walk over and repair it to full, for scrap (%d spent)" % (fix_scrap0 - g.scrap))
	check(not g.repair_turret(0, 0).has("ok"), "a turret that's whole doesn't need repairs")

	# Levels: 1 is the front lane only; 2 opens the west on day 3, the east on day 5.
	g = Game.new()
	g.apply_meta({"levels": {}, "level": 1})
	g.time = D.CYCLE * 5.0
	g.update_sides()
	check(g.level == 1 and g.sides_open == [true, false, false], "on level 1 the side lanes never open")
	for i in 300:
		g._spawn_one()
	check(g.zombies.all(func(zz): return zz["side"] == 0), "so on level 1 the dead only come down the front lane")
	var g_l2 = Game.new()
	g_l2.apply_meta({"levels": {}, "level": 2})
	g_l2.time = D.CYCLE * 2.0 + 60.0
	g_l2.update_sides()
	check(g_l2.sides_open == [true, true, false], "on level 2 the west opens on day 3")
	g_l2.time = D.CYCLE * 4.0 + 60.0
	g_l2.update_sides()
	check(g_l2.sides_open == [true, true, true], "and the east on day 5")
	g.kills = 200
	g_l2.kills = 200
	g_l2.time = g.time
	check(g_l2.run_result()["total"] > g.run_result()["total"], "level 2 pays more Grit")
	var lsave = Game.new()
	lsave.from_save(bytes_to_var(var_to_bytes(g.to_save())))
	check(lsave.level == 1 and lsave.open_at[1] == INF, "a saved run remembers its level")

	# After the last night of level 1, the army truck takes everyone to level 2.
	g = Game.new()
	g.apply_meta({"levels": {}, "level": 1})
	g.add_survivor("Bea", "smg", false)
	g.scrap = 333
	g.researched["firearms"] = true
	g.kills = 50
	var called := [0]
	g.truck_coming.connect(func(_n): called[0] += 1)
	g.time = D.WIN_NIGHTS * D.CYCLE - 0.05
	g.step(0.1)
	check(called[0] == 1 and g.evac >= 0.0 and not g.over, "at dawn on day 6 of level 1 the truck comes (the run goes on)")
	g.horde_left = 0   # (the test jumped straight to dawn: no night's horde still queued)
	g.zombies.clear()
	var n_before: int = g.spawned
	for i in 60:
		g.step(0.1)
		g.zombies.clear()   # (nobody's shooting in this test)
	check(not g.truck_waiting() and g.board_truck(0).has("msg") and not g.board_truck(0).has("ok"), "nobody can board before it's parked")
	for i in 60:
		g.step(0.1)
		g.zombies.clear()
	check(g.truck_waiting() and g.level == 1, "the truck parks in the yard and waits")
	for i in 200:
		g.step(0.1)
		g.zombies.clear()
	check(g.truck_waiting() and g.level == 1, "and it doesn't leave until the crew are told to get in")
	check(g.spawned > n_before + 50, "the horde keeps coming while it waits (%d in 32 s)" % (g.spawned - n_before))
	var bea := -1
	for c in g.crew.size():
		if g.crew[c]["name"] == "Bea":
			bea = c
	check(bea >= 0, "Bea is still alive")
	check(g.board_truck(bea).has("ok") and g.crew[bea]["state"] == "boarding", "a survivor can be sent to the truck")
	for i in 150:
		g.step(0.1)
		g.zombies.clear()   # (nobody's shooting in this test)
	check(g.crew[bea]["state"] == "aboard" and g.level == 1 and g.evac_go < 0.0, "they climb in; the truck waits for the rest")
	check(g.board_all().has("ok"), "then everyone's sent")
	for i in 200:
		g.step(0.1)
		g.zombies.clear()
		if g.evac_go >= 0.0:
			break
	var warned := [0]
	var count_warn := func(msg, _kind): if "wall is down" in msg: warned[0] += 1
	g.toast.connect(count_warn)
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 7.0, 50.0)
	g.step(0.1)
	g.toast.disconnect(count_warn)
	check(not g.over and g.walls[0]["breached"], "a wall falling once everyone's in the truck doesn't end the run")
	check(warned[0] == 0, "and there's no 'wall is down' warning then")
	for i in 400:
		g.step(0.1)
		g.zombies.clear()   # (nobody's shooting in this test)
		if g.level == 2:
			break
	check(g.level == 2 and g.day_number() == 1 and g.evac < 0.0, "then everyone's at level 2's base, on day 1")
	check(g.crew.any(func(c): return c["name"] == "Bea" and c["weapon"] == "smg") and g.researched.has("firearms") and g.kills >= 50, "with the crew, their guns, research and kills (%s)" % str(g.crew.map(func(c): return [c["name"], c["weapon"], c["hp"]])))
	check(g.turrets.is_empty() and g.walls.all(func(w): return w["hp"] == w["max_hp"]), "at a fresh base")
	check(g.nights_survived() == D.WIN_NIGHTS, "the nights held so far carry over")
	for lv in [3, 4]:
		g.time = D.WIN_NIGHTS * D.CYCLE - 0.05
		for i in 600:
			g.step(0.1)
			if g.truck_waiting():
				g.board_all()
			if g.level == lv:
				break
		check(g.level == lv and not g.over, "the truck takes them on to level %d" % lv)
	check(g.is_endless() and g.sides_open[0], "level 4 is the endless last stand")
	g.time = D.WIN_NIGHTS * D.CYCLE * 2.0
	g.update_cycle()
	check(not g.over and g.evac < 0.0 and g.nights_survived() > 3 * D.WIN_NIGHTS + D.WIN_NIGHTS, "where no truck ever comes, and every night counts")
	var g_l3 = Game.new()
	g_l3.apply_meta({"levels": {}, "level": 3})
	g_l3.time = 20.0
	g_l3.update_sides()
	check(g_l3.sides_open == [true, true, true], "on level 3 all three lanes open on the first morning")

	# Saving a run and loading it picks up exactly where it was.
	g = Game.new()
	g.spawn_opening()
	g.input_auto = true
	g.scrap = 600
	_research_all(g)
	g.buy("turret")
	for i in 3000:   # 100 s in
		g.step(1.0 / 30.0)
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 9.0, 5.0)
	var some_z: Dictionary = g.spawn_zombie("walker", 1.0, 1.0, 0, D.WALK_Y)
	some_z["inside"] = true
	g.update_zombies(0.05)
	if g.turrets.size() > 0 and g.turrets[0]["hp"] < g.turrets[0]["max_hp"]:
		g.repair_turret(0, 0)
	var saved_run: Dictionary = g.to_save()
	var save_bytes := var_to_bytes(saved_run)   # as it goes to disk
	var gl = Game.new()
	gl.from_save(bytes_to_var(save_bytes))
	check(gl.time == g.time and gl.kills == g.kills and gl.scrap == g.scrap and gl.zombies.size() == g.zombies.size() and gl.crew.size() == g.crew.size(), "a loaded run has the same time, kills, scrap, zombies and crew")
	check(gl.walls[0]["breached"] and gl.walls[0]["gap"] == g.walls[0]["gap"] and gl.turrets.size() == 1 and gl.researched.size() == g.researched.size(), "and the same broken wall, turret and research")
	var linked := true
	for zz in gl.zombies:
		if zz.has("prey") and not (gl.crew.has(zz["prey"]) or gl.turrets.has(zz["prey"])):
			linked = false
	check(linked and gl.wall == gl.walls[0], "who the dead inside are after is linked up again")
	for i in 900:
		gl.step(1.0 / 30.0)
	check(gl.time > g.time + 29.0, "and it plays on from there")

	# The dead come out of the sewer pipes at the end of each lane, then fan out.
	g = Game.new()
	var piped: Dictionary = g.spawn_zombie("walker", 1.0, 1.0)
	var puv: Vector2 = Game.lane_uv(0, Vector2(piped["x"], piped["y"]))
	var near_pipe := false
	for pu in D.PIPES[0]:
		near_pipe = near_pipe or absf(puv.x - pu) < 0.6
	check(near_pipe and absf(puv.y - D.PIPE_SPAWN_V) < 0.01, "new zombies step out of a sewer pipe")
	var want_u: float = piped["tu"]
	for i in 800:   # 40 s: the furthest spot (8.6 m aside) takes ~31 s on the slant
		g.update_zombies(0.05)
	puv = Game.lane_uv(0, Vector2(piped["x"], piped["y"]))
	check(not piped.has("tu") and absf(puv.x - want_u) < 0.6, "and spread out across the lane as they come")
	g = Game.new()
	var fan: Dictionary = g.spawn_zombie("walker", 1.0, 1.0)
	fan["tu"] = Game.lane_uv(0, Vector2(fan["x"], fan["y"])).x + 5.0   # far to one side
	var fastest := 0.0
	var faced := false
	for i in 60:
		var before := Vector2(fan["x"], fan["y"])
		g.update_zombies(0.05)
		fastest = maxf(fastest, before.distance_to(Vector2(fan["x"], fan["y"])) / 0.05)
		faced = faced or fan.has("face")
	var walk: float = D.ZTYPES["walker"]["speed"] * fan["spd"]
	check(fastest <= walk * 1.02 and faced, "fanning out from a pipe they walk at their usual pace, facing the way they go (%.2f vs %.2f m/s)" % [fastest, walk])

	# Scavenger's eye: lucky finds turn up more often.
	var finds_plain := 0
	var finds_eyed := 0
	g = Game.new()
	for i in 3000:
		var lr: Dictionary = g._roll_loot("farmhouse")
		finds_plain += int(lr["weapon"] != "") + int(lr["food"] > 0) + lr["throwables"].size()
	g.scav_eye = 3
	for i in 3000:
		var lr: Dictionary = g._roll_loot("farmhouse")
		finds_eyed += int(lr["weapon"] != "") + int(lr["food"] > 0) + lr["throwables"].size()
	check(finds_eyed > finds_plain * 1.2, "Scavenger's eye finds more (%d finds against %d)" % [finds_eyed, finds_plain])
	g = Game.new()
	var gf = Game.new()
	gf.apply_meta({"levels": {"kit_survivor": 3}, "level": 1})
	check(D.META["kit_survivor"]["costs"].size() == 3 and gf.crew.size() == 4, "A friend goes to level 3: three friends start with you (%d crew)" % gf.crew.size())
	var gbig = Game.new()
	for i in 20:
		gbig.add_survivor(gbig.free_name(), "pistol", false)
	gbig.layout_crew()
	var names := {}
	var spaced := true
	for c in gbig.crew:
		names[c["name"]] = true
		for o in gbig.crew:
			if o != c and Vector2(c["x"], c["y"]).distance_to(Vector2(o["x"], o["y"])) < 0.6:
				spaced = false
	check(gbig.crew.size() == 21 and names.size() == 21, "no cap on survivors, and nobody shares a name (%d)" % gbig.crew.size())
	check(spaced, "a big crew spreads out (the front wall, then the yard) instead of standing in each other")
	gbig.radio = {"x": 5.0, "y": 22.0, "hp": 100.0}
	gbig.first_stranger_done = true
	var n_big: int = gbig.crew.size()
	for i in 4000:
		gbig.update_arrivals(1.0)
		if gbig.crew.size() > n_big:
			break
	check(gbig.crew.size() > n_big, "the radio still brings people in with a big crew")

	g.apply_meta({"levels": {"scav_eye": 2}})
	check(g.scav_eye == 2, "Scavenger's eye bought at the camp carries into a run")
	# Bought in the middle of a run, your skills take hold at once; the kit waits.
	g = Game.new()
	check(g.apply_live("scav_eye", 1) and g.scav_eye == 1, "Scavenger's eye bought mid-run works straight away")
	check(g.apply_live("p_aim", 2) and g.crew[0]["skills"].get("aim", 0) >= 2, "so does a skill of your own")
	var hp_before: float = g.wall["max_hp"]
	check(g.apply_live("tough", 1) and g.wall["max_hp"] > hp_before, "and Tough makes the walls tougher there and then")
	check(not g.apply_live("kit_scrap", 1), "but the starting kit waits for the next run")

	# Molotovs and pipe bombs: one use each, thrown where you click.
	g = Game.new()
	g.scrap = 500
	check(not g.buy("molotov").has("ok") and not g.buy("pipebomb").has("ok"), "throwables need research")
	g.researched["firebombs"] = true
	g.researched["pipebombs"] = true
	check(g.buy("molotov").has("ok") and g.buy("pipebomb").has("ok"), "then they can be built")
	var mol: Dictionary = g.storage["items"][0]
	var pipe: Dictionary = g.storage["items"][1]
	check(not g.move_item({"where": "storage", "i": 0}, {"where": "gear", "s": 0, "g": 0}).has("ok"), "throwables aren't carried, they're thrown")
	check(not g.throw_item(mol["uid"], 11.0, -8.0).has("ok") and g.storage["items"].size() == 2, "you can't throw further than a wall can reach")
	check(g.throw_item(mol["uid"], 11.0, 9.0).has("ok") and g.storage["items"].size() == 1, "a molotov is thrown and used up")
	var pz: Dictionary = g.spawn_zombie("walker", 2.0, 0.0)
	pz["x"] = 9.0; pz["y"] = 10.0
	var php: float = pz["hp"]
	check(g.throw_item(pipe["uid"], 9.0, 10.0).has("ok") and g.storage["items"].is_empty(), "so is a pipe bomb")
	for i in 30:
		g.update_shots(0.1)
	check(pz["hp"] < php - 100.0, "the pipe bomb blows up where it lands")
	var g4 = Game.new()
	g4.researched["firebombs"] = true
	g4.scrap = 100
	g4.buy("molotov")
	g4.throw_item(g4.storage["items"][0]["uid"], 11.0, 9.0)
	for i in 20:
		g4.update_shots(0.1)
	check(g4.fires.size() == 1, "the molotov leaves a fire")
	var thrown_finds := 0
	for k in 400:
		thrown_finds += 1 if g._roll_loot("gas_station")["throwables"].size() > 0 else 0
	check(thrown_finds > 60 and thrown_finds < 200, "scavengers sometimes find molotovs and pipe bombs (%d in 400)" % thrown_finds)

	# Tearing things down for scrap.
	g = Game.new()
	g.add_to_storage("smg")
	g.add_to_storage("hollow")
	g.scrap = 0
	check(g.salvage({"where": "storage", "i": 0}).has("ok") and g.scrap == Game.salvage_value("smg") and g.scrap > 0, "a gun can be torn down for scrap")
	g.move_item({"where": "storage", "i": 0}, {"where": "gear", "s": 0, "g": 0})
	var sc1: int = g.scrap
	check(g.salvage({"where": "gear", "s": 0, "g": 0}).has("ok") and g.crew[0]["gear"][0] == null and g.scrap == sc1 + Game.salvage_value("hollow"), "so can carried gear")
	check(not g.salvage({"where": "weapon", "s": 0}).has("ok"), "but not the gun in someone's hands")

	# Placing buildings.
	g = Game.new()
	g.researched["turrets"] = true
	g.scrap = 1000
	check(not g.build("turret", 11.0, D.WALK_Y).has("ok"), "nothing gets built on a walkway")
	check(not g.build("turret", 5.0, 18.0).has("ok"), "or on the bunker")
	check(not g.build("turret", 11.0, 6.0).has("ok"), "or outside the base")
	var sc0: int = g.scrap
	check(g.build("turret", 6.8, 23.5).has("ok") and g.turrets[0]["x"] == 6.8 and g.scrap == sc0 - D.SHOP["turret"]["cost"], "a turret goes where you put it, for scrap")
	check(not g.build("turret", 7.0, 23.8).has("ok"), "buildings can't overlap")

	# Provisions: food research, cooks and foragers.
	g = Game.new()
	g.add_survivor("Ada", "pistol", false, {})
	g.crew[0]["skills"] = {}
	var eat0: float = g.food_per_minute()
	g.researched["rationing"] = true
	check(absf(g.food_per_minute() - eat0 * 0.75) < 0.001, "rationing: the crew eats 25% less")
	g.crew[1]["skills"] = {"cook": 3}
	check(absf(g.food_per_minute() - eat0 * 0.75 * 0.7) < 0.001, "a cook at the base cuts what everyone eats")
	g.crew[1]["state"] = "away"
	check(absf(g.food_per_minute() - eat0 * 0.75) < 0.001, "but not while they're out scavenging")
	g.food = 10.0
	g.crew[1]["state"] = "wall"
	for i in 600:
		g.update_food(0.1)
	check(absf(g.food - (10.0 - g.food_per_minute())) < 0.01, "the stock drops by what's eaten each minute")
	var plain_finds := 0
	var forager_finds := 0
	var forager_s := {"skills": {"forager": 3}}
	var no_skill := {"skills": {}}
	var g5 = Game.new()
	for k in 600:
		plain_finds += g5._roll_loot("gas_station", no_skill)["food"]
		forager_finds += g5._roll_loot("gas_station", forager_s)["food"]
	check(forager_finds > plain_finds * 1.8, "foragers bring back much more food (%d against %d)" % [forager_finds, plain_finds])
	g5.researched["foraging"] = true
	var never_empty := true
	for k in 200:
		if g5._roll_loot("gas_station", no_skill)["food"] < 1:
			never_empty = false
	check(never_empty, "with Foraging, a trip always brings back some food")
	g5.researched["smokehouse"] = true
	var smoked := 0
	for k in 600:
		smoked += g5._roll_loot("gas_station", no_skill)["food"]
	check(smoked > plain_finds * 1.6, "the Smokehouse stretches what's brought back")
	var g6 = Game.new()
	g6.crew[0]["skills"] = {}
	g6.food = 0.0
	g6.update_food(0.1)
	var starving: float = g6.survivor_stats(g6.crew[0])["interval"]
	g6.researched["kitchen"] = true
	check(g6.survivor_stats(g6.crew[0])["interval"] < starving, "the Field kitchen makes hunger hurt less")
	g6.food = 5.0
	g6.update_food(0.1)
	g6.time = D.DAY_LENGTH + 0.5
	g6.update_cycle()
	check(g6.hot_meal > 0.0 and g6.survivor_stats(g6.crew[0])["interval"] < D.WEAPONS["pistol"]["rate"], "and a hot meal at sundown has everyone shooting faster")

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

	# The pistol reaches both ends of the front wall from your spot.
	g = Game.new()
	var you0: Dictionary = g.crew[0]
	var reach_ok := true
	for type in ["walker", "runner", "brute"]:
		for u in [D.X0, D.X1]:
			var ez: Dictionary = g.spawn_zombie(type, 100.0, 0.0)
			ez["x"] = u; ez["y"] = 0.0
			g.update_zombies(0.0)   # settle it against the wall end
			ez["x"] = u; ez["y"] = D.WALL_Y
			g.update_zombies(0.0)
			var hp1: float = ez["hp"]
			for k in 20:
				g.fire(you0, ez["x"], ez["y"], 1.0)
				_fly(g)
			if ez["hp"] >= hp1:
				reach_ok = false
			g.zombies.clear()
	check(reach_ok, "the pistol hits zombies at either end of the wall")

	# Runs and the camp.
	var Progress = load("res://scripts/progress.gd")
	var pr = Progress.open("user://progress_unit_test.cfg")
	pr.reset()
	check(pr.grit == 0 and pr.levels.is_empty() and pr.max_heat == 0, "progress starts empty")
	var g_short = Game.new()
	g_short.level = 1   # level 1: no extra Grit for the level
	check(g_short.run_result()["total"] == D.GRIT["base"], "even the shortest run pays %d Grit" % D.GRIT["base"])
	check(not pr.buy("kit_scrap").has("ok"), "upgrades cost Grit")
	pr.grit = 500
	check(pr.buy("kit_scrap").has("ok") and pr.level("kit_scrap") == 1 and pr.grit == 500 - D.META["kit_scrap"]["costs"][0], "Grit buys an upgrade level")
	check(pr.next_cost("kit_scrap") == D.META["kit_scrap"]["costs"][1], "the next level costs more")
	check(not pr.buy("bp_turrets").has("ok"), "blueprints follow the research tree")
	pr.buy("kit_smg")
	check(not pr.buy("kit_smg").has("ok"), "one-off upgrades max out")
	var pr2 = Progress.open("user://progress_unit_test.cfg")
	check(pr2.grit == pr.grit and pr2.level("kit_scrap") == 1 and pr2.level("kit_smg") == 1, "progress is saved and loads again")
	var lose := {"total": 30, "won": false, "nights": 3}
	pr.bank(lose)
	check(pr.max_heat == 0 and pr.runs == 1 and pr.best_nights == 3, "a lost run banks its Grit and records")
	pr.bank({"total": 80, "won": true, "nights": D.WIN_NIGHTS})
	check(pr.max_heat == 1 and pr.wins == 1, "a win unlocks the next Heat")
	pr.heat = 0
	pr.bank({"total": 80, "won": true, "nights": D.WIN_NIGHTS})
	check(pr.max_heat == 1, "winning below your highest Heat doesn't unlock more")
	pr.reset()
	check(pr.grit == 0 and pr.levels.is_empty(), "progress can be reset")
	pr.levels = {"bp_farming": 1, "base_farm": 1, "kit_food": 1}
	pr.grit = 5
	pr.save()
	var pr3 = Progress.open("user://progress_unit_test.cfg")
	check(pr3.grit == 75 and not pr3.levels.has("bp_farming") and not pr3.levels.has("base_farm") and pr3.level("kit_food") == 1, "upgrades that were removed from the game are refunded")
	pr.reset()
	# Everything maxed: what a run starts with.
	var all := {}
	for id in D.META:
		all[id] = D.META[id]["costs"].size()
	g = Game.new()
	var base_scrap: int = g.scrap
	var base_cost: int = g.shop_cost("smg")
	g.apply_meta({"levels": all, "heat": 2})
	var me: Dictionary = g.crew[0]
	check(me["skills"].get("aim", 0) == 3 and me["skills"].get("repair", 0) == 3, "bought skills are yours from the start")
	check(me["weapon"] == "smg" and g.scrap == base_scrap + 100 and g.crew.size() == 1 + D.META["kit_survivor"]["costs"].size(), "the starting kit: SMG, scrap and friends")
	check(g.storage["items"].filter(func(it): return it["key"] == "spikes").size() == 4, "and spike strips")
	check(g.researched.has("turrets") and g.researched.has("firearms") and g.research_count == 0, "blueprints start researched (and don't count as research done)")
	check(g.walls[0]["stage"] == 1 and g.walls[2]["max_hp"] == roundf(D.WALL_TIERS[1]["hp"] * 1.3), "wooden walls, made tougher")
	check(g.pantry and g.food == D.START_FOOD + 8.0 + D.PANTRY["food"] and g.turrets.size() == 1 and g.storage["cap"] == 16, "a pantry, a turret and more shelving")
	check(g.shop_cost("smg") < base_cost, "the quartermaster gets better prices")
	var g0 = Game.new()
	g0.time = 400.0
	g.time = 400.0
	check(g.horde_size() > g0.horde_size(), "Heat makes hordes bigger")
	# The radio station.
	g = Game.new()
	g.scrap = 500
	check(not g.buy("radio").has("ok"), "the radio needs research")
	g.researched["radio"] = true
	check(not g.build("radio", 5.0, 18.0).has("ok"), "it can't go on the bunker")
	check(g.build("radio", 17.8, 25.0).has("ok") and g.radio == Vector2(17.8, 25.0), "it's built where you put it")
	check(not g.buy("radio").has("ok"), "there's only one")
	g.first_stranger_done = true
	g.add_survivor("Ada", "pistol", false, {})
	seed(4242)   # a fixed draw: about 10 expected, so it can't fail by bad luck
	var heard := 0
	for i in 18000:   # 30 minutes
		var before: int = g.crew.size()
		g.update_arrivals(0.1)
		if g.crew.size() > before:
			heard += 1
			g.crew.resize(2)
	check(heard >= 3 and heard <= 25, "now and then someone hears it and comes (%d in 30 minutes)" % heard)
	var g7 = Game.new()
	g7.first_stranger_done = true
	g7.add_survivor("Ada", "pistol", false, {})
	for i in 18000:
		g7.update_arrivals(0.1)
	check(g7.crew.size() == 2, "without it, nobody comes while you have a survivor")

	# The first zombies start partway down the lane.
	g = Game.new()
	g.spawn_opening()
	check(g.zombies.size() == D.EARLY_CLOSE, "a run opens with %d zombies already in the lane" % D.EARLY_CLOSE)
	for i in 2:
		g._spawn_one()
	var vs: Array = g.zombies.map(func(zz): return Game.lane_uv(zz["side"], Vector2(zz["x"], zz["y"])).y)
	check(vs[0] > 5.0 and vs[1] > 5.0 and vs[2] < D.LANE_START + 1.0 and vs[3] < D.LANE_START + 1.0, "partway down it; the rest come from the far end")
	check(Game.new().crew[0]["skills"].is_empty(), "you don't start with random skills")

	# Moving anywhere in the base.
	g = Game.new()
	var mv: Dictionary = g.add_survivor("Ada", "pistol", false, {})
	check(not g.move_survivor_to(1, Vector2(11.0, 6.0)).has("ok"), "nobody can be sent out past the wall")
	check(g.move_survivor_to(1, Vector2(9.0, 24.0)).has("ok") and mv["state"] == "moving", "a survivor can be sent anywhere in the base")
	var mt2 := 0.0
	while mv["state"] == "moving" and mt2 < 30.0:
		g.update_walkers(0.1)
		mt2 += 0.1
	check(mv["state"] == "wall" and Vector2(mv["x"], mv["y"]).distance_to(Vector2(9.0, 24.0)) < 0.05, "they walk there and stay")
	g.wall["hp"] = 100.0
	g.scrap = 100
	check(not g.toggle_repair(1).has("ok"), "repairing needs them on a walkway")
	check(g.move_survivor(1, 0, 8.0).has("ok") and not mv.has("post"), "and they can go back up onto one")

	# Salvager: scrap for every kill.
	g = Game.new()
	g.apply_meta({"levels": {"salvager": 1}, "heat": 0})
	var s0: int = g.scrap
	var w1: Dictionary = g.spawn_zombie("walker", 1.0, 0.0)
	var b1: Dictionary = g.spawn_zombie("brute", 1.0, 0.0)
	g.damage(w1, 9999.0)
	g.damage(b1, 9999.0)
	check(g.scrap == s0 + 3, "Salvager: 1 scrap a zombie, 2 for a brute")
	g = Game.new()
	var s1: int = g.scrap
	g.damage(g.spawn_zombie("walker", 1.0, 0.0), 9999.0)
	check(g.scrap == s1, "no scrap for kills without it")

	# Winning: holding out 5 nights on the endless Last Stand counts as a win.
	g = Game.new()
	g.level = D.LEVELS.size()
	g.open_at = D.LEVELS[-1]["open_at"].duplicate()
	g.time = D.WIN_NIGHTS * D.CYCLE - 0.5
	g.update_cycle()
	check(not g.won, "not won the moment before the fifth dawn of the Last Stand")
	g.time += 1.0
	g.update_cycle()
	check(g.won and not g.over and g.nights_survived() == D.WIN_NIGHTS, "the dawn after night %d there wins the run, and it goes on" % D.WIN_NIGHTS)
	g.kills = 100
	var res: Dictionary = g.run_result()
	check(res["parts"]["win"] == D.GRIT["win"] and res["parts"]["nights"] == D.WIN_NIGHTS * D.GRIT["night"] and res["parts"]["kills"] == 5, "a win pays Grit for the win, the nights and the kills")
	g = Game.new()
	g.time = D.CYCLE * 2 + 30.0
	g.heat = 2
	g.level = 1
	var r2: Dictionary = g.run_result()
	check(r2["nights"] == 2 and not r2["won"] and r2["total"] == int(round((D.GRIT["base"] + 2 * D.GRIT["night"]) * (1.0 + 2 * D.HEAT_GRIT))), "a loss pays for the nights held, more at Heat")

	# Magazines and reloading.
	g = Game.new()
	g.input_auto = true
	var shooter: Dictionary = g.crew[0]
	shooter["skills"] = {}
	var mag: int = int(D.WEAPONS["pistol"]["mag"])
	var tank: Dictionary = g.spawn_zombie("brute", 100.0, 0.0)
	tank["x"] = shooter["x"]; tank["y"] = 11.0
	var shots_fired := 0
	var saw_reload := false
	var shots_at_reload := -1
	for i in 600:
		var before: int = shooter.get("ammo", mag)
		g.update_crew(0.02)
		if shooter.get("ammo", mag) < before:
			shots_fired += 1
		if g.is_reloading(shooter) and not saw_reload:
			saw_reload = true
			shots_at_reload = shots_fired
		if saw_reload and not g.is_reloading(shooter):
			break
	check(saw_reload and shots_at_reload == mag, "the pistol reloads after %d shots (%d)" % [mag, shots_at_reload])
	check(not g.is_reloading(shooter) and shooter["ammo"] >= mag - 1, "and comes back with a full magazine")
	g.zombies.clear()
	shooter["ammo"] = mag
	g.start_reload(shooter)
	check(not g.is_reloading(shooter), "a full magazine doesn't need reloading")
	shooter["ammo"] = 3
	check(g.start_reload(shooter) and g.is_reloading(shooter), "you can reload early")
	g.zombies.append(tank)
	var before_ammo: int = shooter["ammo"]
	for i in 10:
		g.update_crew(0.02)
	check(shooter["ammo"] == before_ammo, "nobody shoots while reloading")
	var t_r := 0.0
	while g.is_reloading(shooter) and t_r < 10.0:
		g.update_crew(0.05)
		t_r += 0.05
	check(absf(t_r - D.WEAPONS["pistol"]["reload"]) < 0.25, "a pistol reload takes %.1fs" % t_r)
	g.zombies.clear()
	g.zombies.clear()
	shooter["ammo"] = 2
	for i in 60:
		g.update_crew(0.05)
	check(shooter["ammo"] == mag or g.is_reloading(shooter), "with nothing to shoot they top the magazine up")
	g.add_to_storage("smg")
	g.move_item({"where": "storage", "i": 0}, {"where": "weapon", "s": 0})
	g.update_crew(0.01)
	check(shooter["ammo"] == int(D.WEAPONS["smg"]["mag"]) and not g.is_reloading(shooter), "a newly equipped gun comes loaded")
	var quick: Dictionary = {"weapon": "pistol", "is_player": false, "gear": [null, null], "skills": {"quick": 3}}
	var slow: Dictionary = {"weapon": "pistol", "is_player": false, "gear": [null, null], "skills": {}}
	check(g.survivor_stats(quick)["reload"] < g.survivor_stats(slow)["reload"], "quick hands reload faster")

	# Side lanes open later, and the dead come from there too.
	g = Game.new()
	check(g.sides_open == [true, false, false], "only the front is open at first")
	for i in 600:
		g.update_director(0.1)
	var sides_used := {}
	for zz in g.zombies:
		sides_used[zz["side"]] = true
	check(sides_used.keys() == [0], "early on the dead only come from the front")
	g.time = D.SIDE_OPEN_AT[1] - 1.0
	g.update_sides()
	check(not g.sides_open[1], "the west is still dark just before its time")
	g.time = D.SIDE_OPEN_AT[2] + 1.0
	g.update_sides()
	check(g.sides_open == [true, true, true], "then the west and east open up")
	check(D.SIDE_OPEN_AT[1] > D.CYCLE * 2 and D.SIDE_OPEN_AT[1] < D.CYCLE * 2 + D.DAY_LENGTH, "the west opens on day 3")
	check(D.SIDE_OPEN_AT[2] > D.CYCLE * 4 and D.SIDE_OPEN_AT[2] < D.CYCLE * 4 + D.DAY_LENGTH, "the east opens on day 5")
	g.zombies.clear()
	for i in 300:
		g._spawn_one()
	check(g.zombies.all(func(zz): return zz["side"] == 0), "a newly opened lane gives you time before the dead come")
	g.time += D.SIDE_GRACE + 1.0
	g.zombies.clear()
	for i in 300:
		g._spawn_one()
	sides_used = {}
	for zz in g.zombies:
		sides_used[zz["side"]] = true
	check(sides_used.size() == 3, "once open, all three lanes send the dead")
	var wz: Dictionary = g.spawn_zombie("brute", 1.0, 1.0, 1)
	var west0: float = g.walls[1]["hp"]
	var front0: float = g.walls[0]["hp"]
	g.zombies = [wz]
	for i in 3000:
		g.update_zombies(1.0 / 30.0)
	check(g.walls[1]["hp"] < west0 and g.walls[0]["hp"] == front0, "a zombie in the west lane walks to the west wall and hits it")
	var lane_spot: Vector2 = Game.lane_point(1, -21.0, 8.0)
	check(g.trap_ground(lane_spot.x, lane_spot.y) and not g.trap_ground(11.0, 20.0), "traps can go in the side lanes, not in the yard")
	# A wall breaks: the dead get in and go for the crew.
	g = Game.new()
	g.crew[0]["skills"] = {}
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 11.0, 5.0)
	check(g.walls[0]["breached"] and not g.over, "a broken wall doesn't end the run by itself")
	var biter: Dictionary = g.spawn_zombie("brute", 50.0, 1.0, 0, D.WALL_Y - 1.0)
	biter["x"] = g.crew[0]["x"]
	var bt := 0.0
	while not biter.get("inside", false) and bt < 20.0:
		g.update_zombies(0.05)
		bt += 0.05
	check(biter.get("inside", false), "the dead walk through the gap into the base")
	var you_hp: float = g.crew[0]["hp"]
	for i in 200:
		g.update_zombies(0.05)
	check(g.crew[0]["hp"] < you_hp, "and attack the crew")
	for i in 2000:
		g.update_zombies(0.05)
		g.update_health(0.05)
		if g.over:
			break
	check(g.crew[0]["state"] == "dead" and g.over, "when nobody in the base is left alive, the run is over")
	g = Game.new()
	var helper: Dictionary = g.add_survivor("Ada", "pistol", false, {})
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 11.0, 5.0)
	g.hurt_survivor(g.crew[0], 9999.0)
	g.update_health(0.1)
	check(g.crew[0]["state"] == "dead" and not g.over, "if you fall, the crew fights on")
	g.hurt_survivor(helper, 9999.0)
	g.update_health(0.1)
	check(not g.crew.has(helper) and g.over, "until they've all fallen too")
	g = Game.new()
	g.add_survivor("Ada", "pistol", false, {"repair": 3})
	g.walls[0]["hp"] = 1.0
	g.hit_wall(0, 11.0, 5.0)
	g.scrap = 500
	g.toggle_repair(1)
	for i in 600:
		g.update_repairs(0.1)
		if not g.walls[0]["breached"]:
			break
	check(not g.walls[0]["breached"] and g.walls[0]["hp"] >= g.walls[0]["max_hp"] * D.PATCH_AT, "repairing a broken wall far enough closes the gap")
	g = Game.new()
	var hurt: Dictionary = g.crew[0]
	hurt["hp"] = 40.0
	for i in 100:
		g.update_health(0.1)
	check(hurt["hp"] > 40.0, "survivors recover when no zombie is near")

	# Moving survivors.
	g = Game.new()
	var mover: Dictionary = g.add_survivor("Ada", "pistol", false, {})
	check(mover["side"] == 0 and absf(mover["y"] - D.WALK_Y) < 0.01, "newcomers stand on the front wall")
	check(g.move_survivor(1, 2, 21.0).has("ok") and mover["state"] == "moving", "a survivor can be sent to another wall")
	var mt := 0.0
	while mover["state"] == "moving" and mt < 30.0:
		g.update_walkers(0.1)
		mt += 0.1
	var at: Vector2 = Game.lane_point(2, 21.0, D.WALK_Y)
	check(mover["state"] == "wall" and Vector2(mover["x"], mover["y"]).distance_to(at) < 0.05 and mt > 3.0, "they walk there and take up their spot (%.1fs)" % mt)
	var ez2: Dictionary = g.spawn_zombie("walker", 1.0, 0.0, 2)
	g.sides_open[2] = true
	ez2["x"] = at.x - 4.0; ez2["y"] = at.y
	for i in 60:
		g.update_crew(0.1)
		g.update_bullets(0.1)
	check(ez2["hp"] <= 0, "and shoot what comes at their new wall")
	g.walls[2]["hp"] = 100.0
	g.scrap = 50
	var front_hp: float = g.walls[0]["hp"]
	g.toggle_repair(1)
	for i in 20:
		g.update_repairs(0.1)
	check(g.walls[2]["hp"] > 100.0 and g.walls[0]["hp"] == front_hp, "they repair the wall they're on")
	check(g.move_survivor(0, 0, 6.0).has("ok"), "you can move yourself along the wall too")

	# Lulls.
	g = Game.new()
	g.time = D.FIRST_LULL + 0.5
	g.update_lulls()
	check(g.in_lull(), "a lull comes along")
	var spawned := 0
	var spawned_lull := 0
	var g3 = Game.new()
	g3.time = 300.0
	g3.next_lull = 9999.0
	g.time = 300.0
	g.lull_until = 330.0
	for i in 200:
		g.update_director(0.1)
		g3.update_director(0.1)
	spawned_lull = g.zombies.size()
	spawned = g3.zombies.size()
	check(spawned_lull >= 1 and spawned_lull <= 7 and spawned >= spawned_lull * 2, "during a lull only a straggler every few seconds (%d in 20s, against %d)" % [spawned_lull, spawned])
	var early: float = Game.spawn_rate(60.0)
	check(Game.spawn_rate(300.0) < early * 5.0 and Game.hp_mul(300.0) < 2.0, "the night gets harder gradually (spawns x%.1f, health x%.1f at 5:00)" % [Game.spawn_rate(300.0) / early, Game.hp_mul(300.0)])
	g = Game.new()
	g.time = D.DAY_LENGTH - 25.0
	g.next_lull = g.time - 1.0
	g.update_lulls()
	check(not g.in_lull(), "no lull starts just before nightfall")

	# Day and night.
	g = Game.new()
	check(not g.is_night() and g.day_number() == 1, "the run starts in the day")
	var day_spawned := 0
	var night_spawned := 0
	while g.time < D.DAY_LENGTH - 1.0:
		g.update_director(0.1)
	g.update_cycle()
	check(g.horde_left == 0 and not g.is_night() and g.night > 0.5, "no horde by day, and dusk falls before night")
	check(g._cycle_done.has("dusk1"), "a warning comes before nightfall")
	g.zombies.clear()
	g.time += 1.5
	g.update_cycle()
	check(g.is_night() and g.horde_left == g.horde_size() and g.night > 0.99, "the horde comes when night falls (%d of them)" % g.horde_left)
	g.horde_left = 0
	g.zombies.clear()
	for i in 300:
		g.update_director(0.1)
	night_spawned = g.zombies.size()
	for i in 300:
		g.update_director(0.1)
	check(g._cycle_done.has("midnight1"), "a second wave comes at midnight")
	var gw = Game.new()
	gw.time = D.CYCLE - D.NIGHT_WIND_DOWN + 1.0
	gw.horde_left = 40
	gw.update_director(0.1)
	check(gw.horde_left == 0, "the horde stops coming %d s before dawn" % int(D.NIGHT_WIND_DOWN))
	var gd = Game.new()
	gd.time = D.CYCLE + 20.0
	gd.next_lull = 9999.0
	for i in 300:
		gd.update_director(0.1)
	day_spawned = gd.zombies.size()
	check(night_spawned > day_spawned * 1.3, "nights are much busier than days (%d against %d in 30s)" % [night_spawned, day_spawned])
	check(not gd.is_night() and gd.day_number() == 2 and gd.night == 0.0, "then dawn, and day 2")

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
	g.crew[0]["skills"] = {}
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
	g.spawn_opening()
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


func _research_all(g) -> void:
	for k in D.RESEARCH:
		g.researched[k] = true


## Lets every bullet in flight land (or fly off).
func _fly(g) -> void:
	var n := 0
	while not g.bullets.is_empty() and n < 400:
		g.update_bullets(0.02)
		n += 1
