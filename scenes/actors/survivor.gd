# The look of one survivor: one of the models in scenes/actors/body.gd, who
# holds their gun in both hands, turns to aim, recoils and flashes the muzzle;
# walks with a proper stride when sent somewhere; kneels to hammer at the wall
# when repairing; works the gun when reloading; and falls when killed. When
# sent scavenging they walk out through the pass and vanish until they're back.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Game = preload("res://scripts/game.gd")
const Body = preload("res://scenes/actors/body.gd")
const Guns = preload("res://scenes/actors/guns.gd")

## Light energy of the muzzle flash.
@export var flash_energy := 6.0
## Leg swing while walking, in radians.
@export var stride := 0.55

const PANTS := [Color("3b3a33"), Color("4a4137"), Color("283028"), Color("40362f"), Color("4f5440"), Color("5a5142")]
const JEANS := [Color("2f3a52"), Color("34405a"), Color("28303f")]
const HAIR := [Color("2a1d14"), Color("4a3221"), Color("1a1715"), Color("7a5a35"), Color("5c4a3a"), Color("9a8f86"), Color("b08a4a"), Color("8a3a22")]
const SHOES := [Color("231d18"), Color("3a2c22"), Color("1d1f22"), Color("5a4634")]
const CAPS := [Color("3b4a3a"), Color("5a3a2a"), Color("2f3540"), Color("6a6250")]
const UNDER := [Color("8a8578"), Color("b9b2a0"), Color("5f6a5a"), Color("7a5a52"), Color("4a5560")]
const SCARVES := [Color("6a5f4a"), Color("7a3a2e"), Color("4a5a4a"), Color("5a5a66")]
## Whose build is a woman's (anyone else by the roll of their id).
const WOMEN := ["Dana", "Priya", "June", "Ada", "Rosa", "Imke"]
const MEN := ["Marek", "Hollis", "Tomas", "Kofi", "Lev", "Sol"]

@onready var label: Label3D = $NameLabel
@onready var ring: MeshInstance3D = $Ring

var hovered := false
var selected := false
var upper: Node3D           # the spine: chest, head and arms, which turn to aim
var hips: Node3D            # pelvis and legs, which face where they walk
var j := {}                 # the body's joints (see body.gd)
var gun_pivot: Node3D
var gun: MeshInstance3D
var muzzle: Node3D
var flash_mesh: MeshInstance3D
var flash_light: OmniLight3D
var _bar: Node3D            # reload progress, over their head
var _bar_fill: MeshInstance3D
var _hp_bar: Node3D         # health, over their head when they're hurt
var _hp_fill: MeshInstance3D

var _weapon := ""
var _height := D.DECK_H
var _heading := 0.0
var _last := Vector2.ZERO
var _phase := 0.0
var _t := 0.0


