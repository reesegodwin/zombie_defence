# Builds the people of the game in one cartoon style: big heads, big eyes,
# long limbs. zombie(): a gaunt, bald corpse with bulging eyes, a gaping toothy
# mouth, pointed ears, bony arms and bare feet, in a torn, stained T-shirt and
# ragged cut-off trousers. survivor(): a living person with hair, brows, a
# proper nose, a jacket or T-shirt, trousers and boots, maybe a backpack.
#
# Both share one skeleton of joints, so the actor scripts pose them the same
# way: "hips" (pelvis and legs, which face where you walk) and "spine" (chest,
# head and arms, which face where you aim), both at hip height on the node you
# build onto. Limbs hang straight down at rest; rotating a shoulder or hip by
# -PI/2 on x swings it forward (+z). The parts on each joint are merged into
# one mesh, so a body is about a dozen meshes and a big horde stays cheap.
#
# Vertex colours carry the colours (stains are painted onto the clothes per
# body); their alpha tells the shader (body.gdshader) what each surface is, so
# it can add veins to dead skin, blotches to living skin and a weave to cloth.
extends RefCounted

const HIP_H := 0.93
const LEG := 0.89        # hip joint to sole, metres: how far a foot swings out


## How far a body walks in one full stride cycle (two steps) when its hips
## swing amplitude radians either way: a planted foot sweeps 2 * LEG * sin(a)
## back per step. Drive the walk by distance / this * TAU and the feet stay
## planted instead of sliding.
static func stride_cycle(amplitude: float, scale := 1.0) -> float:
	return 4.0 * LEG * scale * sin(amplitude)


## A hip's swing (radians, positive is back) at phase in the stride cycle,
## for the left leg (the right is the same at phase + PI). The foot moves at
## an even pace, not a sine: so while it's planted (the half of the cycle
## when cos(phase) > 0) it sweeps back exactly as fast as the body goes
## forward, and doesn't slip.
static func hip_swing(phase: float, amplitude: float) -> float:
	var tri := asin(sin(phase)) * 2.0 / PI    # -1..1, rising while cos(phase) > 0
	return asin(sin(amplitude) * tri)
const SKIN := 1.0        # dead skin: veins and mottling
const LIVE := 0.75       # living skin: faint blotches
const CLOTH := 0.5
const PLAIN := 0.0

const BLOOD := Color(0.30, 0.05, 0.03)
const DIRT := Color(0.27, 0.20, 0.12)
const MOUTH := Color(0.3, 0.06, 0.05)
const TEETH := Color(0.86, 0.80, 0.62)
const EYE_WHITE := Color(0.93, 0.91, 0.84)
const PUPIL := Color(0.05, 0.04, 0.04)
const NAIL := Color(0.52, 0.56, 0.62)

static var _geo := {}
static var _material: ShaderMaterial
static var _noise: FastNoiseLite
static var _skin: Color   # the skin of the body being built
static var _skin_kind := SKIN


