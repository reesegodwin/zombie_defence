# The look of one zombie. The simulation (scripts/game.gd) owns where it is and
# how hurt it is; this script poses the model to match every frame.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Terrain = preload("res://scripts/terrain.gd")

## Leg and arm swing while walking, in radians.
@export var stride := 0.55

@onready var bar: Node3D = $HealthBar
@onready var bar_fill: Node3D = $HealthBar/Fill

const Body = preload("res://scenes/actors/body.gd")
const PANTS := [Color("2e333b"), Color("3d3a33"), Color("4b4236"), Color("2a2f29"), Color("3a2f2a"), Color("54504a")]

static var _flash_mat: StandardMaterial3D
static var _burn_mat: StandardMaterial3D

var meshes: Array = []
var zid := -1
var dying := false
var _overlay = null
var j := {}
# This zombie's own way of moving.
var _lean := 0.3
var _tilt := 0.0
var _reach := [true, true]     # which arms reach out (left, right)
var _limp := 1.0               # how much the dragging leg swings (1 = not at all lame)
var _limp_left := true
var _runner := false
var _phase := 0.0              # where it is in its stride cycle
var _last := Vector2.INF       # where it was last frame
var _speed := 0.0              # how fast it's actually moving (smoothed)
var _stagger := 0.0            # 1 just after a hit, easing back to 0
var _was_hit := false
var _stagger_side := 1.0
var _head_x := 0.0
var _turn := 0.0               # the way it faces, turning smoothly             # the head's resting nod
const LOOKS := 2               # how many different bodies each model, shirt and type comes in
static var _corpses: Array = []   # the bodies lying around, oldest first
const MAX_CORPSES := 30
const CORPSE_TIME := Vector2(6.0, 10.0)   # seconds a body lies before sinking away


## model: which of Body.ZOMBIE_MODELS to be (else one of its type's, by its id).
func setup(z: Dictionary, model := "") -> void:
	zid = z["id"]
	var T: Dictionary = D.ZTYPES[z["type"]]
	scale = Vector3.ONE * T["scale"]
	_runner = z["type"] == "runner"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(z["id"]) * 92821 + 7
	if model == "":
		model = T["models"][rng.randi() % T["models"].size()]
	j = Body.zombie(self, _ready_look(z["type"], model, z["shirt"], rng.randi() % LOOKS))
	meshes = j["meshes"]
	_lean = rng.randf_range(0.18, 0.42) if not _runner else 0.35
	_tilt = rng.randf_range(-0.45, 0.45)
	var arms := rng.randi() % 4   # most reach with both, some with one
	_reach = [arms != 1, arms != 2]
	_limp = rng.randf_range(0.35, 0.7) if rng.randf() < 0.35 else 1.0
	_limp_left = rng.randf() < 0.5
	j["head"].rotation.z = _tilt
	_head_x = rng.randf_range(-0.1, 0.35)
	j["head"].rotation.x = _head_x
	sync(z, 0.0)