## A small bar that floats over their head.
func _make_bar(y: float, color: Color) -> Array:
	var bar := Node3D.new()
	bar.position = Vector3(0, y, 0)
	add_child(bar)
	var fill_node: MeshInstance3D
	for fill in [false, true]:
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.07)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 2 if fill else 1
		m.albedo_color = color if fill else Color(0.05, 0.05, 0.06, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.add_child(mi)
		if fill:
			fill_node = mi
	bar.visible = false
	return [bar, fill_node]


## What a survivor looks like: the same every time they're seen (by their id).
## You are the scout: hood up, cap, dust mask, a pack with an axe on it.
## model: which of Body.SURVIVOR_MODELS to be (else by their id).
static func look_of(s: Dictionary, model := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["id"]) * 7919 + 13
	var fem: bool = rng.randf() < 0.5
	if s["name"] in WOMEN:
		fem = true
	elif s["name"] in MEN or s["is_player"]:
		fem = false
	if model == "":
		# (The ranger, hat and pack, is only ever the one rescued from the cabin.)
		var pick: Array = ["tank", "jacket", "hooded", "tank"] if fem else ["soldier", "jacket", "hooded", "tank"]
		model = "scout" if s["is_player"] else s.get("model", pick[rng.randi() % pick.size()])
	var M: Dictionary = Body.SURVIVOR_MODELS[model]
	var look: Dictionary = M.duplicate()
	var styles: Array = M["hair"]
	if fem:   # short hair is the exception
		styles = styles.filter(func(k): return k != "buzz")
		if rng.randf() < 0.6:
			styles = ["ponytail", "long"]
	else:
		styles = styles.filter(func(k): return k != "ponytail") if rng.randf() < 0.8 else styles
	var pants: Array = JEANS if M["legs"] == "jeans" else PANTS
	var shoes: Array = M.get("shoes", SHOES)
	look.merge({
		"skin": s["skin"], "shirt": s["jacket"], "build": "f" if fem else "m",
		"pants": pants[rng.randi() % pants.size()], "shoes": shoes[rng.randi() % shoes.size()],
		"hair": HAIR[rng.randi() % HAIR.size()], "hair_style": styles[rng.randi() % styles.size()],
		"cap": CAPS[rng.randi() % CAPS.size()] if M.get("cap", false) or (not M.get("hood", false) and rng.randf() < 0.2) else null,
		"beard": 0.0 if fem else (rng.randf_range(0.5, 1.0) if rng.randf() < M.get("beard", 0.0) else (0.3 if rng.randf() < 0.4 else 0.0)),
		"under": UNDER[rng.randi() % UNDER.size()], "scarf_col": SCARVES[rng.randi() % SCARVES.size()],
		"width": rng.randf_range(0.96, 1.06) * (0.94 if fem else 1.0), "rng": rng,
		"key": "s/%d/%s/%s/%s/%s" % [s["id"], model, s["skin"].to_html(), s["jacket"].to_html(), s["name"]],
	}, true)
	return look


func setup(s: Dictionary, model := "") -> void:
	var look := look_of(s, model)
	if look["build"] == "f":
		scale = Vector3.ONE * 0.95
	j = Body.survivor(self, look)
	upper = j["spine"]
	hips = j["hips"]
	# The gun, held in front at chest height, and its muzzle flash.
	gun_pivot = Node3D.new()
	gun_pivot.position = Vector3(0.06, 0.3, 0.2)
	upper.add_child(gun_pivot)
	gun = MeshInstance3D.new()
	gun.material_override = Guns.material()
	gun_pivot.add_child(gun)
	muzzle = Node3D.new()
	gun_pivot.add_child(muzzle)
	flash_mesh = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.1
	fm.height = 0.2
	fm.radial_segments = 6
	fm.rings = 3
	flash_mesh.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(4, 3, 1.2)
	flash_mesh.material_override = fmat
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.visible = false
	muzzle.add_child(flash_mesh)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1, 0.8, 0.45)
	flash_light.light_energy = 0.0
	flash_light.omni_range = 5.0
	muzzle.add_child(flash_light)
	var r := _make_bar(1.95, Color(1.0, 0.8, 0.3))
	_bar = r[0]
	_bar_fill = r[1]
	var h := _make_bar(2.07, Color(0.85, 0.2, 0.15))
	_hp_bar = h[0]
	_hp_fill = h[1]
	label.position.y = 2.2
	label.text = s["name"]
	ring.visible = false
	_last = Vector2(s["x"], s["y"])
	_height = _ground_height(s)
	sync(s, 0.0)


func _ground_height(s: Dictionary) -> float:
	return D.DECK_H if Game.on_deck(Vector2(s["x"], s["y"])) else 0.0


# --- Poses --------------------------------------------------------------------
## Both hands on the gun, held out in front.
func _pose_aim(k := 1.0) -> void:
	_arm("r", Vector3(-1.25, 0.0, -0.3) * k, -0.55 * k)
	_arm("l", Vector3(-1.45, 0.0, 0.45) * k, -0.25 * k)


func _arm(s: String, shoulder: Vector3, elbow: float) -> void:
	j["shoulder_" + s].rotation = j["shoulder_" + s].rotation.lerp(shoulder, 0.35)
	j["elbow_" + s].rotation.x = lerpf(j["elbow_" + s].rotation.x, elbow, 0.35)


func _legs(hl: float, kl: float, hr: float, kr: float) -> void:
	j["hip_l"].rotation.x = hl
	j["knee_l"].rotation.x = kl
	j["hip_r"].rotation.x = hr
	j["knee_r"].rotation.x = kr