## look: skin, shirt, pants (Colors), eyes (Color, the rims), width (1.0
## normal, more for broad builds), rng (a RandomNumberGenerator for variety).
## Returns the joints: hips, spine, neck, head, shoulder_l/r, elbow_l/r,
## hand_l/r, hip_l/r, knee_l/r, and "meshes" (every MeshInstance3D made).
static func zombie(root: Node3D, look: Dictionary) -> Dictionary:
	var j := {"meshes": [], "_parts": {}}
	var w: float = look.get("width", 1.0)
	var rng: RandomNumberGenerator = look.get("rng", RandomNumberGenerator.new())
	var skin: Color = look["skin"]
	var shirt: Color = look["shirt"]
	var pants: Color = look["pants"]
	var rim: Color = look.get("eyes", Color(0.7, 0.2, 0.15)).lerp(skin, 0.35)
	var dark_skin := skin.darkened(0.25)
	var hem := rng.randi() % 4
	var limb := w * w   # broad builds have thick arms and legs too
	_skin = skin.darkened(0.1)
	_skin_kind = SKIN   # which ragged edge pattern

	# --- Lower body: pelvis, legs and bare feet -----------------------------
	var hips := _joint(root, "Hips", Vector3(0, HIP_H, 0))
	j["hips"] = hips
	_part(j, hips, "pelvis", pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "pants")
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var hip := _joint(hips, "Hip" + s, Vector3(side * 0.085 * w, -0.04, 0))
		_part(j, hip, "thigh", pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "pants")
		var knee := _joint(hip, "Knee" + s, Vector3(0, -0.43, 0))
		_part(j, knee, "trouser_leg%d" % ((hem + side + 2) % 4), pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "pants")
		_part(j, knee, "shin", skin, SKIN, Vector3.ZERO, Vector3(limb, 1, limb))
		_part(j, knee, "ankle", skin, SKIN, Vector3(side * 0.012, -0.405, 0), Vector3.ONE)
		_part(j, knee, "foot", skin, SKIN, Vector3(0, -0.44, 0.045), Vector3.ONE, Vector3(0, side * -0.12, 0))
		for t in 5:
			var tx: float = -side * (0.024 - t * 0.012) + side * 0.004
			var big := t == 0
			_part(j, knee, "toe_big" if big else "toe", skin, SKIN,
				Vector3(tx + side * 0.01, -0.452, 0.135 - t * t * 0.0028 + (0.004 if big else 0.0)), Vector3.ONE,
				Vector3(PI / 2, side * -0.12 - side * t * 0.08, 0), "", NAIL)
		j["hip_" + s] = hip
		j["knee_" + s] = knee

	# --- Upper body: a skinny chest in a baggy shirt ------------------------
	var spine := _joint(root, "Spine", Vector3(0, HIP_H + 0.04, 0))
	j["spine"] = spine
	_part(j, spine, "shirt%d" % hem, shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "shirt")
	var neck := _joint(spine, "Neck", Vector3(0, 0.5, 0.0))
	_part(j, spine, "neck", skin, SKIN, Vector3(0, 0.44, 0.012), Vector3.ONE, Vector3(0.25, 0, 0))
	for side in [-1, 1]:   # tendons
		_part(j, spine, "tendon", skin, SKIN, Vector3(side * 0.016, 0.47, 0.03), Vector3.ONE, Vector3(0.45, 0, side * 0.35))
	var head := _joint(neck, "Head", Vector3(0, 0.08, 0.01))
	j["neck"] = neck
	j["head"] = head

	# --- The head: big, bald and skull-like --------------------------------
	_part(j, head, "cranium", skin, SKIN, Vector3(0, 0.16, -0.012), Vector3.ONE)
	_part(j, head, "muzzle", skin, SKIN, Vector3(0, 0.07, 0.045), Vector3.ONE)
	_part(j, head, "lower_jaw", skin, SKIN, Vector3(0, 0.008, 0.052), Vector3.ONE, Vector3(0.2, 0, 0))
	_part(j, head, "mouth", MOUTH, PLAIN, Vector3(0, 0.041, 0.106), Vector3.ONE)
	for k in 5:
		var tx := (k - 2) * 0.011
		var miss := rng.randf() < 0.18
		if not miss:
			_part(j, head, "tooth", TEETH, PLAIN, Vector3(tx, 0.07, 0.118 - absf(tx) * 0.5), Vector3(1, rng.randf_range(0.8, 1.25), 1))
		if k > 0 and k < 4 and rng.randf() > 0.15:
			_part(j, head, "tooth", TEETH, PLAIN, Vector3(tx, 0.012, 0.116 - absf(tx) * 0.5), Vector3(1, rng.randf_range(0.8, 1.2), 1), Vector3(PI, 0, 0))
	_part(j, head, "brow", dark_skin, SKIN, Vector3(0, 0.162, 0.088), Vector3.ONE)
	_part(j, head, "nose", skin, SKIN, Vector3(0, 0.098, 0.112), Vector3.ONE)
	for side in [-1, 1]:
		_part(j, head, "nostril", MOUTH, PLAIN, Vector3(side * 0.007, 0.088, 0.117), Vector3.ONE)
		_part(j, head, "cheek", skin, SKIN, Vector3(side * 0.058, 0.088, 0.068), Vector3.ONE)
		_part(j, head, "socket", rim, SKIN, Vector3(side * 0.04, 0.124, 0.083), Vector3.ONE)
		var eye := Vector3(side * 0.04, 0.124 + rng.randf_range(-0.004, 0.004), 0.088)
		_part(j, head, "eyeball", EYE_WHITE, PLAIN, eye, Vector3.ONE)
		var look_at := Vector3(side * rng.randf_range(-0.004, 0.006), rng.randf_range(-0.003, 0.004), 0.029)
		_part(j, head, "pupil", PUPIL, PLAIN, eye + look_at, Vector3.ONE)
		_part(j, head, "ear", skin, SKIN, Vector3(side * 0.108, 0.13, -0.012), Vector3.ONE, Vector3(-0.35, side * -0.5, side * -0.35))
	# Wrinkles across the scalp and the face.
	for k in 3:
		_part(j, head, "wrinkle", dark_skin, SKIN, Vector3(0, 0.205 + k * 0.022, 0.08 - k * 0.012), Vector3(1.0 - k * 0.08, 1, 1), Vector3(-0.25 - k * 0.15, 0, 0))

	# --- Arms: short sleeves, then long, bony and grasping ------------------
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sh := _joint(spine, "Shoulder" + s, Vector3(side * 0.18 * w, 0.42, 0))
		_part(j, sh, "sleeve%d" % ((hem + side + 4) % 4), shirt, CLOTH, Vector3.ZERO, Vector3(limb, 1, limb), Vector3(0, 0, side * 0.12), "shirt")
		_part(j, sh, "upper_arm", skin, SKIN, Vector3.ZERO, Vector3(limb, 1, limb))
		var el := _joint(sh, "Elbow" + s, Vector3(0, -0.29, 0))
		_part(j, el, "elbow", skin, SKIN, Vector3(0, 0, -0.008), Vector3(limb, 1, limb))
		_part(j, el, "forearm", skin, SKIN, Vector3.ZERO, Vector3(limb, 1, limb))
		var hand := _joint(el, "Hand" + s, Vector3(0, -0.27, 0))
		_part(j, hand, "palm", skin, SKIN, Vector3(0, -0.04, 0), Vector3.ONE)
		for f in 4:
			var fz := 0.024 - f * 0.016
			var lenk: float = [0.92, 1.0, 0.96, 0.78][f]
			_part(j, hand, "finger", skin, SKIN, Vector3(side * -0.002, -0.08 + absf(f - 1.5) * 0.004, fz), Vector3(1, lenk, 1),
				Vector3(-0.08 + f * 0.05, 0, side * (0.18 + f * 0.02)), "", NAIL)
		_part(j, hand, "finger", skin, SKIN, Vector3(side * -0.012, -0.03, 0.03), Vector3(1.1, 0.7, 1.1), Vector3(-0.7, 0, side * 0.35), "", NAIL)
		j["shoulder_" + s] = sh
		j["elbow_" + s] = el
		j["hand_" + s] = hand

	_merge(j, rng, 1.0)
	return j


const IRIS := [Color("4a3424"), Color("2f4f6a"), Color("3d5a36"), Color("5a4630"), Color("2a2a2a")]
const PACKS := [Color("4c5638"), Color("5a4532"), Color("3a4250"), Color("6a5a3a")]


