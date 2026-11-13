# Checks that walking feet stay planted: walks each zombie type
# forward and measures how fast the planted foot moves over the
# ground, which should be next to nothing. From the project folder:
#   godot --headless --path . --script res://tests/gait_check.gd
extends SceneTree

const D = preload("res://scripts/defs.gd")

var failures := 0


func _foot(node: Node3D, j: Dictionary, s: String) -> Vector3:
	var t: Transform3D = node.transform * j["hips"].transform * j["hip_" + s].transform * j["knee_" + s].transform
	return t * Vector3(0, -0.465, 0.04)


## Median speed (m/s) of the lower foot over the ground, along the way it's
## walking (+z). (The dead also sway from side to side as they go, which
## swivels a planted foot a little; that isn't sliding.)
func _slip(node: Node3D, step: Callable, frames := 600) -> float:
	var dt := 1.0 / 60.0
	var slips := []
	var prev := {}
	for i in frames:
		step.call(dt)
		var j: Dictionary = node.j
		var fl := _foot(node, j, "l")
		var fr := _foot(node, j, "r")
		var low := "l" if fl.y < fr.y else "r"
		var f := fl if low == "l" else fr
		if prev.has(low) and i > 60:
			slips.append(absf(f.z - prev[low].z) / dt)   # along the way it's walking
		prev = {"l": fl, "r": fr}
	slips.sort()
	return slips[slips.size() / 2]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for type in ["walker", "runner", "brute"]:
		var z: Node3D = load("res://scenes/actors/zombie.tscn").instantiate()
		root.add_child(z)
		await process_frame
		var zd := {"id": 5, "type": type, "shirt": 0, "x": 11.0, "y": 0.0, "t": 0.0, "held": 0, "atk": 0, "spd": 1.0, "slow": 1.0,
			"sway": 0.0, "hit": 0, "burn": 0, "hp": 1.0, "max_hp": 1.0, "side": 0}
		z.setup(zd)
		z._limp = 1.0   # a sound-legged one: a lame leg drags, as it should
		var v: float = D.ZTYPES[type]["speed"]
		var slip := _slip(z, func(dt):
			zd["y"] += v * dt
			zd["t"] += dt
			z.sync(zd, dt))
		_check(slip < v * 0.1, "%s walking %.2f m/s: planted foot slips %.3f m/s" % [type, v, slip])
		z.queue_free()
	print("RESULT: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