func sync(z: Dictionary, dt: float, shown := true) -> void:
	position = Vector3(z["x"], Terrain.sample(z["x"], z["y"]), z["y"])
	# Off screen: just keep up with where it is (and its stride, so the feet
	# don't skip when it walks into view); posing it would be wasted work.
	var skel: Node = meshes[0].get_parent() if not meshes.is_empty() else null
	if skel != null and skel.is_processing() != shown:
		skel.set_process(shown)
	if not shown:
		var at := Vector2(z["x"], z["y"])
		if _last != Vector2.INF:
			_phase += minf(at.distance_to(_last), 0.5) / Body.stride_cycle(stride * (1.25 if _runner else 0.8), scale.x) * TAU
		_last = at
		return
	var t: float = z["t"]
	var held: bool = z["held"] > 0
	var attacking: bool = z["atk"] > 0
	var inside: bool = z.get("inside", false)
	# The walk is driven by how far it has actually moved, so the feet stay
	# planted on the ground (whatever its speed, size, or a slick slowing it).
	var a := stride * (1.25 if _runner else 0.8)
	var here := Vector2(z["x"], z["y"])
	var moved := 0.0 if _last == Vector2.INF else minf(here.distance_to(_last), 0.5)
	_last = here
	if dt > 0.0:
		_speed = lerpf(_speed, moved / dt, 0.25)
	_phase += moved / Body.stride_cycle(a, scale.x) * TAU
	var phase := _phase
	var moving: bool = not held and not attacking and _speed > 0.05
	var spine: Node3D = j["spine"]
	var hips: Node3D = j["hips"]
	var hip_y := Body.HIP_H
	if moving:
		# A shambling, uneven gait: one leg may drag.
		var sw := sin(phase)
		var ll := _limp if _limp_left else 1.0
		var lr := 1.0 if _limp_left else _limp
		j["hip_l"].rotation.x = Body.hip_swing(phase, a) * ll
		j["knee_l"].rotation.x = maxf(0.0, -cos(phase)) * 0.8 * ll
		j["hip_r"].rotation.x = Body.hip_swing(phase + PI, a) * lr
		j["knee_r"].rotation.x = maxf(0.0, cos(phase)) * 0.8 * lr
		var bob := absf(cos(phase)) * 0.04
		hips.position.y = hip_y + bob
		spine.position.y = hip_y + 0.04 + bob
		spine.rotation.z = sw * 0.08 + (0.06 if _limp < 1.0 else 0.0) * (1.0 if _limp_left else -1.0)
	else:
		spine.rotation.z = 0.0
		for k in ["hip_l", "hip_r", "knee_l", "knee_r"]:
			j[k].rotation.x = lerpf(j[k].rotation.x, 0.0, 0.2)
		hips.position.y = hip_y
		spine.position.y = hip_y + 0.04
	spine.rotation.x = _lean + (0.25 if attacking else 0.0)
	# Arms: reaching out ahead (or pumping, for runners), clawing when they hit.
	var claw := sin(t * 18.0) * 0.5 if attacking else 0.0
	for side in ["l", "r"]:
		var sgn := -1.0 if side == "l" else 1.0
		var reach: bool = _reach[0 if side == "l" else 1]
		var sh: Node3D = j["shoulder_" + side]
		var el: Node3D = j["elbow_" + side]
		if attacking:
			sh.rotation = Vector3(-1.7 + claw * sgn, 0, -sgn * 0.15)
			el.rotation.x = -0.3
		elif _runner and moving:
			sh.rotation = Vector3(sin(phase) * 0.9 * -sgn - 0.2, 0, -sgn * 0.08)
			el.rotation.x = -1.3
		elif reach:
			sh.rotation = Vector3(-1.3 + sin(phase + 0.5 + sgn) * 0.12, 0, -sgn * 0.12)
			el.rotation.x = -0.15
		else:
			sh.rotation = Vector3(sin(phase) * 0.15 * sgn, 0, sgn * 0.08)
			el.rotation.x = -0.1
	j["head"].rotation.z = _tilt + sin(t * 1.3 + z["sway"]) * 0.15
	j["head"].rotation.x = _head_x
	# Face down the lane, towards its wall (or whoever they're chasing inside).
	var n: Vector2 = D.LANES[z.get("side", 0)]["n"]
	var facing: float = z.get("face", atan2(n.x, n.y)) if (inside or z.has("tu")) else atan2(n.x, n.y)
	# Turn toward it over a moment rather than snapping.
	_turn = lerp_angle(_turn, facing, 0.12) if dt > 0.0 else facing
	if held:
		rotation.y = _turn + sin(t * 30.0) * 0.12
	else:
		rotation.y = _turn + sin(t * 0.8 + z["sway"]) * 0.15

	# Struck: the body jerks back, the head snaps, the arms fling up, then it
	# recovers. Brutes barely flinch.
	var hit_now: bool = z["hit"] > 0
	if hit_now and not _was_hit:
		_stagger = 1.0
		_stagger_side = 1.0 if randf() < 0.5 else -1.0
	_was_hit = hit_now
	if _stagger > 0.0:
		var k := _stagger * (0.35 if z["type"] == "brute" else 1.0)
		spine.rotation.x -= 0.6 * k
		# Offsets from this frame's pose (set above), so nothing accumulates.
		spine.rotation.z += 0.18 * k * _stagger_side
		j["head"].rotation.x = _head_x - 0.45 * k
		for side in ["l", "r"]:
			j["shoulder_" + side].rotation.x += 0.7 * k
			j["elbow_" + side].rotation.x -= 0.4 * k
		_stagger = maxf(0.0, _stagger - dt * 3.2)

	# Flash white when hit, orange while burning.
	var want = null
	if z["hit"] > 0:
		want = _flash()
	elif z["burn"] > 0:
		want = _burn()
	if want != _overlay:
		_overlay = want
		for m in meshes:
			m.material_overlay = want

	# Health bar, only once hurt, always facing the camera.
	var frac: float = clampf(z["hp"] / z["max_hp"], 0.0, 1.0)
	bar.visible = frac < 0.999
	if bar.visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			bar.global_basis = cam.global_basis
		bar_fill.scale.x = maxf(0.001, frac)
		bar_fill.position.x = -0.25 * (1.0 - frac)