## look: skin, shirt (their jacket or T-shirt), pants, shoes (Colors); hair
## (Color, or null for bald); hair_style ("short", "long", "cap"); cap (Color,
## for "cap"); sleeves ("long": a jacket, "short": a T-shirt); width (1.0
## normal); pack (bool, a backpack); rng. Returns the joints, as zombie().
static func survivor(root: Node3D, look: Dictionary) -> Dictionary:
	var j := {"meshes": [], "_parts": {}}
	var w: float = look.get("width", 1.0)
	var rng: RandomNumberGenerator = look.get("rng", RandomNumberGenerator.new())
	var skin: Color = look["skin"]
	var shirt: Color = look["shirt"].lightened(0.18)
	var pants: Color = look["pants"].lightened(0.2)
	var shoes: Color = look.get("shoes", Color("2a221c")).lightened(0.12)
	var hair = look.get("hair", null)
	var style: String = look.get("hair_style", "short")
	var jacket: bool = look.get("sleeves", "long") == "long"
	var lips := skin.darkened(0.25).lerp(Color(0.55, 0.25, 0.22), 0.3)
	var brow_col: Color = hair.darkened(0.2) if hair != null else skin.darkened(0.45)
	_skin = skin
	_skin_kind = LIVE

	# --- Lower body: trousers and boots -------------------------------------
	var hips := _joint(root, "Hips", Vector3(0, HIP_H, 0))
	j["hips"] = hips
	_part(j, hips, "pelvis", pants, CLOTH, Vector3.ZERO, Vector3(w * 1.05, 1, 1.05), Vector3.ZERO, "worn")
	_part(j, hips, "belt", Color("2b2622"), PLAIN, Vector3(0, 0.05, 0), Vector3(w * 1.05, 1, 1.05))
	_part(j, hips, "buckle", Color("8a8070"), PLAIN, Vector3(0, 0.05, 0.1), Vector3.ONE)
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var hip := _joint(hips, "Hip" + s, Vector3(side * 0.09 * w, -0.04, 0))
		_part(j, hip, "thigh", pants, CLOTH, Vector3.ZERO, Vector3(w * 1.1, 1, 1.1), Vector3.ZERO, "worn")
		var knee := _joint(hip, "Knee" + s, Vector3(0, -0.43, 0))
		_part(j, knee, "trousers", pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "worn")
		_part(j, knee, "boot_top", shoes, PLAIN, Vector3(0, -0.36, 0.0), Vector3.ONE)
		_part(j, knee, "boot", shoes, PLAIN, Vector3(0, -0.437, 0.04), Vector3(1.25, 1.2, 1.05))
		_part(j, knee, "sole", shoes.darkened(0.5), PLAIN, Vector3(0, -0.462, 0.04), Vector3.ONE)
		j["hip_" + s] = hip
		j["knee_" + s] = knee

	# --- Upper body ---------------------------------------------------------
	var spine := _joint(root, "Spine", Vector3(0, HIP_H + 0.04, 0))
	j["spine"] = spine
	if jacket:
		_part(j, spine, "jacket", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "worn")
		_part(j, spine, "collar", shirt.darkened(0.12), CLOTH, Vector3(0, 0.455, -0.008), Vector3(w, 1, 1))
		_part(j, spine, "zip", shirt.darkened(0.4), PLAIN, Vector3(0, 0.2, 0.0), Vector3(w, 1, 1))
	else:
		_part(j, spine, "tee", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "tee")
	_part(j, spine, "neck_live", skin, LIVE, Vector3(0, 0.42, 0.008), Vector3.ONE, Vector3(0.12, 0, 0))
	if look.get("pack", false):
		var pc: Color = PACKS[rng.randi() % PACKS.size()]
		_part(j, spine, "pack", pc, CLOTH, Vector3(0, 0.25, -0.17), Vector3(w, 1, 1))
		_part(j, spine, "pack_flap", pc.darkened(0.15), CLOTH, Vector3(0, 0.37, -0.175), Vector3(w, 1, 1), Vector3(-0.2, 0, 0))
		_part(j, spine, "pack_pocket", pc.darkened(0.08), CLOTH, Vector3(0, 0.17, -0.235), Vector3(w, 1, 1))
		for side in [-1, 1]:
			_part(j, spine, "strap", pc.darkened(0.3), PLAIN, Vector3(side * 0.085 * w, 0.3, 0.0), Vector3(1, 1, w), Vector3(0, 0, side * 0.08))
	var neck := _joint(spine, "Neck", Vector3(0, 0.47, 0.0))
	var head := _joint(neck, "Head", Vector3(0, 0.08, 0.01))
	j["neck"] = neck
	j["head"] = head

	# --- The head -------------------------------------------------------------
	_part(j, head, "cranium", skin, LIVE, Vector3(0, 0.16, -0.012), Vector3.ONE)
	_part(j, head, "face", skin, LIVE, Vector3(0, 0.08, 0.04), Vector3.ONE)
	_part(j, head, "chin", skin, LIVE, Vector3(0, 0.03, 0.05), Vector3.ONE)
	_part(j, head, "lips", lips, LIVE, Vector3(0, 0.052, 0.104), Vector3.ONE)
	_part(j, head, "s_nose", skin, LIVE, Vector3(0, 0.094, 0.108), Vector3.ONE, Vector3(-0.2, 0, 0))
	var iris: Color = IRIS[rng.randi() % IRIS.size()]
	var glance := Vector3(rng.randf_range(-0.003, 0.003), rng.randf_range(-0.002, 0.002), 0.0)
	for side in [-1, 1]:
		var eye := Vector3(side * 0.038, 0.126, 0.086)
		_part(j, head, "s_cheek", skin, LIVE, Vector3(side * 0.05, 0.088, 0.064), Vector3.ONE)
		_part(j, head, "s_eyeball", EYE_WHITE, PLAIN, eye, Vector3.ONE)
		_part(j, head, "iris", iris, PLAIN, eye + Vector3(0, 0, 0.022) + glance, Vector3.ONE)
		_part(j, head, "pupil", PUPIL, PLAIN, eye + Vector3(0, 0, 0.0255) + glance, Vector3(0.75, 0.75, 1))
		_part(j, head, "lid", skin.darkened(0.06), LIVE, eye, Vector3.ONE, Vector3(-0.15, 0, 0))
		_part(j, head, "s_brow", brow_col, PLAIN, Vector3(side * 0.04, 0.16, 0.106), Vector3.ONE, Vector3(0, side * 0.25, side * -0.12))
		_part(j, head, "s_ear", skin, LIVE, Vector3(side * 0.104, 0.125, -0.01), Vector3.ONE, Vector3(0, side * -0.3, 0))
	if hair != null:
		var hm: Color = hair
		match style:
			"long":
				_part(j, head, "hair", hm, CLOTH, Vector3(0, 0.16, -0.012), Vector3.ONE)
				_part(j, head, "hair_long", hm, CLOTH, Vector3(0, 0.12, -0.05), Vector3.ONE)
			"cap":
				var cc: Color = look.get("cap", Color("3a3f35"))
				_part(j, head, "hair_under_cap", hm, CLOTH, Vector3(0, 0.16, -0.012), Vector3.ONE)
				_part(j, head, "cap", cc, CLOTH, Vector3(0, 0.17, -0.012), Vector3.ONE)
				_part(j, head, "cap_brim", cc.darkened(0.1), CLOTH, Vector3(0, 0.205, 0.11), Vector3.ONE, Vector3(0.18, 0, 0))
			_:
				_part(j, head, "hair", hm, CLOTH, Vector3(0, 0.16, -0.012), Vector3.ONE)
		if style != "long" and rng.randf() < 0.3:
			_part(j, head, "beard", hm, CLOTH, Vector3(0, 0.05, 0.03), Vector3.ONE)

	# --- Arms -----------------------------------------------------------------
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sh := _joint(spine, "Shoulder" + s, Vector3(side * 0.19 * w, 0.42, 0))
		var el := _joint(sh, "Elbow" + s, Vector3(0, -0.29, 0))
		var hand := _joint(el, "Hand" + s, Vector3(0, -0.27, 0))
		if jacket:
			_part(j, sh, "jacket_arm", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, w), Vector3(0, 0, side * 0.08), "worn")
			_part(j, el, "s_elbow", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, w))
			_part(j, el, "jacket_forearm", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, w), Vector3.ZERO, "worn")
			_part(j, el, "cuff", shirt.darkened(0.15), CLOTH, Vector3(0, -0.235, 0), Vector3(w, 1, w))
		else:
			_part(j, sh, "tee_sleeve", shirt, CLOTH, Vector3.ZERO, Vector3(w, 1, w), Vector3(0, 0, side * 0.1), "tee")
			_part(j, sh, "s_upper_arm", skin, LIVE, Vector3.ZERO, Vector3(w, 1, w))
			_part(j, el, "s_elbow", skin, LIVE, Vector3.ZERO, Vector3(w, 1, w))
			_part(j, el, "s_forearm", skin, LIVE, Vector3.ZERO, Vector3(w, 1, w))
		_part(j, hand, "palm", skin, LIVE, Vector3(0, -0.035, 0), Vector3(1.4, 0.9, 1.1))
		for f in 4:
			var fz := 0.022 - f * 0.015
			_part(j, hand, "finger", skin, LIVE, Vector3(side * -0.003, -0.072, fz), Vector3(1.35, 0.75, 1.3),
				Vector3(-0.1 + f * 0.04, 0, side * 0.3))
		_part(j, hand, "finger", skin, LIVE, Vector3(side * -0.012, -0.025, 0.03), Vector3(1.45, 0.6, 1.4), Vector3(-0.8, 0, side * 0.35))
		j["shoulder_" + s] = sh
		j["elbow_" + s] = el
		j["hand_" + s] = hand

	_merge(j, rng, 0.35)
	return j


