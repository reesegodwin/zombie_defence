# Entry point: creates the world, camera, sound and HUD, runs the game loop,
# and turns mouse and keyboard input into game actions.
extends Node2D

const D = preload("res://scripts/defs.gd")
const Game = preload("res://scripts/game.gd")
const World = preload("res://scripts/world.gd")
const Hud = preload("res://scripts/hud.gd")
const Sfx = preload("res://scripts/sfx.gd")

var game
var world: Node2D
var cam: Camera2D
var hud: CanvasLayer
var sfx: Node

var started := false
var paused := false
var cam_center := Vector2.ZERO
var _panning := false
var _press_trap := false
var _over_handled := false
var _mouse_screen = null     # last cursor position over the battlefield


func _ready() -> void:
	randomize()
	sfx = Sfx.new()
	add_child(sfx)
	world = World.new()
	add_child(world)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_reset_camera()
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	_new_game()
	game.input_auto = true


func _new_game() -> void:
	var auto: bool = game.input_auto if game != null else true
	game = Game.new()
	game.input_auto = auto
	game.toast.connect(func(t, k): hud.toast(t, k))
	game.sound.connect(func(n): sfx.play(n))
	game.inv_changed.connect(func(): hud.on_inv_changed())
	game.leveled_up.connect(func(): hud.show_cards())
	world.g = game
	world.preview = null
	_over_handled = false


func _reset_camera() -> void:
	# Frame the lane and the wall; the base is a short pan away.
	cam_center = Vector2(130, 290)
	cam.position = cam_center
	cam.zoom = Vector2(1.2, 1.2)


func start() -> void:
	started = true
	hud.title_overlay.visible = false
	hud.toast("They're coming from the tree line. Hold the wall.")


func restart() -> void:
	hud.over_overlay.visible = false
	hud.hide_cards()
	if hud.inv_panel.visible:
		hud.toggle_inventory()
	_new_game()
	paused = false
	_reset_camera()
	hud.toast("Again. Hold the wall.")


func toggle_pause() -> void:
	if started and not game.over and game.cards.is_empty():
		paused = not paused


func toggle_auto() -> void:
	game.input_auto = not game.input_auto


func toggle_sound() -> void:
	sfx.muted = not sfx.muted


func choose_card(i: int) -> void:
	if game.cards.is_empty():
		return
	game.choose_card(i)
	sfx.play("coin")
	if game.cards.is_empty():
		hud.hide_cards()


# --- Loop -------------------------------------------------------------------
func _process(dt: float) -> void:
	_keyboard_pan(dt)
	if started and not paused:
		_update_aim()
		game.step(minf(dt, 0.05))
		if game.over and not _over_handled:
			_over_handled = true
			game.input_firing = false
			if hud.inv_panel.visible:
				hud.toggle_inventory()
			get_tree().create_timer(1.4).timeout.connect(func(): if game.over: hud.show_over())
	elif started:
		_update_aim()
	# Screen shake.
	var sh: float = game.shake
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * sh * 10.0
	hud.update_hud()


func _update_aim() -> void:
	if _mouse_screen == null:
		game.input_aim = null
		return
	var mp := _screen_to_world(_mouse_screen)
	var aim := D.w2g(mp)
	# Snap to a zombie whose body is under the cursor.
	var best = null
	var bd := 22.0
	for z in game.zombies:
		var sc: float = D.ZTYPES[z["type"]]["scale"]
		var body := D.g2w(z["x"], z["y"]) - Vector2(0, 14 * sc)
		var d := body.distance_to(mp)
		if d < bd * sc:
			bd = d / sc
			best = z
	if best != null:
		aim = Vector2(best["x"], best["y"])
	game.input_aim = aim


func _keyboard_pan(dt: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if v != Vector2.ZERO:
		_pan(-v * 600.0 * dt * cam.zoom.x)


func _pan(screen_delta: Vector2) -> void:
	cam.position -= screen_delta / cam.zoom.x
	var lim := D.N * D.TW * 0.5
	cam.position.x = clampf(cam.position.x, -lim, lim)
	cam.position.y = clampf(cam.position.y, 0.0, D.N * D.TH)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _screen_to_world(screen_pos)
	var z := clampf(cam.zoom.x * factor, 0.5, 2.4)
	cam.zoom = Vector2(z, z)
	var after := _screen_to_world(screen_pos)
	cam.position += before - after


func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _screen_to_grid(p: Vector2) -> Vector2:
	return D.w2g(_screen_to_world(p))


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
			if hud.inv_panel.visible:
				hud.toggle_inventory()
			else:
				toggle_pause()
		KEY_M:
			toggle_sound()
		KEY_R:
			if game.over:
				restart()
		KEY_HOME:
			_reset_camera()
		KEY_EQUAL, KEY_KP_ADD:
			_zoom_at(get_viewport().get_visible_rect().size / 2, 1.15)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(get_viewport().get_visible_rect().size / 2, 1 / 1.15)
		KEY_1, KEY_2, KEY_3:
			choose_card(event.keycode - KEY_1)


# Mouse input over the battlefield (from field.gd).
func field_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press_trap = hud.inv_panel.visible and game.trap_at(_screen_to_grid(event.position).x, _screen_to_grid(event.position).y) != null
					game.input_firing = started and not _press_trap and not game.over
				else:
					game.input_firing = false
					_press_trap = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1 / 1.1)
	elif event is InputEventMouseMotion:
		if _panning:
			_pan(event.relative)
		if hud.inv_panel.visible:
			var gp := _screen_to_grid(event.position)
			var t = game.trap_at(gp.x, gp.y)
			world.hover_trap_uid = t["uid"] if t != null else -1
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		_pan(-event.delta * 20.0)


# Start dragging a placed trap (only while storage is open).
func field_drag(pos: Vector2) -> Variant:
	if not hud.inv_panel.visible or not _press_trap:
		return null
	var gp := _screen_to_grid(pos)
	var t = game.trap_at(gp.x, gp.y)
	if t == null:
		return null
	game.input_firing = false
	var l := Label.new()
	l.text = " " + D.item_name(t["key"]) + " "
	field_preview_style(l, t["key"])
	hud.field.set_drag_preview(l)
	return {"trap_uid": t["uid"], "key": t["key"]}


func field_preview_style(l: Label, key: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	sb.border_color = D.KIND_COLORS[D.item_kind(key)]
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	l.add_theme_stylebox_override("normal", sb)


func field_can_drop(pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var gp := _screen_to_grid(pos)
	var r: Dictionary
	if data.has("trap_uid"):
		r = game.can_place_trap(gp.x, gp.y, data["trap_uid"])
	elif data.has("loc") and data["loc"]["where"] == "storage" and D.item_kind(data["key"]) == "trap":
		r = game.can_place_trap(gp.x, gp.y)
	else:
		world.preview = null
		return false
	world.preview = {"x": gp.x, "y": gp.y, "ok": r.has("ok"), "key": data["key"]}
	if not r.has("ok"):
		hud.set_inv_message(r.get("msg", ""))
	return r.has("ok")


func field_drop(pos: Vector2, data: Variant) -> void:
	var gp := _screen_to_grid(pos)
	var r: Dictionary
	if data.has("trap_uid"):
		r = game.move_trap(data["trap_uid"], gp.x, gp.y)
	else:
		r = game.place_trap(data["loc"]["i"], gp.x, gp.y)
	world.preview = null
	if r.has("ok"):
		hud.selected = null
	elif r.get("msg", "") != "":
		hud.set_inv_message(r["msg"])


func drag_ended() -> void:
	world.preview = null
	_press_trap = false
