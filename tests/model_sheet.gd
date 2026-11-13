# Renders character sheets of every zombie model (zombies.png and one sheet
# each), the zombie types and the survivors (front,
# three-quarter, side and back, in an A-pose on white, and close-ups of the
# faces) to check the models. Needs a display (e.g. xvfb-run):
#   godot --path . --script res://tests/model_sheet.gd -- <output dir>
extends SceneTree

const D = preload("res://scripts/defs.gd")
const ZOMBIE := preload("res://scenes/actors/zombie.tscn")
const Body = preload("res://scenes/actors/body.gd")
const Guns = preload("res://scenes/actors/guns.gd")
const Turret = preload("res://scenes/actors/turret.gd")
const GUNS := ["pistol", "smg", "shotgun", "rifle", "launcher"]
const Survivor = preload("res://scenes/actors/survivor.gd")
# You (the scout), then one of each of the other models.
const CREW := [
	{"model": "scout", "name": "You", "build": "m", "skin": Color("d9a77f"), "shirt": Color("3e5a6e"), "seed": 1},
	{"model": "soldier", "name": "Marek", "build": "m", "skin": 0, "shirt": 3, "seed": 2},
	{"model": "tank", "name": "Dana", "build": "f", "skin": 1, "shirt": 1, "seed": 5},
	{"model": "jacket", "name": "Kofi", "build": "m", "skin": 2, "shirt": 0, "seed": 11},
	{"model": "ranger", "name": "Tomas", "build": "m", "skin": 4, "shirt": 4, "seed": 7},
	{"model": "hooded", "name": "Rosa", "build": "f", "skin": 3, "shirt": 2, "seed": 9},
	{"model": "tank", "name": "Lev", "build": "m", "skin": 0, "shirt": 2, "seed": 4},
]
const VIEWS := [0.0, -0.6, -PI / 2, PI]

var out_dir := "shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 800)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.WHITE
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, PI - 0.6, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.position = Vector3(0, 0.92, 10)
	world.add_child(cam)
	await _zombie_models(cam)
	for type in D.ZTYPES:
		var sc: float = D.ZTYPES[type]["scale"]
		cam.size = 2.3 * sc
		cam.position = Vector3(0, 0.92 * sc, 10)
		var models := []
		for i in VIEWS.size():
			var z := ZOMBIE.instantiate()
			world.add_child(z)
			z.setup({"id": 3 + i * 0, "type": type, "shirt": 0, "x": 0.0, "y": 0.0, "t": 0.0,
				"held": 0, "atk": 0, "v": 999.0, "spd": 1.0, "slow": 1.0, "sway": 0.0,
				"hit": 0, "burn": 0, "hp": 1.0, "max_hp": 1.0, "side": 0})
			z.set_process(false)
			_a_pose(z)
			z.position = Vector3((i - 1.5) * 1.15 * sc, 0, 0)
			z.rotation = Vector3(0, VIEWS[i], 0)
			models.append(z)
		await _shot(type)
		# A close-up of the head and shoulders.
		cam.size = 0.75 * sc
		cam.position = Vector3(-1.725 * sc, 1.5 * sc, 10)
		root.size = Vector2i(800, 800)
		await _shot(type + "_face")
		root.size = Vector2i(1600, 800)
		for m in models:
			m.free()
	await _survivors(cam)
	await _guns(cam)
	await _turret(cam)
	quit()