## What a body looks like: one of LOOKS of that model in that shirt (which
## of the type's shirt colours), for that type. The same ones come round
## again and share their meshes: a horde is built from a few dozen bodies,
## each made once.
static func _look(type: String, model: String, shirt: int, which: int) -> Dictionary:
	var T: Dictionary = D.ZTYPES[type]
	var M: Dictionary = Body.ZOMBIE_MODELS[model]
	if M["top"] in ["none", "flayed"]:
		shirt = 0   # nothing on top to tell them apart by
	var key := "%s/%s/%d/%d" % [type, model, shirt, which]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	# Skin: the type's pallor, a shade lighter or darker.
	var shade := float(rng.randi_range(-2, 2)) * 0.05
	var skin: Color = T["skin"].lightened(shade) if shade > 0.0 else T["skin"].darkened(-shade)
	var pants: Array = M.get("pants", PANTS)
	var boots: Array = M.get("boots", [Color("5a3524")])
	return {
		# Clothes faded by sun and rain.
		"skin": skin, "shirt": T["shirts"][shirt].lerp(Color(0.85, 0.85, 0.8), 0.15),
		"pants": pants[rng.randi() % pants.size()].lightened(0.2),
		"boots": boots[rng.randi() % boots.size()],
		"eyes": T["eyes"],
		"top": M["top"], "legs": M["legs"], "feet": M["feet"], "glow": M.get("glow", false),
		# Mostly the model's own hair, now and then another head of it.
		"hair": M["hair"] if rng.randf() < 0.6 else ["bald", "thin", "lank"][rng.randi() % 3],
		"width": 1.25 if type == "brute" else (1.7 if type == "bloater" else (0.9 if type == "runner" else rng.randf_range(0.95, 1.05))),
		"rng": rng, "key": key, "model": model,
	}


## The look to give a zombie: the one asked for if its body is built, else
## one of its type's that is (building a body takes a long moment, a stall
## if it happened mid-fight; prewarm() builds the rest when nothing is going
## on). Only if none of its type is built yet does it build one now.
static func _ready_look(type: String, model: String, shirt: int, which: int) -> Dictionary:
	var look := _look(type, model, shirt, which)
	if Body.has_body(look["key"]):
		return look
	var built := Body.built_keys(type + "/")
	if built.is_empty():
		return look
	var k: PackedStringArray = built[(shirt * LOOKS + which + model.hash()) % built.size()].split("/")
	return _look(k[0], k[1], int(k[2]), int(k[3]))


## Builds the first body of each type, if it isn't yet: a run needs at least
## those before the dead arrive (the rest can be lent until they're made).
static func ensure_basics() -> void:
	for type in D.ZTYPES:
		if Body.built_keys(type + "/").is_empty():
			var model: String = D.ZTYPES[type]["models"][0]
			var holder := Node3D.new()
			Body.zombie(holder, _look(type, model, 0, 0))
			holder.free()


static var _to_make = null   # the bodies not made yet: [type, model, shirt, which]


## Makes one of the bodies the horde will need, ahead of time (each takes a
## moment, which would otherwise be a hitch when the first of its kind walks
## in). Call it while nothing is happening; false once they're all made.
static func prewarm() -> bool:
	if _to_make == null:
		_to_make = []
		for which in LOOKS:   # one of everything first, then the second of each
			for type in D.ZTYPES:
				var done := {}
				for model in D.ZTYPES[type]["models"]:
					if not done.has(model):
						done[model] = true
						var bare: bool = Body.ZOMBIE_MODELS[model]["top"] in ["none", "flayed"]
						for shirt in (1 if bare else D.ZTYPES[type]["shirts"].size()):
							_to_make.append([type, model, shirt, which])
	if _to_make.is_empty():
		return false
	var m: Array = _to_make.pop_front()
	var look := _look(m[0], m[1], m[2], m[3])
	if not Body.has_body(look["key"]):
		var holder := Node3D.new()
		Body.zombie(holder, look)
		holder.free()
	return true


