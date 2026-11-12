# Works out, once, what the game would otherwise compute every time it starts:
# every sound effect and zombie voice (scripts/sfx.gd) and the height grid of
# the land (scripts/terrain.gd), and saves them under res://assets/baked/.
# The CI runs this before exporting, so released builds start much faster
# (above all in a browser). Not committed: a copy run from the repo works them
# out at startup as before. From the project folder:
#   godot --headless --path . --script res://tools/bake.gd
extends SceneTree

const Sfx = preload("res://scripts/sfx.gd")
const Terrain = preload("res://scripts/terrain.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/baked")
	for f in [Sfx.BAKED, Terrain.BAKED]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)   # never bake from an old bake
	var sfx = Sfx.new()
	sfx.make_basic()
	var all: Dictionary = sfx.streams.duplicate()
	all.merge(sfx.make_voices())
	sfx.free()
	var bank := Resource.new()
	bank.set_meta("streams", all)
	print("sounds: ", all.size(), " -> ", ResourceSaver.save(bank, Sfx.BAKED))
	Terrain._grid = PackedFloat32Array()
	Terrain._build_grid()
	var t := Resource.new()
	t.set_meta("grid", Terrain._grid)
	print("terrain grid: ", Terrain._grid.size(), " -> ", ResourceSaver.save(t, Terrain.BAKED))
	quit()