## Every zombie model side by side (as walkers), then their faces, then each
## from the front, the side and the back.
func _zombie_models(cam: Camera3D) -> void:
	var names: Array = Body.ZOMBIE_MODELS.keys()
	var models := []
	for i in names.size():
		models.append(_zombie("walker", names[i], i, i))
		models[i].position = Vector3((i - (names.size() - 1) / 2.0) * 0.74, 0, 0)
		models[i].rotation.y = -0.3
	root.size = Vector2i(2400, 1000)
	cam.size = 2.15
	cam.position = Vector3(0, 0.95, 10)
	await _shot("zombies")
	root.size = Vector2i(2400, 420)
	cam.size = 0.9
	cam.position = Vector3(0, 1.6, 10)
	await _shot("zombies_faces")
	for m in models:
		m.free()
	root.size = Vector2i(1600, 800)
	for i in names.size():
		models.clear()
		for v in VIEWS.size():
			models.append(_zombie("walker", names[i], i, i))
			models[v].position = Vector3((v - 1.5) * 1.15, 0, 0)
			models[v].rotation.y = VIEWS[v]
		cam.size = 2.3
		cam.position = Vector3(0, 0.92, 10)
		await _shot("zombie_" + names[i])
		cam.size = 0.75
		cam.position = Vector3(-1.725, 1.5, 10)
		root.size = Vector2i(800, 800)
		await _shot("zombie_" + names[i] + "_face")
		root.size = Vector2i(1600, 800)
		for m in models:
			m.free()


func _zombie(type: String, model: String, id: int, shirt: int) -> Node3D:
	var z := ZOMBIE.instantiate()
	root.add_child(z)
	z.setup({"id": id, "type": type, "shirt": shirt % D.ZTYPES[type]["shirts"].size(), "x": 0.0, "y": 0.0, "t": 0.0,
		"held": 0, "atk": 0, "v": 999.0, "spd": 1.0, "slow": 1.0, "sway": 0.0,
		"hit": 0, "burn": 0, "hp": 1.0, "max_hp": 1.0, "side": 0}, model)
	z.set_process(false)
	_a_pose(z)
	return z


func _guns(cam: Camera3D) -> void:
	# Each gun from the side, three times life size, one under the other.
	var nodes := []
	for i in GUNS.size():
		var g := Guns.get_gun(GUNS[i], D.WEAPONS[GUNS[i]]["len"])
		var mi := MeshInstance3D.new()
		mi.mesh = g["mesh"]
		mi.material_override = Guns.material()
		# Shown 1.4 m long (the pistol 0.7 m), in two columns.
		var show := (0.7 if GUNS[i] == "pistol" else 1.4) / float(D.WEAPONS[GUNS[i]]["len"])
		mi.scale = Vector3.ONE * g["scale"] * show
		mi.rotation = Vector3(0, PI / 2 - 0.3, 0)
		var col := 0 if i < 3 else 1
		var row := i if i < 3 else i - 3
		mi.position = Vector3(-1.1 + col * 2.1, 1.65 - row * 0.62, 0)
		root.add_child(mi)
		nodes.append(mi)
	cam.size = 2.3
	cam.position = Vector3(0, 0.92, 10)
	await _shot("guns")
	for n in nodes:
		n.free()
	# The crew holding them, aiming.
	nodes.clear()
	for i in GUNS.size():
		var n := _survivor(i)
		var j: Dictionary = n.get_meta("j")
		j["shoulder_r"].rotation = Vector3(-1.25, 0.0, -0.3)
		j["elbow_r"].rotation.x = -0.55
		j["shoulder_l"].rotation = Vector3(-1.45, 0.0, 0.45)
		j["elbow_l"].rotation.x = -0.25
		var pivot := Node3D.new()
		pivot.position = Vector3(0.06, 0.3, 0.2)
		j["spine"].add_child(pivot)
		var g := Guns.get_gun(GUNS[i], D.WEAPONS[GUNS[i]]["len"])
		var mi := MeshInstance3D.new()
		mi.mesh = g["mesh"]
		mi.material_override = Guns.material()
		mi.scale = Vector3.ONE * g["scale"]
		mi.position = Guns.HOLD
		pivot.add_child(mi)
		n.position = Vector3((i - 2) * 0.95, 0, 0)
		n.rotation.y = 0.9
		nodes.append(n)
	await _shot("armed")
	for n in nodes:
		n.free()