static func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	return node


## Adds a part to a joint; paint ("shirt" or "pants") stains and rips it.
## tip: a colour for the far end of a finger or toe (its nail).
static func _part(j: Dictionary, parent: Node3D, kind: String, col: Color, surface: float, pos: Vector3,
		scl: Vector3, rot := Vector3.ZERO, paint := "", tip = null) -> void:
	if not j["_parts"].has(parent):
		j["_parts"][parent] = []
	var xf := Transform3D(Basis.from_euler(rot).scaled(scl), pos)
	j["_parts"][parent].append([kind, Color(col, surface), xf, paint, tip])


## One mesh per joint, colours (and stains) baked into its vertices.
## dirt: how stained the clothes are (1 for the dead).
static func _merge(j: Dictionary, rng: RandomNumberGenerator, dirt: float) -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 7.0
	var seed_off := Vector3(rng.randf() * 100.0, rng.randf() * 100.0, rng.randf() * 100.0)
	for joint in j["_parts"]:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		# Offset each joint's stains so the two legs don't match.
		var off: Vector3 = seed_off + Vector3(joint.position.x, 0, 0) * 37.0
		for part in j["_parts"][joint]:
			var g: Array = _geometry(part[0])
			var xf: Transform3D = part[2]
			var nb := xf.basis.inverse().transposed()
			var base := verts.size()
			var col: Color = part[1]
			var paint: String = part[3]
			var tips: PackedFloat32Array = g[3]
			for k in g[0].size():
				var v: Vector3 = xf * g[0][k]
				verts.append(v)
				norms.append((nb * g[1][k]).normalized())
				var c := col
				if part[4] != null and tips[k] > 0.0:
					c = Color(col.lerp(part[4], tips[k]), PLAIN if tips[k] > 0.5 else col.a)
				if paint != "":
					c = _stain(c, v, paint, off, dirt)
				cols.append(c)
			for i in g[2]:
				idx.append(base + i)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material()
		joint.add_child(mi)
		j["meshes"].append(mi)
	j.erase("_parts")


