# Plays the real scene, drives it with simulated mouse input, and saves screenshots.
# Needs a display (e.g. xvfb-run). From the project folder:
#   godot --path . --script res://tests/visual_test.gd -- <output dir>
extends SceneTree

const D = preload("res://scripts/defs.gd")

var main
var out_dir := "user://shots"
var failures := 0


func check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond:
		failures += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(sname: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "/" + sname + ".png")
	print("  saved " + sname)


func mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(e)


var _last_mouse := Vector2.ZERO


func mouse_move(pos: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = pos - _last_mouse
	_last_mouse = pos
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(e)


func drag(a: Vector2, b: Vector2) -> void:
	# Godot 4.7 reads the drop point from the real cursor, so move it too.
	Input.warp_mouse(a)
	await frames(3)
	mouse_move(a, false)
	await frames(2)
	mouse_button(a, true)
	await frames(2)
	for i in range(1, 13):
		mouse_move(a.lerp(b, i / 12.0), true)
		await frames(1)
	Input.warp_mouse(b)
	await frames(3)
	mouse_move(b, true)
	await frames(1)
	mouse_button(b, false)
	await frames(4)


func fast_forward(seconds: float) -> void:
	var g = main.game
	var t := 0.0
	var think := 0.0
	while t < seconds and not g.over:
		g.step(1.0 / 30.0)
		t += 1.0 / 30.0
		think -= 1.0 / 30.0
		if think <= 0.0:
			think = 2.0
			g.auto_scavenge()
			g.auto_shop()


func grid_to_screen(gx: float, gy: float, h := 0.0) -> Vector2:
	return main.rig.world_to_screen(Vector3(gx, h, gy))


func _run() -> void:
	await frames(10)
	await shot("01_title")
	main.start()
	await frames(240)
	await shot("02_early")

	print("Drag and drop")
	var g = main.game
	g.add_to_storage("smg")
	g.add_to_storage("spikes")
	g.add_to_storage("hollow")
	main.hud.toggle_inventory()
	main.paused = true
	await frames(5)
	var slots: Array = main.hud.slots
	var s_smg = slots[0]
	var s_weapon = null
	var s_gear = null
	for s in slots:
		if s.loc["where"] == "weapon" and s.loc["s"] == 0:
			s_weapon = s
		if s.loc["where"] == "gear" and s.loc["s"] == 0 and s.loc["g"] == 0:
			s_gear = s
	await drag(s_smg.get_global_rect().get_center(), s_weapon.get_global_rect().get_center())
	check(g.crew[0]["weapon"] == "smg", "dragging the SMG onto your weapon slot equips it")
	slots = main.hud.slots
	# storage now: pistol, spikes, hollow
	await drag(slots[2].get_global_rect().get_center(), _find(slots, "gear", 0, 0).get_global_rect().get_center())
	check(g.crew[0]["gear"][0] != null and g.crew[0]["gear"][0]["key"] == "hollow", "dragging hollow points onto a gear slot equips them")
	slots = main.hud.slots
	var n_before: int = g.storage["items"].size()
	await drag(slots[0].get_global_rect().get_center(), _find(slots, "gear", 0, 1).get_global_rect().get_center())
	check(g.storage["items"].size() == n_before and g.crew[0]["gear"][1] == null, "a gun cannot be dropped on a gear slot")
	slots = main.hud.slots
	var target := grid_to_screen(9.0, 9.0)
	await drag(slots[1].get_global_rect().get_center(), target)
	check(g.traps.size() == 1, "dragging the spike strip onto the field places it")
	if g.traps.size() == 1:
		check(absf(g.traps[0]["x"] - 9.0) < 0.3 and absf(g.traps[0]["y"] - 9.0) < 0.3, "the trap lands where it was dropped")
		await drag(grid_to_screen(9.0, 9.0), grid_to_screen(12.0, 7.0))
		check(absf(g.traps[0]["x"] - 12.0) < 0.3, "a placed trap can be dragged to a new spot")
	await shot("03_inventory")
	if OS.get_environment("QUICK") != "":
		quit(0)
		return
	main.paused = false
	main.hud.close_inventory()

	print("Manual shooting")
	g.input_auto = false
	for z in g.zombies:
		z["hp"] = 0.0
	g.zombies = []
	var target_z: Dictionary = g.spawn_zombie("walker", 1.0, 0.0)
	target_z["x"] = 11.0
	target_z["y"] = 9.0
	target_z["spd"] = 0.0
	var zp := grid_to_screen(11.0, 9.0, 0.9)
	Input.warp_mouse(zp)
	await frames(3)
	mouse_move(zp, false)
	await frames(2)
	mouse_button(zp, true)
	# Keep the cursor on it, as a player would while it gets knocked back.
	for k in 12:
		await create_timer(0.4).timeout
		if target_z["hp"] <= 0:
			break
		zp = grid_to_screen(target_z["x"], target_z["y"], 0.9)
		mouse_move(zp, true)
	mouse_button(zp, false)
	check(target_z["hp"] <= 0, "holding the mouse on a zombie shoots it dead")
	g.input_auto = true
	print("Aiming")
	g.input_auto = false
	for z in g.zombies:
		z["hp"] = 0.0
	g.zombies = []
	main.paused = true
	var p_in := grid_to_screen(14.0, 6.0)
	Input.warp_mouse(p_in)
	await frames(3)
	mouse_move(p_in, false)
	await frames(6)
	check(main.aim_guide.visible and main.aim_guide.label.visible, "the range arc shows while you play")
	await shot("08_aim_in_range")
	var p_out := grid_to_screen(16.5, 0.6)
	Input.warp_mouse(p_out)
	await frames(3)
	mouse_move(p_out, false)
	await frames(6)
	await shot("08b_aim_out_of_range")
	main.paused = false
	g.input_auto = true
	var zl: Dictionary = g.spawn_zombie("walker", 20.0, 0.0)
	zl["x"] = 6.0
	zl["y"] = 9.0
	await frames(20)
	var you: Dictionary = g.crew[0]
	var want := atan2(zl["y"] - you["y"], zl["x"] - you["x"])
	check(absf(angle_difference(you["aim"], want)) < 0.15, "with auto-fire on you face the zombie you're shooting, not the cursor")
	var upper: Node3D = main.crew_nodes[0].upper
	check(absf(angle_difference(upper.rotation.y, atan2(cos(you["aim"]), sin(you["aim"])))) < 0.05, "the character model turns the same way")
	main.paused = true
	await shot("08c_aim_auto")
	main.paused = false
	zl["hp"] = 0.0
	g.zombies = []

	if OS.get_environment("QUICK2") != "":
		quit(0)
		return
	print("Workshop")
	g.scrap = 200
	await click(main.hud.btn_workshop)
	check(main.hud.workshop.visible, "the workshop button opens the workshop")
	var n_items: int = g.storage["items"].size()
	await click(main.hud._shop_rows["rifle"])
	check(g.storage["items"].size() == n_items + 1 and g.storage["items"][-1]["key"] == "rifle" and g.scrap == 200 - D.SHOP["rifle"]["cost"], "buying a rifle costs scrap and puts it in storage")
	await shot("05_workshop")
	await click(main.hud.btn_workshop)

	print("Scavenging")
	var dana: Dictionary = g.add_survivor("Dana", "pistol", false)
	await frames(5)
	await click(main.hud.btn_map)
	check(main.hud.map_open(), "the scavenge button opens the map")
	var t_before: float = g.time
	await frames(20)
	check(g.time == t_before, "the game waits while the map is open")
	var canvas: Control = main.hud.scav_map.canvas
	var site_pos: Vector2 = canvas.get_global_rect().position + canvas.site_px("hardware_store") + Vector2(0, -8)
	await click_at(site_pos)
	check(main.hud.scav_map.site == "hardware_store", "clicking a place on the map selects it")
	await shot("06_map")
	var scrap0: int = g.scrap
	await click(main.hud.scav_map.send_button)
	check(g.trip != null and g.trip["who"] == dana and not main.hud.map_open(), "Send starts the trip and closes the map")
	# Follow them out through the pass.
	main.rig.position = Vector3(11.5, 0, 24.0)
	while dana["state"] == "leaving" and dana["path_t"] < 0.62:
		g.step(1.0 / 30.0)
		if randf() < 0.15:
			await frames(1)
	await frames(10)
	await shot("07_through_the_pass")
	var seen_away := false
	var guard := 0
	while g.trip != null and guard < 20000:
		g.step(1.0 / 30.0)
		g.zombies.clear()   # keep the wall standing for this check
		if dana["state"] == "away":
			seen_away = true
		guard += 1
	check(seen_away and dana["state"] == "wall", "the scavenger disappears, then comes back to the wall")
	check(g.scrap - scrap0 >= D.SCRAP_TIERS[1][0], "they bring back medium scrap from the hardware store")
	main.rig.reset()
	await frames(5)
	await click(main.hud.btn_map)
	check(main.hud.map_open() and main.hud.scav_map.site != "hardware_store", "reopening the map picks a place that hasn't been looted")
	site_pos = canvas.get_global_rect().position + canvas.site_px("hardware_store") + Vector2(0, -8)
	await click_at(site_pos)
	check(main.hud.scav_map.site == "hardware_store" and main.hud.scav_map.send_button.disabled, "a looted place can be looked at, but nobody can be sent there")
	await shot("06b_map_looted")
	await click(main.hud.scav_map.send_button)
	check(g.trip == null, "pressing Send on a looted place does nothing")
	await click(main.hud.scav_map.get_node("%CloseButton"))

	print("Gameplay")
	fast_forward(110.0)
	await frames(30)
	await shot("04_two_minutes")
	g.add_to_storage("slick")
	g.place_trap(g.storage["items"].size() - 1, 11.0, 10.0)
	g.explode(11.0, 10.0, 70.0, 1.7)
	await frames(4)
	await shot("04b_explosion")
	fast_forward(60.0)
	await frames(20)
	await shot("04c_night")
	fast_forward(1500.0)
	await create_timer(2.5).timeout
	check(g.over and main.hud.over_overlay.visible, "the game-over screen appears when the wall falls")
	await shot("06_game_over")
	main.restart()
	await frames(10)
	check(not main.game.over and main.game.time < 1.0, "restart starts a fresh run")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func click(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	Input.warp_mouse(p)
	await frames(3)
	mouse_move(p, false)
	await frames(2)
	mouse_button(p, true)
	await frames(2)
	mouse_button(p, false)
	await frames(4)


func _find(slots: Array, where: String, s: int, gi: int):
	for x in slots:
		if x.loc["where"] == where and x.loc.get("s", -1) == s and x.loc.get("g", -1) == gi:
			return x
	return null