func _turret(cam: Camera3D) -> void:
	# Three turrets, fully upgraded, behind a stretch of wall to show they clear it.
	var nodes := []
	for i in 3:
		var t: Node3D = Turret.new()
		root.add_child(t)
		t.position = Vector3((i - 1) * 1.6, 0, 0)
		t.head.rotation.y = [-0.6, -PI / 2, 2.4][i]
		t.flash.visible = false
		nodes.append(t)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.6, 1.32, 0.2)
	wall.mesh = box
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.55, 0.42, 0.3, 0.45)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall.material_override = wm
	wall.position = Vector3(0, 0.66, 0.8)
	root.add_child(wall)
	nodes.append(wall)
	cam.size = 2.6
	cam.position = Vector3(0, 1.3, 10)
	await _shot("turret")
	# A close-up of one, from the front quarter.
	nodes[0].free()
	nodes[2].free()
	wall.free()
	var t: Node3D = nodes[1]
	t.position = Vector3.ZERO
	t.head.rotation.y = -0.7
	cam.size = 1.0
	cam.position = Vector3(0, 1.9, 10)
	await _shot("turret_close")
	t.free()


func _survivor(i: int) -> Node3D:
	var c: Dictionary = CREW[i]
	var n := Node3D.new()
	root.add_child(n)
	if c["build"] == "f":
		n.scale = Vector3.ONE * 0.95
	var j := Body.survivor(n, Survivor.look_of({"id": c["seed"], "name": c["name"], "is_player": i == 0,
		"skin": c["skin"] if c["skin"] is Color else D.SKINS[c["skin"]], "jacket": c["shirt"] if c["shirt"] is Color else D.JACKETS[c["shirt"]]}, c["model"]))
	n.set_meta("j", j)
	_pose(j)
	return n


## Everyone side by side, then their faces, then each from four sides.
func _survivors(cam: Camera3D) -> void:
	var models := []
	root.size = Vector2i(2400, 1000)
	cam.size = 2.9
	cam.position = Vector3(0, 0.95, 10)
	for i in CREW.size():
		var n := _survivor(i)
		n.position = Vector3((i - (CREW.size() - 1) / 2.0) * 0.98, 0, 0)
		n.rotation.y = -0.3
		models.append(n)
	await _shot("crew")
	root.size = Vector2i(2400, 420)
	root.size = Vector2i(2400, 300)
	cam.size = 0.86
	cam.position = Vector3(0, 1.6, 10)
	await _shot("crew_faces")
	for m in models:
		m.free()
	root.size = Vector2i(1600, 800)
	for i in CREW.size():
		models.clear()
		for v in VIEWS.size():
			var n := _survivor(i)
			n.position = Vector3((v - 1.5) * 1.15, 0, 0)
			n.rotation.y = VIEWS[v]
			models.append(n)
		cam.size = 2.3
		cam.position = Vector3(0, 0.92, 10)
		await _shot("survivor_" + CREW[i]["model"])
		cam.size = 0.75
		cam.position = Vector3(-1.725, 1.5, 10)
		root.size = Vector2i(800, 800)
		await _shot("survivor_" + CREW[i]["model"] + "_face")
		root.size = Vector2i(1600, 800)
		for m in models:
			m.free()


func _a_pose(z: Node3D) -> void:
	_pose(z.j)


func _pose(j: Dictionary) -> void:
	for k in ["hip_l", "hip_r", "knee_l", "knee_r"]:
		j[k].rotation = Vector3.ZERO
	j["spine"].rotation = Vector3(0.08, 0, 0)
	j["head"].rotation = Vector3(0.05, 0, 0)
	for side in ["l", "r"]:
		var sgn := -1.0 if side == "l" else 1.0
		j["shoulder_" + side].rotation = Vector3(0, 0, sgn * 0.5)
		j["elbow_" + side].rotation = Vector3(-0.15, 0, 0)


func _shot(sname: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + "/" + sname + ".png")
	print("saved " + sname)