## Blood, grime and the odd rip showing skin, painted onto the clothes.
static func _stain(c: Color, v: Vector3, paint: String, off: Vector3, dirt: float) -> Color:
	var p := v + off
	var n := _noise.get_noise_3dv(p)
	var n2 := _noise.get_noise_3dv(p * 2.3 + Vector3(17, 3, 9))
	var out := c
	if paint == "shirt" and v.z > 0.0 and v.y > 0.425 and absf(v.x) < 0.02:
		return Color(_skin, _skin_kind)   # the V of the collar shows the chest
	# Grime collects lower down.
	var grime := smoothstep(0.1, 0.6, n2) * 0.6 * dirt
	if paint == "shirt":
		grime += smoothstep(0.25, -0.05, v.y) * 0.25
	out = Color(out.lerp(DIRT, grime), c.a)
	var blood := smoothstep(0.2, 0.55, n) * dirt * dirt
	if paint == "pants":
		blood *= 0.6
	out = Color(out.lerp(BLOOD, blood * 0.85), c.a)
	return out


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/body.gdshader")
	return _material


# --- Shapes ------------------------------------------------------------------

## A shape's [vertices, normals, indices, tip weights], made on first use.
static func _geometry(kind: String) -> Array:
	if _geo.has(kind):
		return _geo[kind]
	var g: Array
	var base := kind.rstrip("0123456789")
	var variant := int(kind.substr(base.length())) if base.length() < kind.length() else 0
	match base:
		"pelvis":
			g = _loft([[0.07, 0.11, 0.075, -0.005], [0.0, 0.14, 0.095, 0.0], [-0.09, 0.145, 0.095, 0.0], [-0.14, 0.12, 0.08, 0.0]], 12)
		"thigh":
			g = _loft([[0.02, 0.07, 0.072, 0.0], [-0.2, 0.068, 0.07, 0.004], [-0.42, 0.06, 0.062, 0.006], [-0.47, 0.058, 0.06, 0.006]], 10)
		"trouser_leg":
			g = _loft([[0.03, 0.06, 0.062, 0.006], [-0.1, 0.062, 0.063, 0.003], [-0.22, 0.07, 0.068, 0.0]], 10, true, false, 0.035, variant)
		"shin":
			g = _loft([[-0.05, 0.034, 0.036, 0.0], [-0.17, 0.033, 0.036, -0.004], [-0.3, 0.026, 0.027, 0.0], [-0.4, 0.022, 0.024, -0.004]], 8)
		"ankle":
			g = _ellipsoid(Vector3(0.016, 0.016, 0.016), 6, 4)
		"foot":
			g = _ellipsoid(Vector3(0.042, 0.024, 0.1), 10, 6, func(p: Vector3) -> Vector3:
				# Flat sole, high instep at the back, toes splay wider at the front.
				var q := p
				q.y = maxf(q.y, -0.012)
				if p.z < 0.0 and p.y > 0.0:
					q.y += 0.006
				q.x *= 1.0 + clampf(p.z / 0.1, 0.0, 1.0) * 0.25
				return q)
		"toe", "toe_big":
			var r := 0.013 if base == "toe_big" else 0.008
			var l := 0.034 if base == "toe_big" else 0.024
			g = _loft([[0.0, r, r, 0.0], [-l * 0.6, r, r * 0.95, 0.0], [-l, r * 0.85, r * 0.8, 0.0]], 6, true, true, 0.0, 0, 0.55)
		"shirt":
			# Hem to collar; ragged at the bottom, a little hunched at the top.
			g = _loft([[0.5, 0.06, 0.05, -0.015], [0.47, 0.115, 0.08, -0.015], [0.44, 0.165, 0.098, -0.01], [0.41, 0.17, 0.102, -0.007], [0.38, 0.172, 0.105, -0.004],
				[0.3, 0.165, 0.108, 0.0], [0.18, 0.152, 0.104, 0.004], [0.06, 0.15, 0.1, 0.0], [-0.06, 0.155, 0.104, 0.0], [-0.11, 0.158, 0.106, 0.0]],
				16, true, false, 0.045, variant)
		"neck":
			g = _loft([[0.15, 0.03, 0.034, -0.01], [0.08, 0.03, 0.032, 0.0], [0.0, 0.032, 0.034, 0.0], [-0.04, 0.042, 0.04, 0.0]], 8)
		"tendon":
			g = _loft([[0.06, 0.007, 0.007, 0.0], [-0.06, 0.009, 0.009, 0.0]], 5)
		"cranium":
			g = _ellipsoid(Vector3(0.108, 0.13, 0.125), 14, 9, func(p: Vector3) -> Vector3:
				# Narrower at the temples, bulging at the back.
				var q := p
				q.x *= 1.0 - 0.12 * clampf(-p.y / 0.13, 0.0, 1.0) - 0.06 * clampf(p.z / 0.125, 0.0, 1.0)
				q.z *= 1.0 + 0.08 * clampf(-p.z / 0.125, 0.0, 1.0)
				return q)
		"muzzle":
			g = _ellipsoid(Vector3(0.068, 0.07, 0.07), 12, 7, func(p: Vector3) -> Vector3:
				var q := p
				q.x *= 1.0 - 0.25 * clampf(p.z / 0.07, 0.0, 1.0)   # a narrow, bony face
				return q)
		"lower_jaw":
			g = _ellipsoid(Vector3(0.048, 0.03, 0.056), 10, 6, func(p: Vector3) -> Vector3:
				var q := p
				q.x *= 1.0 - 0.3 * clampf(p.z / 0.058, 0.0, 1.0)
				return q)
		"mouth":
			g = _ellipsoid(Vector3(0.029, 0.037, 0.017), 10, 6)
		"tooth":
			g = _ellipsoid(Vector3(0.0055, 0.011, 0.004), 5, 3, func(p: Vector3) -> Vector3:
				return Vector3(p.x, maxf(p.y, -0.004), p.z))
		"brow":
			g = _ellipsoid(Vector3(0.082, 0.016, 0.026), 10, 4, func(p: Vector3) -> Vector3:
				return p + Vector3(0, -absf(p.x) * 0.12, -p.x * p.x * 3.0))
		"wrinkle":
			g = _ellipsoid(Vector3(0.06, 0.003, 0.008), 8, 3, func(p: Vector3) -> Vector3:
				return p + Vector3(0, 0, -p.x * p.x * 4.0))
		"nose":
			g = _ellipsoid(Vector3(0.012, 0.016, 0.01), 6, 4)
		"nostril":
			g = _ellipsoid(Vector3(0.005, 0.004, 0.004), 5, 3)
		"cheek":
			g = _ellipsoid(Vector3(0.022, 0.016, 0.025), 7, 4)
		"socket":
			g = _ellipsoid(Vector3(0.034, 0.034, 0.02), 10, 5)
		"eyeball":
			g = _ellipsoid(Vector3(0.03, 0.03, 0.03), 12, 8)
		"pupil":
			g = _ellipsoid(Vector3(0.0085, 0.0085, 0.004), 8, 4)
		"ear":
			g = _ellipsoid(Vector3(0.007, 0.036, 0.022), 8, 6, func(p: Vector3) -> Vector3:
				var q := p
				if p.y > 0.0:   # drawn up to a point at the back
					q.z -= p.y * 0.35
					q.z *= 1.0 - p.y / 0.036 * 0.5
				return q)
		"sleeve":
			g = _loft([[0.04, 0.04, 0.048, 0.0], [0.0, 0.054, 0.054, 0.0], [-0.08, 0.052, 0.05, 0.0], [-0.13, 0.054, 0.052, 0.0]], 10, true, false, 0.025, variant)
		"upper_arm":
			g = _loft([[-0.02, 0.036, 0.036, 0.0], [-0.12, 0.031, 0.033, 0.0], [-0.27, 0.024, 0.026, 0.0]], 8)
		"elbow":
			g = _ellipsoid(Vector3(0.028, 0.03, 0.03), 7, 5)
		"forearm":
			g = _loft([[0.0, 0.027, 0.03, 0.0], [-0.06, 0.029, 0.032, 0.0], [-0.24, 0.019, 0.022, 0.0], [-0.27, 0.017, 0.021, 0.0]], 8)
		"palm":
			g = _ellipsoid(Vector3(0.013, 0.045, 0.033), 8, 5)
		# --- The living ---
		"belt":
			g = _loft([[0.025, 0.142, 0.1, 0.0], [-0.025, 0.142, 0.1, 0.0]], 12, false, false)
		"buckle":
			g = _ellipsoid(Vector3(0.02, 0.016, 0.006), 6, 3)
		"trousers":
			g = _loft([[0.03, 0.062, 0.064, 0.006], [-0.15, 0.058, 0.06, 0.003], [-0.33, 0.054, 0.056, 0.0], [-0.39, 0.056, 0.058, 0.0]], 10, true, true)
		"boot_top":
			g = _loft([[0.0, 0.05, 0.054, 0.0], [-0.08, 0.046, 0.05, 0.0]], 9, true, false)
		"boot":
			g = _ellipsoid(Vector3(0.042, 0.024, 0.1), 10, 6, func(p: Vector3) -> Vector3:
				var q := p
				q.y = maxf(q.y, -0.012)
				if p.z < 0.02 and p.y > 0.0:
					q.y += 0.012
				q.x *= 1.0 + clampf(p.z / 0.1, 0.0, 1.0) * 0.15
				return q)
		"sole":
			g = _ellipsoid(Vector3(0.054, 0.008, 0.115), 10, 3)
		"jacket":
			g = _loft([[0.5, 0.07, 0.06, -0.012], [0.47, 0.13, 0.09, -0.012], [0.44, 0.18, 0.11, -0.008], [0.38, 0.188, 0.118, -0.002],
				[0.28, 0.182, 0.122, 0.004], [0.16, 0.17, 0.118, 0.006], [0.04, 0.162, 0.112, 0.004], [-0.08, 0.162, 0.11, 0.0], [-0.12, 0.155, 0.104, 0.0]],
				16, true, true)
		"tee":
			g = _loft([[0.5, 0.065, 0.055, -0.012], [0.47, 0.125, 0.085, -0.012], [0.44, 0.172, 0.104, -0.008], [0.38, 0.178, 0.11, -0.002],
				[0.28, 0.172, 0.114, 0.004], [0.16, 0.16, 0.11, 0.006], [0.04, 0.152, 0.104, 0.004], [-0.08, 0.155, 0.104, 0.0], [-0.1, 0.15, 0.1, 0.0]],
				16, true, true)
		"collar":
			g = _loft([[0.06, 0.07, 0.06, -0.01], [0.0, 0.1, 0.085, 0.0], [-0.02, 0.11, 0.09, 0.0]], 12, false, false)
		"zip":
			g = _loft([[0.27, 0.005, 0.003, 0.116], [0.1, 0.005, 0.003, 0.118], [-0.1, 0.005, 0.003, 0.11]], 4)
		"neck_live":
			g = _loft([[0.13, 0.046, 0.048, -0.006], [0.06, 0.047, 0.049, 0.0], [-0.04, 0.054, 0.054, 0.0]], 9)
		"pack":
			g = _ellipsoid(Vector3(0.13, 0.17, 0.07), 10, 7, func(p: Vector3) -> Vector3:
				return Vector3(p.x * (1.0 + 0.25 * (1.0 - absf(p.y) / 0.17)), p.y, p.z))
		"pack_flap":
			g = _ellipsoid(Vector3(0.125, 0.05, 0.072), 10, 4)
		"pack_pocket":
			g = _ellipsoid(Vector3(0.08, 0.06, 0.03), 8, 4)
		"strap":
			g = _loft([[0.08, 0.012, 0.11, -0.03], [0.0, 0.012, 0.12, -0.03], [-0.15, 0.012, 0.115, -0.03]], 12, false, false)
		"face":
			g = _ellipsoid(Vector3(0.075, 0.075, 0.072), 12, 7, func(p: Vector3) -> Vector3:
				var q := p
				q.x *= 1.0 - 0.12 * clampf(p.z / 0.072, 0.0, 1.0)
				return q)
		"chin":
			g = _ellipsoid(Vector3(0.052, 0.035, 0.056), 10, 6, func(p: Vector3) -> Vector3:
				var q := p
				q.x *= 1.0 - 0.25 * clampf(p.z / 0.056, 0.0, 1.0)
				return q)
		"lips":
			g = _ellipsoid(Vector3(0.022, 0.006, 0.007), 8, 4, func(p: Vector3) -> Vector3:
				return p + Vector3(0, absf(p.x) * 0.15, -p.x * p.x * 4.0))
		"s_nose":
			g = _ellipsoid(Vector3(0.016, 0.026, 0.018), 8, 6, func(p: Vector3) -> Vector3:
				var q := p
				q.z += clampf(-p.y / 0.026, 0.0, 1.0) * 0.006   # a rounded tip
				q.x *= 1.0 + clampf(-p.y / 0.026, 0.0, 1.0) * 0.3
				return q)
		"s_cheek":
			g = _ellipsoid(Vector3(0.024, 0.017, 0.024), 7, 5)
		"s_eyeball":
			g = _ellipsoid(Vector3(0.025, 0.025, 0.025), 12, 8)
		"iris":
			g = _ellipsoid(Vector3(0.012, 0.012, 0.004), 10, 4)
		"lid":
			# The top half of a shell over the eye: a calm, steady look.
			g = _ellipsoid(Vector3(0.028, 0.028, 0.028), 12, 8, func(p: Vector3) -> Vector3:
				return Vector3(p.x, maxf(p.y, 0.013), p.z))
		"s_brow":
			g = _ellipsoid(Vector3(0.022, 0.006, 0.008), 7, 4, func(p: Vector3) -> Vector3:
				return p + Vector3(0, -p.x * p.x * 6.0, 0))
		"s_ear":
			g = _ellipsoid(Vector3(0.009, 0.03, 0.02), 8, 6)
		"hair", "hair_under_cap":
			# A shell over the scalp, cut along the hairline.
			var lift := 0.02 if base == "hair_under_cap" else 0.0
			g = _ellipsoid(Vector3(0.113, 0.136, 0.131), 14, 9, func(p: Vector3) -> Vector3:
				var q := p
				q.x *= 1.0 - 0.1 * clampf(-p.y / 0.138, 0.0, 1.0)
				q.z *= 1.0 + 0.08 * clampf(-p.z / 0.133, 0.0, 1.0)
				var f := clampf(p.z / 0.131 * 0.5 + 0.5, 0.0, 1.0)
				var line := lerpf(-0.1 + lift, 0.07 + lift, f * f) - absf(p.x) * 0.25 * f
				q.y = maxf(q.y, line)
				if q.y == line:
					q.x *= 0.92
					q.z *= 0.92
				return q)
		"hair_long":
			g = _loft([[0.08, 0.11, 0.07, 0.0], [-0.04, 0.115, 0.075, -0.01], [-0.14, 0.1, 0.05, -0.02]], 12, false, true, 0.02, 1)
		"cap":
			g = _ellipsoid(Vector3(0.12, 0.13, 0.136), 14, 8, func(p: Vector3) -> Vector3:
				return Vector3(p.x, maxf(p.y, 0.035), p.z))
		"cap_brim":
			g = _ellipsoid(Vector3(0.095, 0.006, 0.07), 12, 3, func(p: Vector3) -> Vector3:
				return Vector3(p.x, p.y - p.x * p.x * 3.0, maxf(p.z, -0.02)))
		"beard":
			g = _ellipsoid(Vector3(0.07, 0.06, 0.07), 12, 7, func(p: Vector3) -> Vector3:
				var q := p
				if p.y > 0.0 and p.z > 0.0:   # leave the mouth clear
					q.z -= 0.02 * clampf(p.y / 0.06, 0.0, 1.0)
				q.x *= 1.0 - 0.2 * clampf(p.z / 0.07, 0.0, 1.0)
				return q)
		"jacket_arm":
			g = _loft([[0.04, 0.048, 0.055, 0.0], [0.0, 0.062, 0.06, 0.0], [-0.15, 0.052, 0.054, 0.0], [-0.29, 0.046, 0.048, 0.0]], 10)
		"jacket_forearm":
			g = _loft([[0.0, 0.046, 0.048, 0.0], [-0.12, 0.044, 0.046, 0.0], [-0.23, 0.04, 0.042, 0.0]], 10, true, false)
		"cuff":
			g = _loft([[0.0, 0.043, 0.045, 0.0], [-0.03, 0.042, 0.044, 0.0]], 10, false, false)
		"tee_sleeve":
			g = _loft([[0.04, 0.045, 0.052, 0.0], [0.0, 0.06, 0.06, 0.0], [-0.08, 0.056, 0.055, 0.0], [-0.12, 0.055, 0.054, 0.0]], 10, true, false)
		"s_upper_arm":
			g = _loft([[-0.02, 0.044, 0.045, 0.0], [-0.12, 0.04, 0.042, 0.0], [-0.27, 0.032, 0.034, 0.0]], 8)
		"s_elbow":
			g = _ellipsoid(Vector3(0.042, 0.042, 0.044), 8, 5)
		"s_forearm":
			g = _loft([[0.0, 0.036, 0.04, 0.0], [-0.07, 0.037, 0.04, 0.0], [-0.24, 0.026, 0.029, 0.0], [-0.27, 0.024, 0.027, 0.0]], 8)
		"finger":
			g = _loft([[0.0, 0.0075, 0.0075, 0.0], [-0.03, 0.0068, 0.007, 0.0], [-0.055, 0.0058, 0.006, 0.002], [-0.075, 0.0045, 0.0048, 0.006]], 5, true, true, 0.0, 0, 0.3)
	_fix_winding(g)
	_geo[kind] = g
	return g


