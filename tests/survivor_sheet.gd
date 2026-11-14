# Renders each survivor model (assets/models/survivors/*.gltf, made in
# Blender), as the game shows it: front, three-quarter, side and back, a
# close-up of the head and one of the upper body.
# Needs a display (e.g. xvfb-run):
#   godot --path . --script res://tests/survivor_sheet.gd -- <output dir> [name ...]
extends SceneTree

const Model = preload("res://scenes/actors/survivor_model.gd")
const Game = preload("res://scripts/game.gd")
const SURVIVOR := preload("res://scenes/actors/survivor.tscn")
## Some of the cast, and what each carries, for the line-up.
const CAST := [["", "pistol"], ["Dana", "smg"], ["Marek", "rifle"], ["Priya", "shotgun"], ["Tomas", "ar"], ["Kofi", "smg"], ["Hollis", "shotgun"], ["June", "pistol"]]
const DIR := "res://assets/models/survivors/"
const VIEWS := [0.0, -0.6, -PI / 2, PI]

var out_dir := "shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred(args.slice(1))


func _run(names: Array) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.83, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, PI - 0.6, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	if names.is_empty():
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".gltf"):
				names.append(f.get_basename())
	for n in names:
		var models := []
		for i in VIEWS.size():
			var m := Node3D.new()
			root.add_child(m)
			var j := Model.build(m, n)
			for side in ["l", "r"]:     # arms a little out from the sides
				j["shoulder_" + side].rotation.z = -0.5 if side == "l" else 0.5
			m.position = Vector3((i - 1.5) * 1.15, 0, 0)
			m.rotation.y = VIEWS[i]
			models.append(m)
		root.size = Vector2i(1600, 800)
		cam.size = 2.3
		cam.position = Vector3(0, 0.92, 10)
		await _shot(n)
		root.size = Vector2i(1000, 800)
		cam.size = 0.5
		cam.position = Vector3(-1.725, 1.62, 10)
		await _shot(n + "_face")
		root.size = Vector2i(1000, 1000)
		cam.size = 1.15
		cam.position = Vector3(-0.575, 1.22, 10)
		await _shot(n + "_bust")
		for m in models:
			m.free()
	if names.size() == Model.MODELS.size():
		await _cast(cam)
	quit()


## The cast as the game shows them: each in their own colouring, aiming.
func _cast(cam: Camera3D) -> void:
	var g = Game.new()
	var people := []
	for i in CAST.size():
		var s: Dictionary = g.add_survivor("You" if i == 0 else CAST[i][0], CAST[i][1], i == 0)
		s["aim"] = PI / 2 - 0.7
		var n: Node3D = SURVIVOR.instantiate()
		root.add_child(n)
		n.setup(s)
		for k in 40:      # let them settle into their hold
			n.sync(s, 0.016)
		n.position = Vector3((i - (CAST.size() - 1) / 2.0) * 0.95, 0, 0)
		people.append(n)
	root.size = Vector2i(2400, 760)
	cam.size = 2.4
	cam.position = Vector3(0, 1.0, 10)
	await _shot("cast")
	for n in people:
		n.free()


func _shot(sname: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir + "/" + sname + ".png")
	print("saved " + sname)
