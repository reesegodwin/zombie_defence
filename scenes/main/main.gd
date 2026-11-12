# Runs the game: owns the simulation (scripts/game.gd), keeps the 3D scene in
# step with it, sets the mood of the night, and turns input into actions.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Game = preload("res://scripts/game.gd")
const Turret = preload("res://scenes/actors/turret.gd")
const Radio = preload("res://scenes/actors/radio.gd")
const Settings = preload("res://scripts/settings.gd")
const Progress = preload("res://scripts/progress.gd")
const Terrain = preload("res://scripts/terrain.gd")
const Saves = preload("res://scripts/saves.gd")
const Truck = preload("res://scenes/actors/truck.gd")

@export var zombie_scene: PackedScene
@export var survivor_scene: PackedScene
@export var trap_scenes: Dictionary = {}   # trap key -> PackedScene

@onready var level: Node3D = $Level
@onready var wall: Node3D = $Level/Wall
@onready var walls: Array = [$Level/Wall, $Level/WallWest, $Level/WallEast]
@onready var moon: DirectionalLight3D = $Moon
@onready var env: Environment = $WorldEnvironment.environment
@onready var rig: Node3D = $CameraRig
@onready var zombies_root: Node3D = $Actors/Zombies
@onready var crew_root: Node3D = $Actors/Crew
@onready var traps_root: Node3D = $Actors/Traps
@onready var effects: Node3D = $Effects
@onready var preview: MeshInstance3D = $PlacePreview
@onready var aim_guide: MeshInstance3D = $AimGuide
@onready var hud: CanvasLayer = $HUD
@onready var sfx: Node = $Sfx

var game
var started := false
var paused := false
var zombie_nodes := {}     # zombie id -> node
var crew_nodes := {}           # survivor id -> node
var trap_nodes := {}       # trap uid -> node
var hover_trap_uid := -1
var turret_nodes: Array = []   # one per built turret, in build order
var radio_node: Node3D = null
var buildings_root: Node3D
var selected_id := -1          # id of the survivor picked to move, or -1
var group_ids: Array = []      # others picked with them by dragging a box (ids)
var _box_start = null          # screen point where a selection drag began, or null
var _box: Panel                # the box drawn while dragging
var placing := ""              # "turret" or "radio" while choosing where to build one
var throwing := -1             # uid of the molotov or pipe bomb being aimed, or -1
var settings                   # display settings (scripts/settings.gd)
var progress                   # Grit and camp upgrades (scripts/progress.gd)

var _mouse_screen = null   # last cursor position over the battlefield
var _panning := false
var _press_trap := false
var _over_handled := false
var hover_survivor := -1
var _clock := 0.0


func _ready() -> void:
	randomize()
	buildings_root = Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)
	rig.bounds = Rect2(-26, -16, 76, 52)   # room to look down every lane
	hud.main = self
	settings = Settings.load_or_detect()
	_apply_settings.call_deferred()
	# Test scripts keep their own progress file, so they never touch the player's.
	var testing := "--script" in OS.get_cmdline_args()
	progress = Progress.open("user://progress_test.cfg" if testing else "user://progress.cfg")
	if testing:
		progress.reset()
		Saves.dir = "user://saves_test/"
	_new_game()


## A fresh run (from the camp's upgrades), or, given a saved run's data, that
## run picked up where it was.
func _new_game(saved := {}) -> void:
	game = Game.new()
	if saved.is_empty():
		game.apply_meta(progress.meta())
		game.spawn_opening()
	else:
		game.from_save(saved)
	game.toast.connect(func(t, k): hud.toast(t, k))
	game.sound.connect(func(n): sfx.play(n))
	game.inv_changed.connect(func(): hud.on_inv_changed())
	game.wall_breached.connect(func(side, u):
		walls[side].collapse(u)
		rig.shake = maxf(rig.shake, 1.0))
	game.wall_patched.connect(func(side): walls[side].reset())
	game.side_opened.connect(func(_side): rig.shake = maxf(rig.shake, 0.3))
	game.turret_destroyed.connect(func(i):
		if i < turret_nodes.size():
			turret_nodes[i].collapse()
			turret_nodes.remove_at(i))
	game.exploded.connect(func(_x, _y, _r): rig.shake = maxf(rig.shake, 0.6))
	effects.bind(game)
	game.level_started.connect(_on_level_started)
	game.new_day.connect(func(n): hud.banner("DAY %d" % n, D.LEVELS[game.level - 1]["name"]))
	_clear_scene()
	selected_id = -1
	group_ids.clear()
	placing = ""
	throwing = -1
	preview.visible = false
	_over_handled = false
	_was_night = game.is_night()
	# A loaded run's broken walls lie broken.
	for side in game.walls.size():
		if game.walls[side].get("breached", false):
			walls[side].collapse(game.walls[side].get("gap", 11.0))