## A tube through rings of [y, x radius, z radius, z offset], top to bottom,
## with its ends capped. ragged: how jagged the bottom edge is (torn cloth).
## tip: how much of the far end (as a fraction of the length) gets the tip colour.
static func _loft(rings: Array, seg: int, cap_top := true, cap_bottom := true, ragged := 0.0, variant := 0, tip := 0.0) -> Array:
	var v := PackedVector3Array()
	var t := PackedFloat32Array()
	var idx := PackedInt32Array()
	var y0: float = rings[0][0]
	var y1: float = rings[rings.size() - 1][0]
	for i in rings.size():
		var r: Array = rings[i]
		for k in seg:
			var a := TAU * k / seg
			var y: float = r[0]
			if i == rings.size() - 1 and ragged > 0.0:
				var h := ((k * 7 + variant * 5) % 5) / 4.0
				y -= ragged * (h * h) - ragged * 0.3
			v.append(Vector3(sin(a) * r[1], y, r[3] + cos(a) * r[2]))
			t.append(_tip_weight(y, y0, y1, tip))
	for i in rings.size() - 1:
		for k in seg:
			var a := i * seg + k
			var b := i * seg + (k + 1) % seg
			var c := a + seg
			var d := b + seg
			idx.append_array([a, b, c, b, d, c])
	if cap_top:
		v.append(Vector3(0, y0 + 0.002, rings[0][3]))
		t.append(_tip_weight(y0, y0, y1, tip))
		var ci := v.size() - 1
		for k in seg:
			idx.append_array([ci, (k + 1) % seg, k])
	if cap_bottom:
		var last := (rings.size() - 1) * seg
		var r: Array = rings[rings.size() - 1]
		v.append(Vector3(0, y1 - minf(r[1], r[2]) * 0.6, r[3]))
		t.append(_tip_weight(y1, y0, y1, tip))
		var ci := v.size() - 1
		for k in seg:
			idx.append_array([ci, last + k, last + (k + 1) % seg])
	return [v, _normals(v, idx), idx, t]


