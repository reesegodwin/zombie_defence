# Measures what costs time: frame times for a night horde with each graphics
# feature on or off, and the game rules alone at different crowd sizes.
# Needs a display (e.g. xvfb-run); from the project folder:
#   godot --path . --script res://tests/perf_check.gd
# On a software renderer the absolute numbers are slow; compare them.
extends SceneTree

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/defs.gd")

var main


func _initialize() -> void:
	_sim_timing()
	root.size = Vector2i(960, 540)
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


## The game rules alone: milliseconds per 1/60 s step.
func _sim_timing() -> void:
	print("Game rules alone (ms per step):")
	for n in [50, 150, 300]:
		var g = Game.new()
		g.apply_meta({"levels": {}, "level": 3})
		g.time = 30.0
		g.update_sides()
		for side in 3:
			g.side_live_at[side] = 0.0
		for i in n:
			g.spawn_zombie("walker", 1.0, 1.0, i % 3, randf_range(-6.0, 12.0))
		var t0 := Time.get_ticks_usec()
		var steps := 300
		for i in steps:
			g.step(1.0 / 60.0)
			while g.zombies.size() > n:
				g.zombies.pop_back()
			while g.zombies.size() < n:
				g.spawn_zombie("walker", 1.0, 1.0, randi() % 3, randf_range(-6.0, 4.0))
		print("  %3d zombies: %.2f ms" % [n, (Time.get_ticks_usec() - t0) / 1000.0 / steps])


func _frames(n: int) -> Array:
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in n:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	return [sum / times.size(), times[int(times.size() * 0.95)]]


func _run() -> void:
	for i in 10:
		await process_frame
	main.progress.map_level = 3
	main.start()
	var g = main.game
	g.time = 220.0      # night
	g.input_auto = true
	for side in 3:
		if not g.sides_open[side]:
			g.open_side(side)
		g.side_live_at[side] = 0.0
	g.scrap = 2000
	_research(g)
	g.buy("turret")
	for i in 150:
		g.spawn_zombie(["walker", "runner", "brute"][i % 3], 50.0, 0.4, i % 3, randf_range(-6.0, 12.0))
	main.rig.zoom = 30.0
	main.rig._apply()
	for i in 30:
		await process_frame
	var env: Environment = main.env
	var level = main.level
	var cases := [
		["everything on (High)", func(): pass],
		["fog off", func(): level.ground_fog.set_quality("Off")],
		["fog Medium", func(): level.ground_fog.set_quality("Medium")],
		["fog Low", func(): level.ground_fog.set_quality("Low")],
		["SSAO off", func(): env.ssao_enabled = false],
		["glow off", func(): env.glow_enabled = false],
		["MSAA off", func(): root.msaa_3d = Viewport.MSAA_DISABLED],
		["sun shadows off", func(): main.moon.shadow_enabled = false],
		["spotlights off", func(): level.spots_enabled(false)],
	]
	print("Graphics presets, 150 zombies at night (avg ms / worst 5%):")
	for q in ["High", "Medium", "Low"]:
		main.settings.graphics = q
		main.settings.fog = q
		main.apply_graphics()
		main.apply_fog()
		for i in 5:
			await process_frame
		var r = await _frames(40)
		print("  %-22s %7.1f  %7.1f" % [q, r[0], r[1]])
	if "--presets-only" in OS.get_cmdline_user_args():
		quit()
		return
	main.settings.graphics = "High"
	main.apply_graphics()
	print("Each feature off in turn, from High (avg ms / worst 5%):")
	for c in cases:
		# Back to everything on, then turn the one thing off.
		level.ground_fog.set_quality("High")
		env.ssao_enabled = true
		env.glow_enabled = true
		root.msaa_3d = Viewport.MSAA_2X
		main.moon.shadow_enabled = true
		level.spots_enabled(true)
		root.scaling_3d_scale = 1.0
		c[1].call()
		for i in 5:
			await process_frame
		var r = await _frames(40)
		print("  %-22s %7.1f  %7.1f" % [c[0], r[0], r[1]])
	quit()


func _research(g) -> void:
	for k in D.RESEARCH:
		g.researched[k] = true