## Clears the 3D scene of the run's things (the dead, people, traps, turrets,
## the radio, effects) and stands the walls back up; it refills from the game.
func _clear_scene() -> void:
	for n in zombies_root.get_children():   # the living, and the bodies still lying about
		n.queue_free()
	zombie_nodes.clear()
	for n in crew_nodes.values():
		n.queue_free()
	crew_nodes.clear()
	for n in trap_nodes.values():
		n.queue_free()
	trap_nodes.clear()
	for n in turret_nodes:
		n.queue_free()
	if radio_node != null:
		radio_node.queue_free()
		radio_node = null
	turret_nodes.clear()
	effects.clear()
	for w in walls:
		w.reset()
	level.set_level(game.open_at)


# --- Saving and loading -----------------------------------------------------------
var _was_night := false
var truck: Node3D = null
var _fade: ColorRect = null


## The truck, driving in or parked, while the game's evac clock runs; and a
## fade to black just before it leaves.
func _sync_truck() -> void:
	if game.evac >= 0.0:
		if truck == null:
			truck = Truck.new()
			buildings_root.add_child(truck)
		truck.at(game.evac, game.evac_go)
		_fade_to(clampf((game.evac_go - Game.TRUCK_OUT) / (Game.TRUCK_GONE - Game.TRUCK_OUT), 0.0, 1.0) if game.evac_go >= 0.0 else 0.0)
	elif truck != null:
		truck.queue_free()
		truck = null


func _fade_to(a: float) -> void:
	if _fade == null:
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_fade)
	_fade.color.a = a


## The crew have arrived at the next level's base: clear away the old one.
func _on_level_started(_lv: int) -> void:
	_clear_scene()
	if truck != null:
		truck.queue_free()
		truck = null
	_fade_to(1.0)
	hud.banner("DAY 1", D.LEVELS[game.level - 1]["name"])
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_method(_fade_to, 1.0, 0.0, 1.2)
	save_run("auto")


## Saves the run in progress to a slot (see scripts/saves.gd). True if it did.
func save_run(slot: String) -> bool:
	if not started or game.over:
		return false
	return Saves.write(slot, game)


## Picks up a saved run. It starts paused, so you can find your feet.
func load_run(slot: String) -> void:
	var d := Saves.read(slot)
	if d.is_empty():
		hud.toast("There's no saved run there.", "danger")
		return
	hud.close_camp()
	hud.hide_game_over()
	hud.close_inventory()
	_new_game(d["run"])
	started = true
	paused = true
	rig.reset()
	hud.hide_title()
	hud.close_saves()
	hud.toast("%s loaded: day %d. Press P to carry on." % [Saves.NAMES[slot], game.day_number()], "good")


## Back to the title screen. The run is kept in the autosave.
func quit_to_title() -> void:
	if started and not game.over:
		save_run("auto")
	started = false
	paused = false
	game.input_firing = false
	cancel_actions()
	hud.close_saves()
	hud.show_title()


## Fits the window to the player's screen (only when playing the game itself,
## not when a test drives the scene).
func _apply_settings() -> void:
	apply_graphics()
	apply_fog()
	if get_tree().current_scene == self:
		settings.apply(get_tree())


