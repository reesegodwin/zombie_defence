# Runs the game: owns the simulation (scripts/game.gd), keeps the 3D scene in
# step with it, sets the mood of the night, and turns input into actions.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Game = preload("res://scripts/game.gd")

@export var zombie_scene: PackedScene
@export var survivor_scene: PackedScene
@export var trap_scenes: Dictionary = {}   # trap key -> PackedScene
@export_group("Night")
## Moonlight at dusk and at deepest night.
@export var moon_energy := Vector2(1.5, 0.8)
@export var ambient_energy := Vector2(0.8, 0.42)

@onready var level: Node3D = $Level
@onready var wall: Node3D = $Level/Wall
@onready var moon: DirectionalLight3D = $Moon
@onready var env: Environment = $WorldEnvironment.environment
@onready var rig: Node3D = $CameraRig
@onready var zombies_root: Node3D = $Actors/Zombies
@onready var crew_root: Node3D = $Actors/Crew
@onready var traps_root: Node3D = $Actors/Traps
@onready var effects: Node3D = $Effects
@onready var preview: MeshInstance3D = $PlacePreview
@onready var hud: CanvasLayer = $HUD
@onready var sfx: Node = $Sfx

var game
var started := false
var paused := false
var zombie_nodes := {}     # zombie id -> node
var crew_nodes: Array = []
var trap_nodes := {}       # trap uid -> node
var hover_trap_uid := -1

var _mouse_screen = null   # last cursor position over the battlefield
var _panning := false
var _press_trap := false
var _over_handled := false
var _clock := 0.0


func _ready() -> void:
	randomize()
	hud.main = self
	_new_game()


func _new_game() -> void:
	var auto: bool = game.input_auto if game != null else true
	game = Game.new()
	game.input_auto = auto
	game.toast.connect(func(t, k): hud.toast(t, k))
	game.sound.connect(func(n): sfx.play(n))
	game.inv_changed.connect(func(): hud.on_inv_changed())
	game.wall_breached.connect(func(x): wall.collapse(x))
	game.exploded.connect(func(_x, _y, _r): rig.shake = maxf(rig.shake, 0.6))
	effects.bind(game)
	for n in zombie_nodes.values():
		n.queue_free()
	zombie_nodes.clear()
	for n in crew_nodes:
		n.queue_free()
	crew_nodes.clear()
	for n in trap_nodes.values():
		n.queue_free()
	trap_nodes.clear()
	effects.clear()
	wall.reset()
	preview.visible = false
	_over_handled = false


func start() -> void:
	started = true
	hud.hide_title()
	hud.toast("They're coming from the tree line. Hold the wall.")


func restart() -> void:
	hud.hide_game_over()
	hud.close_inventory()
	if hud.map_open():
		hud.toggle_map()
	if hud.workshop.visible:
		hud.toggle_workshop()
	_new_game()
	paused = false
	rig.reset()
	hud.toast("Again. Hold the wall.")


func toggle_pause() -> void:
	if started and not game.over:
		paused = not paused


func toggle_auto() -> void:
	game.input_auto = not game.input_auto


func toggle_sound() -> void:
	sfx.muted = not sfx.muted


# --- Loop -------------------------------------------------------------------
func _process(dt: float) -> void:
	_clock += dt
	_keyboard_pan(dt)
	if started:
		_update_aim()
		# The world waits while you study the scavenging map.
		if not paused and not hud.map_open():
			game.step(minf(dt, 0.05))
	if game.over and not _over_handled:
		_over_handled = true
		game.input_firing = false
		hud.close_inventory()
		if hud.map_open():
			hud.toggle_map()
		rig.shake = 1.2
		get_tree().create_timer(1.6).timeout.connect(func(): if game.over: hud.show_game_over())
	rig.shake = maxf(rig.shake, game.shake * 0.6)
	_sync_scene(dt)
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
	while crew_nodes.size() < game.crew.size():
		var s: Dictionary = game.crew[crew_nodes.size()]
		var n: Node3D = survivor_scene.instantiate()
		crew_root.add_child(n)
		n.setup(s)
		crew_nodes.append(n)
	for i in crew_nodes.size():
		crew_nodes[i].sync(game.crew[i], dt)
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
	# Rock in the mountain pass turns see-through around anyone walking it.
	var walkers: Array = []
	for s in game.crew:
		if s["state"] != "wall" and s["state"] != "away" and s["y"] > D.WALK_Y + 2.0:
			walkers.append(Vector3(s["x"], 0.0, s["y"]))
	var none := Vector3(0, -100, 0)
	RenderingServer.global_shader_parameter_set("walker_a", walkers[0] if walkers.size() > 0 else none)
	RenderingServer.global_shader_parameter_set("walker_b", walkers[1] if walkers.size() > 1 else none)
	wall.sync(game, _clock)
	effects.sync(game)
	level.set_darkness(_darkness(), dt)


func _darkness() -> float:
	return clampf((game.dark - 0.12) / (0.58 - 0.12), 0.0, 1.0)


# Dusk deepens into night as the run goes on.
func _set_mood() -> void:
	var k := _darkness()
	moon.light_energy = lerpf(moon_energy.x, moon_energy.y, k)
	moon.light_color = Color(1.0, 0.78, 0.6).lerp(Color(0.62, 0.72, 1.0), k)
	env.ambient_light_energy = lerpf(ambient_energy.x, ambient_energy.y, k)
	env.fog_light_color = Color(0.42, 0.36, 0.38).lerp(Color(0.1, 0.13, 0.22), k)
	var sky: ProceduralSkyMaterial = env.sky.sky_material
	sky.sky_top_color = Color(0.25, 0.22, 0.32).lerp(Color(0.02, 0.03, 0.08), k)
	sky.sky_horizon_color = Color(0.7, 0.42, 0.32).lerp(Color(0.08, 0.1, 0.17), k)
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
			if not started:
				start()
			elif game.over:
				restart()
		KEY_F:
			toggle_auto()
		KEY_I, KEY_TAB:
			if started:
				hud.toggle_inventory()
		KEY_P, KEY_SPACE:
			toggle_pause()
		KEY_ESCAPE:
			if hud.map_open():
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
		KEY_N:
			toggle_sound()
		KEY_R:
			if game.over:
				restart()
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
				if event.pressed:
					var gp := _grid(event.position)
					_press_trap = hud.inventory_open() and game.trap_at(gp.x, gp.y) != null
					game.input_firing = started and not _press_trap and not game.over
				else:
					game.input_firing = false
					_press_trap = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					rig.zoom_by(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					rig.zoom_by(1 / 1.1)
	elif event is InputEventMouseMotion:
		if _panning:
			rig.drag(event.position - event.relative, event.position)
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
	preview.position = Vector3(gp.x, 0.03, gp.y)
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