static func _flash() -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1, 1, 1, 0.7)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _flash_mat


static func _burn() -> StandardMaterial3D:
	if _burn_mat == null:
		_burn_mat = StandardMaterial3D.new()
		_burn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_burn_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.45)
		_burn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _burn_mat


## Falls dead, one of four ways: on its face, on its back, knees buckling
## into a sideways slump, or spinning round as it drops. The body lies a while
## (the oldest sink away first if too many pile up), then sinks into the ground.
func die() -> void:
	if not meshes.is_empty():
		meshes[0].get_parent().set_process(true)   # (it may have been off screen)
	dying = true
	bar.visible = false
	_stagger = 0.0
	for m in meshes:
		m.material_overlay = null
	var heavy := scale.x > 1.3        # brutes come down slower and heavier
	var fall := 0.55 if heavy else 0.38
	var side := 1.0 if randf() < 0.5 else -1.0
	var tw := create_tween().set_parallel()
	match randi() % 4:
		0:   # Forward onto its face, arms limp.
			_go_slack(tw, fall, Vector3(-0.4, 0, 0.35), 0.2)
			_topple(tw, "rotation:x", 1.47, fall)
		1:   # Back, arms flung out.
			_go_slack(tw, fall, Vector3(-0.2, 0, 1.25), 0.1)
			tw.tween_property(j["head"], "rotation:x", -0.5, fall)
			_topple(tw, "rotation:x", -1.47, fall)
		2:   # Knees buckle, it sinks, then slumps over sideways.
			for s in ["l", "r"]:
				tw.tween_property(j["hip_" + s], "rotation:x", -1.3, fall * 0.6)
				tw.tween_property(j["knee_" + s], "rotation:x", 2.0, fall * 0.6)
			tw.tween_property(j["hips"], "position:y", Body.HIP_H - 0.45, fall * 0.6)
			tw.tween_property(j["spine"], "position:y", Body.HIP_H - 0.41, fall * 0.6)
			_go_slack(tw, fall, Vector3(0.0, 0, 0.3), 0.4)
			_topple(tw, "rotation:z", 1.4 * side, fall, fall * 0.55)
		3:   # Spun half round by the shot, dropping sideways.
			tw.tween_property(self, "rotation:y", rotation.y + 1.3 * side, fall * 0.8).set_ease(Tween.EASE_OUT)
			_go_slack(tw, fall, Vector3(-0.6, 0, 0.6), 0.3)
			_topple(tw, "rotation:z", -1.45 * side, fall, 0.08)
	# Lie there a while, then sink away and go.
	_corpses.append(self)
	while _corpses.size() > MAX_CORPSES:
		var old = _corpses.pop_front()
		if is_instance_valid(old):
			old.sink(0.0)
	sink(randf_range(CORPSE_TIME.x, CORPSE_TIME.y))


## Sinks into the ground after wait seconds, then frees itself.
func sink(wait: float) -> void:
	var tw := create_tween()
	tw.tween_interval(wait)
	tw.tween_property(self, "position:y", position.y - 0.7, 1.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_corpses.erase(self)
		queue_free())


## Tips the body over (prop: a rotation axis) to angle, landing with a little bounce.
func _topple(tw: Tween, prop: String, angle: float, t: float, delay := 0.0) -> void:
	var seq := create_tween()
	seq.tween_interval(delay)
	seq.tween_property(self, prop, angle * 1.04, t).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	seq.tween_property(self, prop, angle * 0.96, 0.08).set_ease(Tween.EASE_OUT)
	seq.tween_property(self, prop, angle, 0.1)
	tw.tween_interval(0.0)


## Arms go slack as it falls: shoulders to rot (z mirrored per side), elbows bent.
func _go_slack(tw: Tween, t: float, rot: Vector3, elbow: float) -> void:
	for s in ["l", "r"]:
		var sgn := -1.0 if s == "l" else 1.0
		tw.tween_property(j["shoulder_" + s], "rotation", Vector3(rot.x, 0, rot.z * sgn), t)
		tw.tween_property(j["elbow_" + s], "rotation:x", -elbow - randf() * 0.4, t)
	tw.tween_property(j["head"], "rotation:z", randf_range(-0.6, 0.6), t)