func sync(s: Dictionary, dt: float) -> void:
	_t += dt
	var state: String = s["state"]
	visible = state != "away" and state != "aboard"
	_bar.visible = false
	label.font_size = 40   # (bigger only while picked: see below)
	label.outline_size = 10
	# Health, when they're hurt.
	var hp_frac: float = clampf(s.get("hp", 1.0) / s.get("max_hp", 1.0), 0.0, 1.0)
	_hp_bar.visible = hp_frac < 0.999 and state != "dead"
	_hp_fill.scale.x = maxf(0.001, hp_frac)
	_hp_fill.position.x = -0.3 * (1.0 - hp_frac)
	if state == "dead":
		# Fallen where they stood.
		rotation = Vector3(-PI / 2, rotation.y, 0)
		position.y = _height + 0.12
		label.text = s["name"] + " · down"
		label.modulate = Color(1, 0.5, 0.45, 0.8)
		flash_mesh.visible = false
		flash_light.light_energy = 0.0
		_overlay(false)
		return
	rotation.x = 0.0
	_overlay(s.get("hurt", 0.0) > 0.0)
	# The ring marks you, and turns gold on whoever is selected.
	ring.visible = selected   # only under whoever is picked
	if selected and ring.material_override == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.8, 0.3)
		ring.material_override = m
	elif not selected and ring.material_override != null:
		ring.material_override = null
	if not visible:
		_last = Vector2(s["x"], s["y"])
		return
	var pos := Vector2(s["x"], s["y"])
	_height = move_toward(_height, _ground_height(s), dt * 2.5)
	position = Vector3(pos.x, _height, pos.y)
	if s["weapon"] != _weapon:
		_set_weapon(s["weapon"])
	var hip_y := Body.HIP_H
	flash_mesh.visible = false
	flash_light.light_energy = 0.0
	gun.visible = true
	upper.rotation.x = 0.0

	if state != "wall":
		# Walking: a stride with bending knees, the gun carried low.
		var step := pos - _last
		if step.length() > 0.0005:
			_heading = atan2(step.x, step.y)
		# Stride by distance walked, so the feet stay planted.
		_phase += minf(step.length(), 0.5) / Body.stride_cycle(stride) * TAU
		var sw := sin(_phase)
		_legs(Body.hip_swing(_phase, stride), maxf(0.0, -cos(_phase)) * 0.9, Body.hip_swing(_phase + PI, stride), maxf(0.0, cos(_phase)) * 0.9)
		var bob := absf(cos(_phase)) * 0.035
		hips.position.y = hip_y + bob
		upper.position = Vector3(0, hip_y + 0.04 + bob, 0)
		hips.rotation.y = lerp_angle(hips.rotation.y, _heading, 0.3)
		upper.rotation.y = hips.rotation.y
		upper.rotation.z = sw * 0.03
		_pose_aim(0.7)
		gun_pivot.rotation.x = lerpf(gun_pivot.rotation.x, 0.5, 0.3)
		if state == "moving":
			label.text = s["name"] + " · on the way"
			label.modulate = Color(1, 1, 1, 0.8)
		else:
			# Fade out as they disappear up the pass, and in as they come back.
			label.text = s["name"]
			label.modulate.a = 0.8 * clampf((1.0 - s["path_t"]) * 8.0, 0.0, 1.0)
	elif s.get("repairing", false) or s.get("fixing", false):
		# Down on one knee at the wall (or a turret's tower), hammering.
		_phase += dt * 11.0
		var n: Vector2 = D.LANES[s["side"]]["n"]
		var face := atan2(-n.x, -n.y)
		if s.get("fixing", false) and s.has("fix_turret"):
			var t: Dictionary = s["fix_turret"]
			face = atan2(t["x"] - s["x"], t["y"] - s["y"])
		hips.rotation.y = face
		upper.rotation.y = face
		_legs(-1.45, 1.55, 0.1, 1.5)
		hips.position.y = hip_y - 0.32
		upper.position = Vector3(0, hip_y - 0.28, 0)
		upper.rotation.x = 0.35
		upper.rotation.z = 0.0
		gun.visible = false
		_arm("r", Vector3(-1.1 - absf(sin(_phase)) * 0.9, 0.0, -0.1), -0.6)
		_arm("l", Vector3(-1.0, 0.0, 0.2), -0.4)
		label.text = s["name"] + " · repairing"
		label.modulate = Color(1.0, 0.85, 0.45, 1.0)
	else:
		# On the walkway, aiming.
		hips.position.y = hip_y
		upper.rotation.z = 0.0
		var reloading: bool = s.get("reload", 0.0) > 0.0
		if selected:
			# Picked: say how to repair, big, and how to move them, under it.
			label.text = "Click again to REPAIR\n%s · or click where to go" % s["name"]
		else:
			label.text = s["name"] + ("  ·  click to select" if hovered else "")
		label.modulate = Color(1.0, 0.9, 0.6, 1.0) if hovered or selected else Color(1, 1, 1, 0.8)
		label.font_size = 72 if selected else 40
		label.outline_size = 16 if selected else 10
		if reloading and not selected:
			label.text = s["name"] + "  ·  reloading"
		# Sim angle is in the ground plane (x, y) -> world (x, z).
		var ang: float = s["aim"]
		var face := atan2(cos(ang), sin(ang))
		upper.rotation.y = face
		if (pos - _last).length() <= 0.001:
			hips.rotation.y = lerp_angle(hips.rotation.y, face, 0.15)
		var step := pos - _last
		if step.length() > 0.001 and dt > 0.0:
			# Walking (you, with the keys) while still aiming: the legs stride
			# the way you're going, the gun stays on target. Going away from
			# where you aim, you walk backwards: hips to the front, the stride
			# played in reverse, shorter steps.
			_heading = atan2(step.x, step.y)
			var backwards := absf(angle_difference(face, _heading)) > deg_to_rad(105.0)
			var stroke := stride * (0.7 if backwards else 1.0)
			var adv := minf(step.length(), 0.5) / Body.stride_cycle(stroke) * TAU
			_phase += -adv if backwards else adv
			_legs(Body.hip_swing(_phase, stroke), maxf(0.0, -cos(_phase)) * 0.9, Body.hip_swing(_phase + PI, stroke), maxf(0.0, cos(_phase)) * 0.9)
			hips.rotation.y = lerp_angle(hips.rotation.y, _heading + PI if backwards else _heading, 0.3)
		else:
			# A slightly wide, braced stance; a little breathing.
			_legs(0.12, 0.08, -0.12, 0.05)
		var breathe := sin(_t * 1.7) * 0.008
		var recoil: float = s["recoil"] * 0.9
		upper.position = Vector3(0, hip_y + 0.04 + breathe, 0) - Vector3(cos(ang), 0, sin(ang)) * recoil
		# Reloading: the gun tips up, the other hand works it, a bar fills up.
		_bar.visible = reloading
		if reloading:
			var done: float = 1.0 - s["reload"] / maxf(0.01, s.get("reload_max", 1.0))
			_bar_fill.scale.x = maxf(0.001, done)
			_bar_fill.position.x = -0.3 * (1.0 - done)
			_phase += dt * 14.0
			gun_pivot.rotation.x = lerpf(gun_pivot.rotation.x, -0.9, 0.3)
			_arm("r", Vector3(-1.0, 0.0, -0.3), -0.9)
			_arm("l", Vector3(-0.9 + sin(_phase) * 0.35, 0.0, 0.5), -1.0)
		else:
			gun_pivot.rotation.x = lerpf(gun_pivot.rotation.x, -recoil * 0.6, 0.4)
			_pose_aim()
		var firing: bool = s["flash"] > 0
		flash_mesh.visible = firing
		flash_light.light_energy = flash_energy if firing else 0.0
		if firing:
			flash_mesh.rotation.z = randf() * TAU
			flash_mesh.scale = Vector3.ONE * randf_range(0.8, 1.3)
	_last = pos


func _set_weapon(key: String) -> void:
	_weapon = key
	var w: Dictionary = D.WEAPONS[key]
	var g := Guns.get_gun(key, w["len"])
	gun.mesh = g["mesh"]
	gun.scale = Vector3.ONE * g["scale"]
	gun.position = Guns.HOLD
	muzzle.position = Guns.HOLD + Vector3(0, 0.01, g["muzzle"])


var _hit_mat: StandardMaterial3D
var _hit_on := false


## A red flash when they're hit.
func _overlay(on: bool) -> void:
	if on == _hit_on:
		return
	_hit_on = on
	if _hit_mat == null:
		_hit_mat = StandardMaterial3D.new()
		_hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.5)
		_hit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in j.get("meshes", []):
		m.material_overlay = _hit_mat if on else null