## Graphics: Low / Medium / High (Options). Measured with tests/perf_check.gd:
## anti-aliasing, the fog, the spotlights and the sun's shadows cost the most.
func apply_graphics() -> void:
	var q: String = settings.graphics
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if q == "High" else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q == "High" else Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = 0.8 if q == "Low" else 1.0
	RenderingServer.directional_shadow_atlas_set_size({"High": 4096, "Medium": 2048, "Low": 1024}[q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality({"High": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"Medium": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "Low": RenderingServer.SHADOW_QUALITY_HARD}[q])
	moon.directional_shadow_max_distance = 80.0 if q == "High" else 45.0
	env.ssao_enabled = q != "Low"
	env.glow_enabled = q != "Low"
	level.spot_detail(q != "Low")


## Rebuilds the ground fog at the quality picked in Options.
func apply_fog() -> void:
	if level.ground_fog != null and level.ground_fog.quality != settings.fog:
		level.ground_fog.set_quality(settings.fog)


func start() -> void:
	_new_game()   # with whatever was just bought at the camp
	started = true
	hud.close_camp()
	hud.hide_title()
	hud.toast("They're coming from the tree line. Hold the wall.")
	hud.banner("DAY 1", D.LEVELS[game.level - 1]["name"])


## From the camp, the title or the game-over screen: a fresh run.
func new_run() -> void:
	if started:
		restart()
	else:
		start()


func restart() -> void:
	hud.close_camp()
	hud.hide_game_over()
	hud.close_inventory()
	if hud.map_open():
		hud.toggle_map()
	if hud.workshop.visible:
		hud.toggle_workshop()
	if hud.research_open():
		hud.toggle_research()
	_new_game()
	paused = false
	rig.reset()
	hud.toast("Again. Hold the wall.")
	hud.banner("DAY 1", D.LEVELS[game.level - 1]["name"])


func toggle_pause() -> void:
	if started and not game.over:
		paused = not paused


## Everyone into the back of the army truck.
func board_all() -> void:
	if not started or game.over:
		return
	var r: Dictionary = game.board_all()
	if r.get("msg", "") != "":
		hud.toast(r["msg"], "info" if r.has("ok") else "danger")
	cancel_actions()


## The ground under the truck while it waits in the yard (for clicks).
static func on_truck(p: Vector2) -> bool:
	return absf(p.x - Game.TRUCK_STOP.x) < 1.4 and p.y > Game.TRUCK_BOARD.y - 0.6 and p.y < Game.TRUCK_STOP.y + 3.2


func toggle_sound() -> void:
	sfx.muted = not sfx.muted


# --- Loop -------------------------------------------------------------------
func _process(dt: float) -> void:
	_clock += dt
	_keyboard_pan(dt)
	if started:
		_update_aim()
		# The world waits while you study the scavenging map.
		if not paused and not hud.map_open() and not hud.research_open() and not hud.options_open() and not hud.camp_open() and not hud.saves_open():
			game.step(minf(dt, 0.05))
	# Autosave every dawn.
	if started and not game.over:
		var night_now: bool = game.is_night()
		if _was_night and not night_now and save_run("auto"):
			hud.toast("Dawn. Autosaved.", "info")
		_was_night = night_now
	if game.over and not _over_handled:
		_over_handled = true
		Saves.erase("auto")   # a finished run can't be picked up again
		game.input_firing = false
		hud.close_inventory()
		if hud.map_open():
			hud.toggle_map()
		if hud.research_open():
			hud.toggle_research()
		rig.shake = 1.2 if not game.won else 0.0
		var result: Dictionary = game.run_result()
		result["unlocked"] = progress.bank(result)
		# A win gets its moment; a loss goes straight to the camp.
		get_tree().create_timer(1.6 if game.won else 2.5).timeout.connect(func(): if game.over: hud.show_game_over(result))
	rig.shake = maxf(rig.shake, game.shake * 0.6)
	_sync_scene(dt)
	_sync_truck()
	_set_mood()
	hud.update_hud()


func _sync_scene(dt: float) -> void:
	# Zombies.
	var seen := {}
	for z in game.zombies:
		var id: int = z["id"]
		seen[id] = true
		var node = zombie_nodes.get(id)
		if node == null:
			node = zombie_scene.instantiate()
			zombies_root.add_child(node)
			node.setup(z)
			zombie_nodes[id] = node
		else:
			node.sync(z, dt)
	for id in zombie_nodes.keys():
		if not seen.has(id):
			zombie_nodes[id].die()
			zombie_nodes.erase(id)
	# Crew.
	var here := {}
	for i in game.crew.size():
		var s: Dictionary = game.crew[i]
		here[s["id"]] = true
		var n = crew_nodes.get(s["id"])
		if n == null:
			n = survivor_scene.instantiate()
			crew_root.add_child(n)
			n.setup(s)
			crew_nodes[s["id"]] = n
		n.hovered = i == hover_survivor
		n.selected = s["id"] == selected_id or group_ids.has(s["id"])
		n.sync(s, dt)
	group_ids = group_ids.filter(func(gid): return game.crew.any(func(c): return c["id"] == gid and c["state"] in ["wall", "moving"]))
	if selected_index() < 0:
		selected_id = -1
		if not group_ids.is_empty():
			selected_id = group_ids.pop_front()
	for id in crew_nodes.keys():
		if not here.has(id):   # lost out scavenging
			crew_nodes[id].queue_free()
			crew_nodes.erase(id)
	# Traps.
	var alive := {}
	for t in game.traps:
		var uid: int = t["uid"]
		alive[uid] = true
		var tn = trap_nodes.get(uid)
		if tn == null:
			tn = trap_scenes[t["key"]].instantiate()
			traps_root.add_child(tn)
			tn.setup(t)
			trap_nodes[uid] = tn
		tn.sync(t, uid == hover_trap_uid)
	for uid in trap_nodes.keys():
		if not alive.has(uid):
			trap_nodes[uid].queue_free()
			trap_nodes.erase(uid)
	# The radio station and turrets, as they get built.
	if game.radio != null and radio_node == null:
		radio_node = Radio.new()
		radio_node.position = Vector3(game.radio.x, 0, game.radio.y)
		buildings_root.add_child(radio_node)
	while turret_nodes.size() < game.turrets.size():
		var tn := Turret.new()
		buildings_root.add_child(tn)
		turret_nodes.append(tn)
	for i in turret_nodes.size():
		turret_nodes[i].sync(game.turrets[i], game)
	# Rock in the mountain pass turns see-through around anyone walking it.
	var walkers: Array = []
	for s in game.crew:
		if not s["state"] in ["wall", "away", "aboard"] and s["y"] > D.BASE_Y1 - 1.0:
			walkers.append(Vector3(s["x"], 0.0, s["y"]))
	if truck != null and truck.position.z > D.BASE_Y1 - 1.0:
		walkers.push_front(Vector3(truck.position.x, 0.0, truck.position.z))
	var none := Vector3(0, -100, 0)
	RenderingServer.global_shader_parameter_set("walker_a", walkers[0] if walkers.size() > 0 else none)
	RenderingServer.global_shader_parameter_set("walker_b", walkers[1] if walkers.size() > 1 else none)
	for w in walls:
		w.sync(game, _clock)
	var cursor = rig.screen_to_ground(_mouse_screen) if _mouse_screen != null else null
	aim_guide.visible = false   # no targeting circle on the ground
	effects.sync(game)
	level.set_darkness(_darkness(), dt)
	level.update_lights([game.side_live(0), game.side_live(1), game.side_live(2)], dt)


func _darkness() -> float:
	return game.night


# Day, dusk and night each have their own light; the cycle blends between them.
const DAY_MOOD := {"sun": 0.82, "sun_col": Color(1.0, 0.93, 0.82), "amb": 0.58, "fog": Color(0.62, 0.68, 0.74),
	"top": Color(0.32, 0.52, 0.85), "horizon": Color(0.72, 0.8, 0.88)}
const DUSK_MOOD := {"sun": 0.8, "sun_col": Color(1.0, 0.7, 0.48), "amb": 0.52, "fog": Color(0.45, 0.34, 0.36),
	"top": Color(0.25, 0.22, 0.34), "horizon": Color(0.78, 0.42, 0.3)}
const NIGHT_MOOD := {"sun": 0.42, "sun_col": Color(0.62, 0.72, 1.0), "amb": 0.32, "fog": Color(0.17, 0.21, 0.3),
	"top": Color(0.02, 0.03, 0.08), "horizon": Color(0.08, 0.1, 0.17)}


func _mood(key: String, k: float):
	if k < 0.5:
		return lerp(DAY_MOOD[key], DUSK_MOOD[key], k * 2.0)
	return lerp(DUSK_MOOD[key], NIGHT_MOOD[key], (k - 0.5) * 2.0)


# Bright day, an orange dusk, then night; and back through dawn.
func _set_mood() -> void:
	var k := _darkness()
	moon.light_energy = _mood("sun", k)
	moon.light_color = _mood("sun_col", k)
	env.ambient_light_energy = _mood("amb", k)
	env.fog_light_color = _mood("fog", k)
	# Only the faintest haze over everything: the real fog lies on the ground
	# (scenes/level/ground_fog.gd).
	env.fog_density = lerpf(0.0012, 0.0035, k)
	var sky: ProceduralSkyMaterial = env.sky.sky_material
	sky.sky_top_color = _mood("top", k)
	sky.sky_horizon_color = _mood("horizon", k)
	sky.ground_horizon_color = sky.sky_horizon_color
	sky.ground_bottom_color = Color(0.05, 0.05, 0.06)


func _update_aim() -> void:
	if _mouse_screen == null:
		game.input_aim = null
		return
	var aim: Vector2 = rig.screen_to_ground(_mouse_screen)
	# Snap to a zombie whose body is under the cursor.
	var best = null
	var bd := 34.0
	for z in game.zombies:
		var sc: float = D.ZTYPES[z["type"]]["scale"]
		var p: Vector2 = rig.world_to_screen(Vector3(z["x"], 0.9 * sc, z["y"]))
		var d: float = p.distance_to(_mouse_screen) / sc
		if d < bd:
			bd = d
			best = z
	if best != null:
		aim = Vector2(best["x"], best["y"])
	game.input_aim = aim


func _keyboard_pan(dt: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y -= 1
	if v != Vector2.ZERO:
		rig.pan_keys(v, dt)


# --- Input ------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if hud.camp_open():
				if not started or game.over:
					new_run()
			elif not started:
				start()
			elif game.over:
				hud.toggle_camp()
		KEY_C:
			hud.toggle_camp()
		KEY_G:
			board_all()
		KEY_I, KEY_TAB:
			if started:
				hud.toggle_inventory()
		KEY_P, KEY_SPACE:
			toggle_pause()
		KEY_F5:
			if save_run("quick"):
				hud.toast("Quick saved.", "good")
		KEY_F9:
			if not Saves.info("quick").is_empty():
				load_run("quick")
		KEY_ESCAPE:
			if hud.saves_open():
				hud.close_saves()
			elif hud.camp_open():
				hud.toggle_camp()
			elif hud.options_open():
				hud.toggle_options()
			elif placing != "" or selected_id >= 0 or throwing >= 0:
				cancel_actions()
			elif hud.research_open():
				hud.toggle_research()
			elif hud.map_open():
				hud.toggle_map()
			elif hud.inventory_open():
				hud.close_inventory()
			elif hud.workshop.visible:
				hud.toggle_workshop()
			else:
				toggle_pause()
		KEY_M:
			if started:
				hud.toggle_map()
		KEY_B:
			if started:
				hud.toggle_workshop()
		KEY_T:
			if started:
				hud.toggle_research()
		KEY_N:
			toggle_sound()
		KEY_O:
			hud.toggle_options()
		KEY_R:
			if game.over:
				if not hud.camp_open():
					hud.toggle_camp()
			elif started:
				game.start_reload(game.crew[0])
		KEY_HOME:
			rig.reset()
		KEY_EQUAL, KEY_KP_ADD:
			rig.zoom_by(1.15)
		KEY_MINUS, KEY_KP_SUBTRACT:
			rig.zoom_by(1 / 1.15)


func _grid(p: Vector2) -> Vector2:
	return rig.screen_to_ground(p)


# Mouse input over the battlefield (from the HUD's Field control).
func field_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed and started and not game.over:
					if placing != "":
						_place_building(event.position)
						return
					if throwing >= 0:
						var tp := _grid(event.position)
						var tr: Dictionary = game.throw_item(throwing, tp.x, tp.y)
						if tr.has("ok"):
							throwing = -1
							preview.visible = false
							preview.scale = Vector3.ONE
						elif tr.get("msg", "") != "":
							hud.toast(tr["msg"], "danger")
						game.input_firing = false
						return
					var who := survivor_at(event.position)
					if who >= 0:
						game.input_firing = false
						group_ids.clear()
						if game.crew[who]["id"] == selected_id or game.crew[who].get("repairing", false):
							# Clicking the selected survivor again: repair here.
							selected_id = -1
							var r: Dictionary = game.toggle_repair(who)
							if r.get("msg", "") != "":
								hud.toast(r["msg"], "info" if r.has("ok") else "danger")
						else:
							selected_id = game.crew[who]["id"]
						return
					if game.truck_waiting() and on_truck(_grid(event.position)):
						# The truck: whoever's picked climbs in (or everyone, if nobody is).
						if selected_id >= 0:
							var sent := 0
							for id in [selected_id] + group_ids:
								for c in game.crew.size():
									if game.crew[c]["id"] == id and game.board_truck(c).has("ok"):
										sent += 1
							hud.toast("%d of the crew head for the truck." % sent if sent > 1 else ("To the truck!" if sent == 1 else "They can't get there right now."), "info" if sent > 0 else "danger")
							selected_id = -1
							group_ids.clear()
						else:
							hud.toast("Pick survivors first, then click the truck. Or press G to send everyone.")
						game.input_firing = false
						return
					if selected_id >= 0:
						# A damaged turret: go and repair it.
						var ti := turret_at_screen(event.position)
						if ti >= 0:
							var tr: Dictionary = game.repair_turret(selected_index(), ti)
							if tr.get("msg", "") != "":
								hud.toast(tr["msg"], "info" if tr.has("ok") else "danger")
							selected_id = -1
							game.input_firing = false
							return
						var spot: Dictionary = Game.deck_spot(rig.screen_to_ground(event.position, D.DECK_H))
						var ground := _grid(event.position)
						var r := {}
						if not spot.is_empty():
							r = _move_group(spot, ground)
						elif Game.in_base(ground):
							r = _move_group({}, ground)
						if not r.is_empty():
							if r.get("msg", "") != "":
								hud.toast(r["msg"], "info" if r.has("ok") else "danger")
							selected_id = -1
							group_ids.clear()
							game.input_firing = false
							return
					# A drag that starts inside the base picks people with a box.
					var at := _grid(event.position)
					if Game.in_base(at) or not Game.deck_spot(rig.screen_to_ground(event.position, D.DECK_H)).is_empty():
						_box_start = event.position
						game.input_firing = false
						return
				if not event.pressed and _box_start != null:
					_finish_box(event.position)
					return
				if event.pressed:
					var gp := _grid(event.position)
					_press_trap = hud.inventory_open() and game.trap_at(gp.x, gp.y) != null
					game.input_firing = started and not _press_trap and not game.over
				else:
					game.input_firing = false
					_press_trap = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (placing != "" or selected_id >= 0 or throwing >= 0):
					cancel_actions()
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					rig.zoom_by(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					rig.zoom_by(1 / 1.1)
	elif event is InputEventMouseMotion:
		if _box_start != null:
			_draw_box(_box_start, event.position)
		var hs := survivor_at(event.position)
		if hs != hover_survivor:
			hover_survivor = hs
			hud.field.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hs >= 0 else Control.CURSOR_ARROW
		if _panning:
			rig.drag(event.position - event.relative, event.position)
		if placing != "":
			var gp := _grid(event.position)
			_show_building_preview(gp, game.can_build_at(placing, gp.x, gp.y).has("ok"))
		elif throwing >= 0:
			var gp := _grid(event.position)
			var i: int = game.storage_index(throwing)
			if i < 0:
				throwing = -1
			else:
				var key: String = game.storage["items"][i]["key"]
				var r: float = D.PIPEBOMB["splash"] if key == "pipebomb" else 1.35
				preview.visible = true
				preview.position = Vector3(gp.x, 0.05 + Terrain.sample(gp.x, gp.y), gp.y)
				preview.scale = Vector3(r, 1, r)
				var m: StandardMaterial3D = preview.get_surface_override_material(0)
				m.albedo_color = Color(1.6, 0.7, 0.2, 0.4)
		if hud.inventory_open():
			var gp := _grid(event.position)
			var t = game.trap_at(gp.x, gp.y)
			hover_trap_uid = t["uid"] if t != null else -1
		else:
			hover_trap_uid = -1
	elif event is InputEventMagnifyGesture:
		rig.zoom_by(event.factor)
	elif event is InputEventPanGesture:
		rig.drag(event.position, event.position - event.delta * 20.0)


## The turret drawn under a screen point (its tower or gun), or -1.
func turret_at_screen(p: Vector2) -> int:
	for i in game.turrets.size():
		var t: Dictionary = game.turrets[i]
		for h in [0.4, 1.0, 1.6, 2.0]:
			if rig.world_to_screen(Vector3(t["x"], h, t["y"])).distance_to(p) < 26.0:
				return i
	return -1


## The box being dragged out, drawn on the interface.
func _draw_box(a: Vector2, b: Vector2) -> void:
	if _box == null:
		_box = Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.4, 0.85, 1.0, 0.12)
		sb.border_color = Color(0.5, 0.9, 1.0, 0.9)
		sb.set_border_width_all(2)
		_box.add_theme_stylebox_override("panel", sb)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_box)
	var r := Rect2(a, b - a).abs()
	_box.position = r.position
	_box.size = r.size
	_box.visible = r.size.length() > 8.0


## Letting go of the drag: everyone on duty inside the box is picked.
func _finish_box(end: Vector2) -> void:
	var r := Rect2(_box_start, end - _box_start).abs()
	_box_start = null
	if _box != null:
		_box.visible = false
	if r.size.length() < 8.0:
		return   # just a click
	var picked: Array = []
	for s in game.crew:
		if not s["state"] in ["wall", "moving"]:
			continue
		var sp: Vector2 = rig.world_to_screen(Vector3(s["x"], D.DECK_H + 0.9, s["y"]))
		if r.grow(12.0).has_point(sp):
			picked.append(s["id"])
	if picked.is_empty():
		selected_id = -1
		group_ids.clear()
		return
	selected_id = picked[0]
	group_ids = picked.slice(1)
	hud.toast("%d picked. Click a walkway or a spot in the base to send them there." % picked.size() if picked.size() > 1 else "Click a walkway or a spot in the base to send them there.")


## Sends the picked survivor(s) to a walkway spot (spot) or a spot in the yard
## (ground), spread out side by side so they don't stand in each other.
func _move_group(spot: Dictionary, ground: Vector2) -> Dictionary:
	var ids: Array = [selected_id] + group_ids
	var n := ids.size()
	var first := {}
	var sent := 0
	for k in n:
		var i := -1
		for c in game.crew.size():
			if game.crew[c]["id"] == ids[k]:
				i = c
		if i < 0:
			continue
		var off := (k - (n - 1) / 2.0) * 0.8
		var r: Dictionary
		if not spot.is_empty():
			r = game.move_survivor(i, spot["side"], spot["u"] + off)
		else:
			var p := ground + Vector2(off, 0.0)
			if not Game.in_base(p):
				p = ground
			r = game.move_survivor_to(i, p)
		if r.has("ok"):
			sent += 1
		if first.is_empty() or (r.has("ok") and not first.has("ok")):
			first = r
	if sent > 1:
		return {"ok": true, "msg": "%d of the crew head over." % sent}
	return first


## Index in game.crew of the selected survivor, or -1.
func selected_index() -> int:
	for i in game.crew.size():
		if game.crew[i]["id"] == selected_id:
			return i
	return -1


## Drops any half-done action: building placement or a picked survivor.
func cancel_actions() -> void:
	if placing != "":
		hud.toast("Building cancelled.")
	placing = ""
	throwing = -1
	selected_id = -1
	group_ids.clear()
	preview.visible = false
	preview.scale = Vector3.ONE


## Aim a molotov or pipe bomb from storage: the next click on the field throws it.
func start_throwing(item_uid: int) -> void:
	placing = ""
	selected_id = -1
	throwing = item_uid
	hud.toast("Click where to throw it.")


## Pick a spot in the base for a turret bought in the workshop.
func start_placing(id: String) -> void:
	var chk: Dictionary = game.can_buy(id)
	if not chk.has("ok"):
		hud.toast(chk.get("msg", ""), "danger")
		return
	selected_id = -1
	placing = id
	hud.toast("Click in the base to put the %s there. Right-click or Esc to cancel." % D.SHOP[id]["name"].to_lower())


func _place_building(screen: Vector2) -> void:
	var gp := _grid(screen)
	var r: Dictionary = game.build(placing, gp.x, gp.y)
	if r.has("ok"):
		hud.toast("%s built." % D.SHOP[placing]["name"])
		placing = ""
		preview.visible = false
		preview.scale = Vector3.ONE
	elif r.get("msg", "") != "":
		hud.toast(r["msg"], "danger")
	game.input_firing = false


func _show_building_preview(gp: Vector2, ok: bool) -> void:
	preview.visible = true
	var sz: Vector2 = D.BUILD_SIZE[placing]
	preview.position = Vector3(gp.x, 0.05, gp.y)
	preview.scale = Vector3(sz.x * 0.5, 1, sz.y * 0.5)
	var m: StandardMaterial3D = preview.get_surface_override_material(0)
	m.albedo_color = Color(0.3, 1.6, 0.5, 0.45) if ok else Color(1.6, 0.3, 0.25, 0.45)


## Index of the survivor on the walkway under a screen point, or -1.
func survivor_at(p: Vector2) -> int:
	var best := -1
	var bd := 30.0
	for i in game.crew.size():
		var s: Dictionary = game.crew[i]
		if s["state"] != "wall":
			continue
		for h in [0.5, 1.0, 1.5]:
			var sp: Vector2 = rig.world_to_screen(Vector3(s["x"], D.DECK_H + h, s["y"]))
			var d := sp.distance_to(p)
			if d < bd:
				bd = d
				best = i
	# A zombie closer to the cursor wins: you meant to shoot it.
	if best >= 0:
		for z in game.zombies:
			var sc: float = D.ZTYPES[z["type"]]["scale"]
			if rig.world_to_screen(Vector3(z["x"], 0.9 * sc, z["y"])).distance_to(p) < bd:
				return -1
	return best


# Start dragging a placed trap (only while storage is open).
func field_drag(pos: Vector2) -> Variant:
	if not hud.inventory_open() or not _press_trap:
		return null
	var gp := _grid(pos)
	var t = game.trap_at(gp.x, gp.y)
	if t == null:
		return null
	game.input_firing = false
	hud.set_drag_label(D.item_name(t["key"]), t["key"])
	return {"trap_uid": t["uid"], "key": t["key"]}


func field_can_drop(pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var gp := _grid(pos)
	var r: Dictionary
	if data.has("trap_uid"):
		r = game.can_place_trap(gp.x, gp.y, data["trap_uid"])
	elif data.has("loc") and data["loc"]["where"] == "storage" and D.item_kind(data["key"]) == "trap":
		r = game.can_place_trap(gp.x, gp.y)
	else:
		preview.visible = false
		return false
	_show_preview(gp, data["key"], r.has("ok"))
	if not r.has("ok"):
		hud.set_inv_message(r.get("msg", ""))
	return r.has("ok")


func _show_preview(gp: Vector2, key: String, ok: bool) -> void:
	preview.visible = true
	var r: float = D.TRAP_R[key]
	preview.position = Vector3(gp.x, 0.03 + Terrain.sample(gp.x, gp.y), gp.y)
	preview.scale = Vector3(r, 1, r)
	var m: StandardMaterial3D = preview.get_surface_override_material(0)
	m.albedo_color = Color(0.3, 1.6, 0.5, 0.45) if ok else Color(1.6, 0.3, 0.25, 0.45)


func field_drop(pos: Vector2, data: Variant) -> void:
	var gp := _grid(pos)
	var r: Dictionary
	if data.has("trap_uid"):
		r = game.move_trap(data["trap_uid"], gp.x, gp.y)
	else:
		r = game.place_trap(data["loc"]["i"], gp.x, gp.y)
	preview.visible = false
	if r.has("ok"):
		hud.clear_selection()
	elif r.get("msg", "") != "":
		hud.set_inv_message(r["msg"])


func drag_ended() -> void:
	preview.visible = false
	_press_trap = false
