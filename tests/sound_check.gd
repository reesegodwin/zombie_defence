# Writes every sound effect to a WAV file to listen to, and the zombie voices
# one after another into zombie_voices.wav. From the project folder:
#   godot --headless --path . --script res://tests/sound_check.gd -- <output dir>
extends SceneTree

const Sfx = preload("res://scripts/sfx.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "shots/sounds"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sfx: Node = Sfx.new()
	root.add_child(sfx)
	var t := Time.get_ticks_msec()
	_wait(sfx, out_dir, t)


func _wait(sfx: Node, out_dir: String, t: int) -> void:
	while not sfx.streams.has("groan_walker"):
		await process_frame
	print("zombie voices built in %d ms (in the background)" % (Time.get_ticks_msec() - t))
	var reel := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(int(0.5 * Sfx.RATE) * 2)
	for k in sfx.streams:
		var st = sfx.streams[k]
		var list: Array = st if st is Array else [st]
		for i in list.size():
			var w: AudioStreamWAV = list[i]
			w.save_to_wav(out_dir + "/%s_%d.wav" % [k, i])
			if k in ["groan_walker", "groan_brute", "groan_runner", "snarl", "zdie", "groan"]:
				reel.append_array(w.data)
				reel.append_array(gap)
	var all := AudioStreamWAV.new()
	all.format = AudioStreamWAV.FORMAT_16_BITS
	all.mix_rate = Sfx.RATE
	all.data = reel
	all.save_to_wav(out_dir + "/zombie_voices.wav")
	print("saved to ", out_dir)
	quit()
