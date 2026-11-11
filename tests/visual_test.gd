# Plays the real scene, drives it with simulated mouse input, and saves screenshots.
# Needs a display (e.g. xvfb-run). From the project folder:
#   godot --path . --script res://tests/visual_test.gd -- <output dir>
extends SceneTree

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
	while t < seconds and not g.over:
		if not g.cards.is_empty():
			main.choose_card(randi() % g.cards.size())
			g.auto_equip()
			continue
		g.step(1.0 / 30.0)
		t += 1.0 / 30.0


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
	await create_timer(2.5).timeout
	mouse_button(zp, false)
	check(target_z["hp"] <= 0, "holding the mouse on a zombie shoots it dead")
	g.input_auto = true
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
	if g.over:
		main.restart()
		g = main.game
		await frames(5)
	if not g.cards.is_empty():
		main.choose_card(0)
	g.xp = g.xp_next
	await frames(10)
	check(main.hud.cards_overlay.visible, "the level-up cards appear")
	await shot("05_cards")
	main.choose_card(0)
	await frames(5)
	fast_forward(1500.0)
	await create_timer(2.5).timeout
	check(g.over and main.hud.over_overlay.visible, "the game-over screen appears when the wall falls")
	await shot("06_game_over")
	main.restart()
	await frames(10)
	check(not main.game.over and main.game.time < 1.0, "restart starts a fresh run")
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _find(slots: Array, where: String, s: int, gi: int):
	for x in slots:
		if x.loc["where"] == where and x.loc.get("s", -1) == s and x.loc.get("g", -1) == gi:
			return x
	return null