static func _tip_weight(y: float, y0: float, y1: float, tip: float) -> float:
	if tip <= 0.0:
		return 0.0
	var f := (y - y0) / (y1 - y0)
	return smoothstep(1.0 - tip, 1.0 - tip * 0.6, f)


## A squashed sphere; deform(p) can bend each point.
static func _ellipsoid(r: Vector3, seg: int, rings: int, deform := Callable()) -> Array:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	v.append(Vector3(0, r.y, 0))
	for i in range(1, rings):
		var phi := PI * i / rings
		for k in seg:
			var a := TAU * k / seg
			v.append(Vector3(sin(phi) * sin(a) * r.x, cos(phi) * r.y, sin(phi) * cos(a) * r.z))
	v.append(Vector3(0, -r.y, 0))
	var bottom := v.size() - 1
	for k in seg:
		idx.append_array([0, 1 + (k + 1) % seg, 1 + k])
	for i in rings - 2:
		for k in seg:
			var a := 1 + i * seg + k
			var b := 1 + i * seg + (k + 1) % seg
			idx.append_array([a, b, a + seg, b, b + seg, a + seg])
	var last := 1 + (rings - 2) * seg
	for k in seg:
		idx.append_array([bottom, last + k, last + (k + 1) % seg])
	if deform.is_valid():
		for k in v.size():
			v[k] = deform.call(v[k])
	var t := PackedFloat32Array()
	t.resize(v.size())
	return [v, _normals(v, idx), idx, t]


## Smooth normals, averaged from the faces around each point.
static func _normals(v: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	for i in range(0, idx.size(), 3):
		var a := v[idx[i]]
		var f := (v[idx[i + 2]] - a).cross(v[idx[i + 1]] - a)
		for k in 3:
			n[idx[i + k]] += f
	for k in n.size():
		n[k] = n[k].normalized() if n[k].length_squared() > 0.0 else Vector3.UP
	return n


## Makes sure a shape's faces (and normals) point outwards, the way Godot
## expects (clockwise seen from outside).
static func _fix_winding(g: Array) -> void:
	var v: PackedVector3Array = g[0]
	var idx: PackedInt32Array = g[2]
	var centre := Vector3.ZERO
	for p in v:
		centre += p
	centre /= v.size()
	var out := 0.0
	for k in v.size():
		out += g[1][k].dot(v[k] - centre)
	if out < 0.0:
		for i in range(0, idx.size(), 3):
			var s := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = s
		g[2] = idx
		g[1] = _normals(v, idx)
