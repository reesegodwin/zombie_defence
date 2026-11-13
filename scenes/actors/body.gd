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
# -PI/2 on x swings it forward (+z). A survivor's parts are merged into one
# mesh per joint. A zombie is one skin over the whole body, finely made, which
# bends with the joints (scenes/actors/skin_rig.gd), so there are no seams at
# the knees and elbows; the same few dozen bodies are shared by the horde and
# drawn in less detail when small on screen.
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
const STRIPE := 0.35     # cloth knitted in bands of its colour and a pale one
const GLOW := 0.15       # lit from within (eyes)
const PLAIN := 0.0

const BLOOD := Color(0.30, 0.05, 0.03)
const DIRT := Color(0.27, 0.20, 0.12)
const MOUTH := Color(0.3, 0.06, 0.05)
const TEETH := Color(0.86, 0.80, 0.62)
const DEAD_TEETH := Color(0.78, 0.76, 0.66)
const EYE_WHITE := Color(0.93, 0.91, 0.84)
const PUPIL := Color(0.05, 0.04, 0.04)
const NAIL := Color(0.52, 0.56, 0.62)

static var _geo := {}
static var _material: ShaderMaterial
static var _noise: FastNoiseLite
static var _skin: Color   # the skin of the body being built
static var _skin_kind := SKIN


## The zombies, each modelled on one of a pack of shambling dead: what it
## wears on top ("tee", "sweater": striped, long sleeved, "work": a buttoned
## work shirt with pockets, "open": a shirt hanging open over a vest, "vest",
## "none": bare chested, "flayed": the chest torn open to the ribs), on its
## legs ("long", "jeans": long, blue, out at the knees, "short": ragged
## cut-offs), on its feet ("boots", "bare", "odd": one boot left), its hair
## ("bald", "thin", "lank") and whether its eyes glow. "pants" and "boots"
## list the colours that model comes in (else any).
const ZOMBIE_MODELS := {
	"tee": {"top": "tee", "legs": "jeans", "feet": "boots", "hair": "thin",
		"pants": [Color("3f4a66"), Color("46506a"), Color("374257")], "boots": [Color("6e2f22"), Color("5a3524")]},
	"sweater": {"top": "sweater", "legs": "long", "feet": "boots", "hair": "thin",
		"pants": [Color("5a554c"), Color("4b4841"), Color("625a4e")], "boots": [Color("3a352c"), Color("4a3a2a")]},
	"shirtless": {"top": "none", "legs": "long", "feet": "odd", "hair": "bald",
		"pants": [Color("3f5536"), Color("4a5a3a"), Color("52503a")], "boots": [Color("5e3a26")]},
	"vest": {"top": "vest", "legs": "short", "feet": "bare", "hair": "bald"},
	"open_shirt": {"top": "open", "legs": "short", "feet": "bare", "hair": "lank"},
	"workshirt": {"top": "work", "legs": "long", "feet": "boots", "hair": "thin",
		"pants": [Color("2e3238"), Color("3a3833"), Color("33302c")], "boots": [Color("6a4630"), Color("3a2c22")]},
	"flayed": {"top": "flayed", "legs": "short", "feet": "bare", "hair": "lank", "glow": true},
}

const RAW := Color(0.50, 0.09, 0.07)       # torn, open flesh
const GORE := Color(0.46, 0.07, 0.05)      # blood on skin: fresher, redder than on cloth
const SORE := Color(0.40, 0.15, 0.12)
const BONE := Color(0.80, 0.74, 0.60)
const MILKY := Color(0.74, 0.75, 0.71)     # a dead eye
const SKULL := Vector3(0.078, 0.117, 0.1)   # the head, before the face is pressed into it
const HEAD_AT := Vector3(0, 0.125, -0.005)     # the middle of the head, from the head joint
const UNDERVEST := Color(0.60, 0.56, 0.48)
const DEAD_HAIR := [Color("6a5d50"), Color("7c6e60"), Color("8c857a"), Color("a8a297"), Color("5e554c")]

const Rig = preload("res://scenes/actors/skin_rig.gd")

static var _cache := {}     # zombie bodies already built: key -> [their mesh, its skin]
static var _rim: Color      # the dark round a dead eye
static var _width := 1.0    # how broad the body being built is
static var _thin_hair = null # the colour of what hair clings to the scalp being built, if any
static var _gore := 1.0     # how bloody this one's mouth and hands are


## look: skin, shirt, pants (Colors), eyes (Color: the glow, if they glow),
## width (1.0 normal, more for broad builds), rng (a RandomNumberGenerator
## for variety), and what it wears (see ZOMBIE_MODELS): top, legs, feet, hair,
## glow, boots (a Color). key: if given, bodies with the same key share their
## meshes (so they must be built from the same look and the same rng seed).
## Returns the joints: hips, spine, neck, head, shoulder_l/r, elbow_l/r,
## hand_l/r, hip_l/r, knee_l/r, and "meshes" (every MeshInstance3D made).
static func zombie(root: Node3D, look: Dictionary) -> Dictionary:
	var j := {"meshes": [], "_parts": {}}
	var w: float = look.get("width", 1.0)
	var rng: RandomNumberGenerator = look.get("rng", RandomNumberGenerator.new())
	var skin: Color = look["skin"]
	var shirt: Color = look["shirt"]
	var pants: Color = look["pants"]
	var top: String = look.get("top", "tee")
	var legs: String = look.get("legs", "short")
	var feet: String = look.get("feet", "bare")
	var hair: String = look.get("hair", "bald")
	var glow: bool = look.get("glow", false)
	var boots: Color = look.get("boots", Color("5a3524"))
	var dark_skin := skin.darkened(0.25)
	var hem := rng.randi() % 4   # which ragged edge pattern
	var limb := pow(w, 1.3)      # broad builds have thick arms and legs too
	_skin = skin.darkened(0.1)
	_skin_kind = SKIN
	_rim = Color(0.24, 0.09, 0.08).lerp(skin, 0.25)
	_gore = rng.randf_range(0.55, 1.0)
	_width = w
	var hc: Color = DEAD_HAIR[rng.randi() % DEAD_HAIR.size()]
	_thin_hair = hc if hair == "thin" else null

	# --- Lower body: pelvis, legs, and boots or bare feet --------------------
	var leg_paint := "jeans" if legs == "jeans" else "pants"
	var hips := _joint(root, "Hips", Vector3(0, HIP_H, 0))
	var spine := _joint(root, "Spine", Vector3(0, HIP_H + 0.04, 0))
	var bones := [hips, spine]
	j["hips"] = hips
	j["spine"] = spine
	_part(j, hips, "z_pelvis", pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "pants", null, [[spine, 0.0, 0.08]])
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var booted: bool = feet == "boots" or (feet == "odd" and side > 0)
		var hip := _joint(hips, "Hip" + s, Vector3(side * 0.076 * w, -0.04, 0))
		var knee := _joint(hip, "Knee" + s, Vector3(0, -0.43, 0))
		bones.append_array([hip, knee])
		var at_knee := [[knee, -0.37, -0.49]]
		var thick := Vector3(limb, 1, limb)
		if legs == "short":
			_part(j, hip, "z_shorts_leg%d" % ((hem + side + 2) % 4), pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, "pants", null, at_knee)
			_part(j, hip, "z_leg", skin, SKIN, Vector3.ZERO, thick, Vector3.ZERO, "skin", null, at_knee)
		else:
			_part(j, hip, "z_trouser_long%d" % ((hem + side + 2) % 4), pants, CLOTH, Vector3.ZERO, Vector3(w, 1, 1), Vector3.ZERO, leg_paint, null, at_knee)
			if not booted:
				_part(j, hip, "z_leg_low", skin, SKIN, Vector3.ZERO, thick, Vector3.ZERO, "skin", null, at_knee)
		if booted:
			_part(j, knee, "z_boot_top", boots, PLAIN, Vector3(0, -0.33, 0.0), Vector3.ONE, Vector3.ZERO, "boot")
			_part(j, knee, "z_boot", boots, PLAIN, Vector3(0, -0.437, 0.04), Vector3(1.25, 1.2, 1.05), Vector3.ZERO, "boot")
			_part(j, knee, "z_sole", boots.darkened(0.55), PLAIN, Vector3(0, -0.462, 0.04), Vector3.ONE)
		else:
			_part(j, knee, "z_foot", skin, SKIN, Vector3(0, -0.44, 0.045), Vector3.ONE, Vector3(0, side * -0.12, 0), "skin")
			for t in 5:
				var tx: float = -side * (0.024 - t * 0.012) + side * 0.004
				var big := t == 0
				_part(j, knee, "z_toe_big" if big else "z_toe", skin, SKIN,
					Vector3(tx + side * 0.01, -0.452, 0.135 - t * t * 0.0028 + (0.004 if big else 0.0)), Vector3.ONE,
					Vector3(PI / 2, side * -0.12 - side * t * 0.08, 0), "", NAIL)
		j["hip_" + s] = hip
		j["knee_" + s] = knee

	# --- Upper body: a gaunt chest, and whatever is left of its clothes ------
	var wide := Vector3(w, 1, 1)
	var sleeves := "none"
	var at_waist := [[hips, 0.07, -0.04]]   # below the waist it goes with the hips
	match top:
		"tee":
			_part(j, spine, "z_tee%d" % hem, shirt, CLOTH, Vector3.ZERO, wide, Vector3.ZERO, "shirt", null, at_waist)
			sleeves = "short"
		"sweater":
			_part(j, spine, "z_sweater", shirt, STRIPE, Vector3.ZERO, wide, Vector3.ZERO, "sweater", null, at_waist)
			_part(j, spine, "z_neckband", shirt.darkened(0.2), CLOTH, Vector3(0, 0.455, -0.006), wide)
			sleeves = "long"
		"work":
			var trim := shirt.darkened(0.22)
			_part(j, spine, "z_workshirt%d" % hem, shirt, CLOTH, Vector3.ZERO, wide, Vector3.ZERO, "shirt", null, at_waist)
			_part(j, spine, "z_collar", trim, CLOTH, Vector3(0, 0.455, -0.008), wide)
			_part(j, spine, "z_placket", trim, CLOTH, Vector3.ZERO, wide, Vector3.ZERO, "", null, at_waist)
			for k in 5:
				_part(j, spine, "z_button", Color(0.62, 0.6, 0.52), PLAIN, Vector3(0, 0.36 - k * 0.085, 0.109 + (0.004 if k == 1 else 0.0) - (0.004 if k == 4 else 0.0)), Vector3.ONE)
			for side in [-1, 1]:
				_part(j, spine, "z_pocket", shirt.darkened(0.08), CLOTH, Vector3(side * 0.078 * w, 0.29, 0.094), Vector3.ONE, Vector3(-0.04, side * 0.5, 0), "sweater")
				_part(j, spine, "z_pocket_flap", trim, CLOTH, Vector3(side * 0.078 * w, 0.322, 0.097), Vector3.ONE, Vector3(-0.04, side * 0.5, 0))
			sleeves = "long"
		"open":
			_part(j, spine, "z_tee%d" % hem, shirt, CLOTH, Vector3.ZERO, wide, Vector3.ZERO, "open", null, at_waist)
			_part(j, spine, "z_collar", shirt.darkened(0.15), CLOTH, Vector3(0, 0.455, -0.008), wide)
			sleeves = "short"
		"vest":
			_part(j, spine, "z_vest%d" % hem, shirt, CLOTH, Vector3.ZERO, wide, Vector3.ZERO, "sweater", Color(_skin, SKIN), at_waist)
		_:   # bare chested
			_part(j, spine, "z_torso", skin, SKIN, Vector3.ZERO, wide, Vector3.ZERO, "flayed" if top == "flayed" else "bare", null, at_waist)
	if top in ["tee", "sweater", "work", "open"]:
		_part(j, spine, "z_chest_top", skin, SKIN, Vector3.ZERO, wide, Vector3.ZERO, "bare")
	var neck := _joint(spine, "Neck", Vector3(0, 0.48, 0.0))
	var head := _joint(neck, "Head", Vector3(0, 0.06, 0.01))
	bones.append_array([neck, head])
	_part(j, spine, "z_neck", skin, SKIN, Vector3.ZERO, Vector3.ONE, Vector3.ZERO, "throat", null, [[head, 0.5, 0.57]])
	j["neck"] = neck
	j["head"] = head

	# --- The head: a skull with the skin drawn tight over it ----------------
	_part(j, head, "z_skull", skin, SKIN, HEAD_AT, Vector3.ONE, Vector3.ZERO, "face")
	for k in 8:   # top teeth, bared; then the bottom row
		var tx := (k - 3.5) * 0.0054
		if rng.randf() > 0.12:
			_part(j, head, "z_tooth", DEAD_TEETH.lerp(BLOOD, rng.randf() * 0.4), PLAIN, Vector3(tx, 0.0655, 0.0875 - tx * tx * 9.0), Vector3(1, rng.randf_range(0.85, 1.15), 1))
		if k > 0 and k < 7 and rng.randf() > 0.12:
			_part(j, head, "z_tooth", DEAD_TEETH.lerp(BLOOD, rng.randf() * 0.5), PLAIN, Vector3(tx * 0.9, 0.0525, 0.085 - tx * tx * 9.0), Vector3(0.9, rng.randf_range(0.8, 1.1), 1), Vector3(PI, 0, 0))
	for side in [-1, 1]:
		_part(j, head, "z_nostril", MOUTH.darkened(0.6), PLAIN, Vector3(side * 0.0062, 0.0845, 0.101), Vector3.ONE, Vector3(0.5, 0, 0))
		var eye := Vector3(side * 0.032, 0.13 + rng.randf_range(-0.0015, 0.0015), 0.0615)
		if glow:
			_part(j, head, "z_eyeball", look.get("eyes", Color(1.0, 0.8, 0.4)), GLOW, eye, Vector3.ONE)
		else:
			_part(j, head, "z_eyeball", MILKY, PLAIN, eye, Vector3.ONE)
			var look_at := Vector3(side * rng.randf_range(-0.003, 0.004), rng.randf_range(-0.003, 0.002), 0.0106)
			_part(j, head, "z_pupil", Color(0.52, 0.56, 0.55), PLAIN, eye + look_at, Vector3.ONE)
		_part(j, head, "z_lid", dark_skin.lerp(_rim, 0.5), SKIN, eye, Vector3.ONE, Vector3(-0.3 + rng.randf_range(-0.1, 0.25), 0, 0))
		_part(j, head, "z_ear", skin, SKIN, Vector3(side * 0.078, 0.118, -0.012), Vector3.ONE, Vector3(-0.12, side * -0.3, side * -0.1), "skin")
	if hair == "lank":
		_part(j, head, "z_hair", hc, CLOTH, HEAD_AT, Vector3.ONE)
		# Strands hanging round the sides and back (and, lank, across the face).
		var n := 18
		for k in n:
			var a := lerpf(1.2, TAU - 1.2, (k + rng.randf()) / n) if hair == "thin" else lerpf(0.5, TAU - 0.5, (k + rng.randf()) / n)
			var len := rng.randf_range(0.35, 0.7) if hair == "thin" else rng.randf_range(0.8, 1.5)
			var up := 0.15 if hair == "thin" else 0.17
			var at := Vector3(sin(a) * 0.075, up + rng.randf_range(-0.012, 0.012), -0.005 + cos(a) * (0.096 if cos(a) < 0.0 else 0.085))
			_part(j, head, "z_strand", hc.lightened(rng.randf() * 0.15), CLOTH, at, Vector3(1, len, 1), Vector3(rng.randf_range(-0.04, 0.04), a, rng.randf_range(-0.05, 0.05)))

	# --- Arms: bony and grasping, bare or sleeved ---------------------------
	var cloth_kind := STRIPE if top == "sweater" else CLOTH
	for side in [-1, 1]:
		var s := "l" if side < 0 else "r"
		var sh := _joint(spine, "Shoulder" + s, Vector3(side * 0.172 * w, 0.415, 0))
		var el := _joint(sh, "Elbow" + s, Vector3(0, -0.29, 0))
		var hand := _joint(el, "Hand" + s, Vector3(0, -0.27, 0))
		bones.append_array([sh, el, hand])
		var thick := Vector3(limb, 1, limb)
		var at_elbow := [[el, -0.24, -0.34]]
		match sleeves:
			"short":
				_part(j, sh, "z_sleeve%d" % ((hem + side + 4) % 4), shirt, CLOTH, Vector3.ZERO, thick, Vector3(0, 0, side * 0.12), "sweater")
			"long":
				_part(j, sh, "z_sleeve_long%d" % ((hem + side + 4) % 4), shirt, cloth_kind, Vector3.ZERO, thick, Vector3.ZERO, "sweater", null, at_elbow)
		_part(j, sh, "z_arm", skin, SKIN, Vector3.ZERO, Vector3(limb * side, 1, limb), Vector3.ZERO, "arm", null, at_elbow)
		_part(j, hand, "z_palm", skin, SKIN, Vector3(0, -0.04, 0), Vector3.ONE, Vector3.ZERO, "hand")
		for f in 4:
			var fz := 0.026 - f * 0.0165
			var lenk: float = [0.92, 1.0, 0.96, 0.78][f]
			_part(j, hand, "z_finger", skin, SKIN, Vector3(side * -0.002, -0.078 + absf(f - 1.5) * 0.004, fz), Vector3(1, lenk, 1),
				Vector3(-0.1 + f * 0.06, 0, side * (0.22 + f * 0.05)), "hand", NAIL)
		_part(j, hand, "z_finger", skin, SKIN, Vector3(side * -0.012, -0.025, 0.034), Vector3(1.15, 0.7, 1.15), Vector3(-0.75, 0, side * 0.3), "hand", NAIL)
		j["shoulder_" + s] = sh
		j["elbow_" + s] = el
		j["hand_" + s] = hand

	_skin_over(j, root, bones, rng, look.get("key", ""))
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
## tip: a colour for the far end of a finger or toe (its nail). blend (skinned
## bodies): [[joint, y0, y1], ...]: the part goes over from its own joint to
## that one between heights y0 and y1 (so it bends there instead of breaking).
static func _part(j: Dictionary, parent: Node3D, kind: String, col: Color, surface: float, pos: Vector3,
		scl: Vector3, rot := Vector3.ZERO, paint := "", tip = null, blend := []) -> void:
	if not j["_parts"].has(parent):
		j["_parts"][parent] = []
	var xf := Transform3D(Basis.from_euler(rot).scaled(scl), pos)
	j["_parts"][parent].append([kind, Color(col, surface), xf, paint, tip, blend])


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
					c = Color(col.lerp(part[4], tips[k]), part[4].a if tips[k] > 0.5 else col.a)
				if paint != "" and (part[4] == null or tips[k] <= 0.5):
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


## Whether the body with this key has been built (and so costs nothing to make again).
static func has_body(key: String) -> bool:
	return _cache.has(key)


## The whole body as one skin on a skeleton with a bone for each joint
## (bones, parents before children), under root. key: share the mesh with
## every other body built with this key.
static func _skin_over(j: Dictionary, root: Node3D, bones: Array, rng: RandomNumberGenerator, key: String) -> void:
	var rig: Skeleton3D = Rig.new()
	rig.name = "Skin"
	var at := {}   # where each joint is at rest, from root
	for i in bones.size():
		var joint: Node3D = bones[i]
		rig.add_bone(joint.name)
		var parent := bones.find(joint.get_parent())
		rig.set_bone_parent(i, parent)
		rig.set_bone_rest(i, Transform3D(Basis(), joint.position))
		at[joint] = joint.position + (at[bones[parent]] if parent >= 0 else Vector3.ZERO)
	rig.reset_bone_poses()
	rig.joints = bones
	root.add_child(rig)
	var mi := MeshInstance3D.new()
	mi.material_override = material()
	if key != "" and _cache.has(key):
		mi.mesh = _cache[key][0]
		mi.skin = _cache[key][1]
	else:
		if _noise == null:
			_noise = FastNoiseLite.new()
			_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			_noise.frequency = 7.0
		var seed_off := Vector3(rng.randf() * 100.0, rng.randf() * 100.0, rng.randf() * 100.0)
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var bone_of := PackedInt32Array()
		var weight_of := PackedFloat32Array()
		for joint in j["_parts"]:
			var here: Vector3 = at[joint]
			var bone := bones.find(joint)
			# Stains are laid out over the whole body at rest, so they carry
			# on across a knee or an elbow.
			var off: Vector3 = seed_off + here
			for part in j["_parts"][joint]:
				var g: Array = _geometry(part[0])
				var xf: Transform3D = part[2]
				var nb := xf.basis.inverse().transposed()
				var flip := xf.basis.determinant() < 0.0   # mirrored: turn its faces back out
				var base := verts.size()
				var col: Color = part[1]
				var paint: String = part[3]
				var tips: PackedFloat32Array = g[3]
				var blend: Array = part[5]
				for k in g[0].size():
					var v: Vector3 = xf * g[0][k]
					verts.append(v + here)
					norms.append((nb * g[1][k]).normalized())
					var c := col
					if part[4] != null and tips[k] > 0.0:
						c = Color(col.lerp(part[4], tips[k]), part[4].a if tips[k] > 0.5 else col.a)
					if paint != "" and (part[4] == null or tips[k] <= 0.5):
						c = _stain(c, v, paint, off, 1.0)
					cols.append(c)
					# Which bones it follows: its own, going over to others where it bends.
					var b := [bone, 0, 0, 0]
					var wt := [1.0, 0.0, 0.0, 0.0]
					for n in blend.size():
						var t := smoothstep(blend[n][1], blend[n][2], v.y)
						for m in n + 1:
							wt[m] *= 1.0 - t
						b[n + 1] = bones.find(blend[n][0])
						wt[n + 1] = t
					bone_of.append_array(b)
					weight_of.append_array(wt)
				var tri: PackedInt32Array = g[2]
				for i in range(0, tri.size(), 3):
					idx.append(base + tri[i])
					idx.append(base + tri[i + (2 if flip else 1)])
					idx.append(base + tri[i + (1 if flip else 2)])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		arr[Mesh.ARRAY_BONES] = bone_of
		arr[Mesh.ARRAY_WEIGHTS] = weight_of
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
		im.generate_lods(25.0, 60.0, [])
		mi.mesh = im.get_mesh()
		mi.skin = rig.create_skin_from_rest_transforms()
		if key != "":
			_cache[key] = [mi.mesh, mi.skin]
	rig.add_child(mi)
	mi.skeleton = NodePath("..")
	j["meshes"].append(mi)
	j.erase("_parts")


## How far a rib stands out at a point on a bare chest (0..1).
static func _rib(v: Vector3) -> float:
	var band := smoothstep(0.06, 0.1, v.y) * smoothstep(0.34, 0.29, v.y)
	var front := smoothstep(-0.05, 0.01, v.z) * smoothstep(0.01, 0.035, absf(v.x))
	var ridge := 0.5 + 0.5 * cos(TAU * (v.y + absf(v.x) * 0.3) / 0.043)
	return band * front * ridge * ridge


## Blood, grime and the odd rip showing skin, painted onto the clothes.
static func _stain(c: Color, v: Vector3, paint: String, off: Vector3, dirt: float) -> Color:
	var p := v + off
	var n := _noise.get_noise_3dv(p)
	var n2 := _noise.get_noise_3dv(p * 2.3 + Vector3(17, 3, 9))
	var out := c
	match paint:
		"face":   # dark round the eyes, hollow cheeks, blood round the mouth and down the chin
			var eye := Vector2(absf(v.x) - 0.032, v.y - 0.13).length()
			out = out.lerp(_rim, smoothstep(0.032, 0.012, eye) * smoothstep(0.02, 0.05, v.z) * 0.85)
			var cheek := Vector2(absf(v.x) - 0.045, (v.y - 0.067) * 0.7).length()
			out = out.lerp(c.darkened(0.45), smoothstep(0.03, 0.0, cheek) * smoothstep(0.0, 0.03, v.z) * 0.55)
			var mouth := Vector2(v.x * 0.8, (v.y - 0.059) * (1.0 if v.y > 0.059 else 0.55)).length()
			var b := smoothstep(0.046, 0.016, mouth + n2 * 0.02) * smoothstep(0.0, 0.04, v.z) * smoothstep(0.083, 0.07, v.y + n * 0.012) * 1.1 * _gore
			out = out.lerp(GORE, clampf(b, 0.0, 0.93))
			# Inside the mouth, and the lips' torn edge.
			var gape := Vector2(v.x / 0.0225, (v.y - 0.059) / 0.0105).length()
			out = out.lerp(Color(0.07, 0.015, 0.012), smoothstep(1.15, 0.8, gape) * smoothstep(0.03, 0.05, v.z))
			out = out.lerp(SORE, smoothstep(0.45, 0.62, n) * 0.45)
			if _thin_hair != null:   # thin hair clinging on round the sides and back, gone on top
				var r := v - HEAD_AT
				var band := smoothstep(-0.062, -0.045, r.y) * smoothstep(0.085 - maxf(0.0, r.z) * 1.3, 0.06 - maxf(0.0, r.z) * 1.3, r.y) * smoothstep(0.045, 0.02, r.z)
				out = out.lerp(_thin_hair.darkened(0.35), band * clampf(0.75 + n2 * 0.9, 0.0, 0.92))
			return Color(out, c.a)
		"throat":   # what ran down from the mouth
			var b := smoothstep(0.0, 0.03, v.z) * smoothstep(0.035, 0.0, absf(v.x)) * smoothstep(0.42, 0.5, v.y) * (0.5 + n2) * _gore
			return Color(out.lerp(GORE, clampf(b, 0.0, 0.85)), c.a)
		"skin":
			return Color(out.lerp(SORE, smoothstep(0.36, 0.56, n) * 0.6).lerp(DIRT, smoothstep(0.2, 0.6, n2) * 0.3), c.a)
		"arm":   # bloody to the elbows
			var b := smoothstep(-0.36, -0.55, v.y) * (0.55 + n2 * 1.3) * _gore
			return Color(out.lerp(SORE, smoothstep(0.36, 0.56, n) * 0.6).lerp(GORE, clampf(b, 0.0, 0.9)), c.a)
		"hand":
			return Color(out.lerp(GORE, clampf((0.55 + n2 * 1.2) * _gore, 0.0, 0.9)), c.a)
		"boot":
			return Color(out.lerp(DIRT, clampf(0.25 + n2 * 0.6, 0.0, 0.7)).lerp(BLOOD, smoothstep(0.3, 0.6, n) * 0.6), c.a)
		"bare", "flayed":
			out = out.lerp(SORE, smoothstep(0.34, 0.54, n) * 0.65)
			out = out.lerp(c.darkened(0.3), smoothstep(0.3, 0.9, 1.0 - _rib(v)) * smoothstep(0.06, 0.1, v.y) * smoothstep(0.34, 0.29, v.y) * smoothstep(-0.05, 0.01, v.z) * 0.35)
			var drip := smoothstep(0.075, 0.015, absf(v.x) + n2 * 0.03) * smoothstep(0.16, 0.44, v.y) * smoothstep(0.0, 0.03, v.z) * _gore
			out = out.lerp(GORE, clampf(drip * (0.8 + n2), 0.0, 0.9))
			if paint == "flayed":
				var raw := smoothstep(-0.25, 0.0, n + n2 * 0.4 + 0.1) * smoothstep(-0.01, 0.03, v.z) * smoothstep(0.42, 0.35, v.y) * smoothstep(-0.03, 0.03, v.y)
				out = out.lerp(RAW.lerp(BLOOD, clampf(0.5 + n2 * 2.0, 0.0, 1.0) * 0.6), raw).lerp(BONE, raw * _rib(v) * 0.75)
			return Color(out, c.a)
		"open":   # hanging open over a stained vest
			if v.z > 0.0 and absf(atan2(v.x, v.z)) < 0.27:
				out = Color(UNDERVEST, CLOTH)
				c = out
		"jeans":   # worn through at the knees
			var knee := smoothstep(0.11, 0.0, absf(v.y + 0.43))
			if v.z > 0.02 and knee * (0.5 + n * 1.6 + n2 * 0.8) > 0.62:
				return Color(_skin.lerp(SORE, 0.35), _skin_kind)
			out = Color(out.lightened(0.18 * knee * smoothstep(0.0, 0.03, v.z)), c.a)   # faded where it's worn
			paint = "pants"
	if dirt > 0.5:
		# The dead: filthy all over, darker where it has soaked in, with blood
		# in great patches (down the front most of all) and a few spatters.
		var where := _noise.get_noise_3dv(p * 0.3 + Vector3(40, 0, 0))
		var where2 := _noise.get_noise_3dv(p * 0.45 + Vector3(0, 70, 0))
		var filth := 0.22 + 0.3 * smoothstep(-0.3, 0.4, where2) + 0.1 * n2
		if paint == "shirt" or paint == "sweater":
			filth += smoothstep(0.2, -0.1, v.y) * 0.15
		out = Color(out.lerp(DIRT, clampf(filth, 0.0, 0.75)), c.a)
		var soak := smoothstep(0.12, 0.5, where + (0.22 if paint != "pants" and v.z > 0.0 and v.y > 0.15 else 0.0))
		var spots := smoothstep(0.38, 0.6, n) * 0.5
		var b := soak * (0.4 + 0.3 * n2) + spots * (0.25 + 0.75 * soak)
		if paint == "pants":
			b *= 0.6
		return Color(out.lerp(BLOOD, clampf(b, 0.0, 0.9)), c.a)
	# Grime collects lower down.
	var grime := smoothstep(0.1, 0.6, n2) * 0.6 * dirt
	out = Color(out.lerp(DIRT, grime), c.a)
	var blood := smoothstep(0.2, 0.55, n) * dirt * dirt
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
		"cranium":
			g = _ellipsoid(Vector3(0.108, 0.13, 0.125), 14, 9, func(p: Vector3) -> Vector3:
				# Narrower at the temples, bulging at the back.
				var q := p
				q.x *= 1.0 - 0.12 * clampf(-p.y / 0.13, 0.0, 1.0) - 0.06 * clampf(p.z / 0.125, 0.0, 1.0)
				q.z *= 1.0 + 0.08 * clampf(-p.z / 0.125, 0.0, 1.0)
				return q)
		"pupil":
			g = _ellipsoid(Vector3(0.0085, 0.0085, 0.004), 8, 4)
		"palm":
			g = _ellipsoid(Vector3(0.013, 0.045, 0.033), 8, 5)
		# --- The dead (finely made: they're seen close, and in numbers) ---
		"z_pelvis":
			g = _loft(_fine([[0.1, 0.12, 0.08, 0.0], [0.05, 0.132, 0.088, 0.0], [0.0, 0.142, 0.095, 0.0], [-0.07, 0.148, 0.097, 0.0], [-0.12, 0.135, 0.09, 0.0], [-0.17, 0.07, 0.06, 0.0]], 4), 28)
		"z_leg", "z_leg_low":
			# A wasted leg, hip to ankle: the knee's bones standing out, a
			# stringy calf, the shin's edge down the front.
			var rings := [[0.04, 0.06, 0.07, 0.0], [-0.04, 0.07, 0.08, 0.0], [-0.14, 0.066, 0.076, 0.004], [-0.26, 0.055, 0.063, 0.006], [-0.36, 0.046, 0.051, 0.006], [-0.43, 0.046, 0.05, 0.01],
				[-0.48, 0.04, 0.046, 0.002], [-0.56, 0.042, 0.053, -0.012], [-0.66, 0.035, 0.042, -0.008], [-0.78, 0.026, 0.03, -0.002], [-0.845, 0.024, 0.029, 0.0], [-0.875, 0.027, 0.034, 0.004]]
			if base == "z_leg_low":
				rings = rings.slice(7)
			g = _loft(_fine(rings, 4), 20)
			_bend(g, func(p: Vector3) -> Vector3:
				var a := atan2(p.x, p.z)
				var out := Vector3(sin(a), 0, cos(a))
				var front := smoothstep(0.6, 1.0, cos(a))
				var d := 0.007 * smoothstep(0.045, 0.0, absf(p.y + 0.435)) * front                       # the kneecap
				d -= 0.004 * smoothstep(0.03, 0.0, absf(p.y + 0.475)) * front                            # the dip under it
				d += 0.003 * smoothstep(-0.47, -0.52, p.y) * smoothstep(-0.86, -0.8, p.y) * smoothstep(0.9, 1.0, cos(a))   # the shin bone
				d += 0.005 * smoothstep(0.03, 0.0, absf(p.y + 0.85)) * smoothstep(0.6, 1.0, absf(sin(a)))                  # the ankle bones
				d -= 0.004 * smoothstep(-0.7, -0.82, p.y) * smoothstep(0.5, 0.0, absf(absf(a) - 2.3))    # hollows either side of the heel cord
				return p + out * d)
		"z_trouser_long", "z_shorts_leg":
			# Loose on the leg, bagged at the knee, bunched at the ankle.
			var rings := [[0.045, 0.07, 0.078, 0.0], [-0.04, 0.08, 0.088, 0.0], [-0.15, 0.076, 0.084, 0.004], [-0.28, 0.067, 0.073, 0.006], [-0.43, 0.061, 0.065, 0.008],
				[-0.56, 0.059, 0.065, -0.004], [-0.7, 0.055, 0.059, -0.002], [-0.82, 0.057, 0.061, 0.002]]
			if base == "z_shorts_leg":
				rings = [rings[0], rings[1], [-0.15, 0.078, 0.086, 0.004], [-0.28, 0.073, 0.079, 0.006], [-0.36, 0.074, 0.08, 0.006]]
			g = _loft(_fine(rings, 5), 20, true, false, 0.04, variant)
			_bend(g, func(p: Vector3) -> Vector3:
				var a := atan2(p.x, p.z)
				var k := 0.004 * sin(p.y * 70.0 + sin(a * 2.0) * 2.5) * (smoothstep(0.12, 0.0, absf(p.y + 0.43)) + smoothstep(-0.62, -0.8, p.y))
				k += 0.003 * sin(a * 5.0 + p.y * 9.0) * smoothstep(0.0, -0.2, p.y)
				return p + Vector3(sin(a), 0, cos(a)) * k)
		"z_foot":
			g = _ellipsoid(Vector3(0.042, 0.024, 0.1), 20, 12, func(p: Vector3) -> Vector3:
				# Flat sole, high instep at the back, toes splay wider at the front.
				var q := p
				q.y = maxf(q.y, -0.012)
				q.y += 0.012 * smoothstep(0.03, -0.06, p.z) * smoothstep(-0.005, 0.02, p.y)
				q.x *= 1.0 + clampf(p.z / 0.1, 0.0, 1.0) * 0.25 - 0.2 * smoothstep(0.0, -0.1, p.z)
				return q)
		"z_toe", "z_toe_big":
			var r := 0.013 if base == "z_toe_big" else 0.008
			var l := 0.034 if base == "z_toe_big" else 0.024
			g = _loft(_fine([[0.0, r, r, 0.0], [-l * 0.6, r, r * 0.95, 0.0], [-l, r * 0.85, r * 0.8, 0.0]], 2), 6, true, true, 0.0, 0, 0.55)
		"z_boot_top":
			g = _loft(_fine([[0.0, 0.056, 0.06, 0.0], [-0.05, 0.05, 0.055, 0.0], [-0.11, 0.046, 0.052, 0.002]], 4), 18, true, false)
		"z_boot":
			g = _ellipsoid(Vector3(0.042, 0.024, 0.1), 20, 12, func(p: Vector3) -> Vector3:
				var q := p
				q.y = maxf(q.y, -0.012)
				q.y += 0.014 * smoothstep(0.045, -0.03, p.z) * smoothstep(-0.005, 0.02, p.y)
				q.y += 0.004 * smoothstep(0.05, 0.09, p.z) * smoothstep(0.0, 0.02, p.y)   # a hard toe cap
				q.x *= 1.0 + clampf(p.z / 0.1, 0.0, 1.0) * 0.15
				return q)
		"z_sole":
			g = _ellipsoid(Vector3(0.054, 0.008, 0.115), 20, 4)
		"z_tee", "z_workshirt", "z_sweater":
			# Hem to collar: baggy on a thin frame, a little hunched at the top.
			var rings := _fine([[0.487, 0.07, 0.058, -0.013], [0.47, 0.115, 0.08, -0.015], [0.44, 0.165, 0.098, -0.01], [0.41, 0.17, 0.102, -0.007], [0.38, 0.172, 0.105, -0.004],
				[0.3, 0.165, 0.108, 0.0], [0.18, 0.152, 0.104, 0.004], [0.06, 0.15, 0.1, 0.0], [-0.06, 0.155, 0.104, 0.0], [-0.11, 0.158, 0.106, 0.0]], 4)
			if base == "z_sweater":   # gathered in at a ribbed hem
				rings.append_array([[-0.125, 0.15, 0.1, 0.0], [-0.15, 0.146, 0.098, 0.0]])
			g = _loft(rings, 48, false, false, [0.045, 0.02, 0.0][["z_tee", "z_workshirt", "z_sweater"].find(base)], variant)
			if base != "z_sweater":   # the neck sags open at the front
				_bend(g, func(p: Vector3) -> Vector3:
					return p - Vector3(0, 0.03 * smoothstep(0.455, 0.487, p.y) * smoothstep(0.0, 0.05, p.z), 0))
			# Folds: the cloth hangs in loose vertical creases below the chest.
			_bend(g, func(p: Vector3) -> Vector3:
				var a := atan2(p.x, p.z)
				var k := smoothstep(0.36, 0.1, p.y) * (0.006 * sin(a * 9.0 + p.y * 14.0) + 0.004 * sin(a * 17.0 + 2.0))
				return p + Vector3(sin(a), 0, cos(a)) * k)
		"z_vest", "z_torso":
			# A wasted body: narrow shoulders, the ribcage, a sunken belly.
			var rings := _fine([[0.5, 0.05, 0.048, -0.012], [0.475, 0.075, 0.058, -0.012], [0.455, 0.118, 0.07, -0.012], [0.435, 0.156, 0.082, -0.01], [0.4, 0.172, 0.09, -0.006], [0.34, 0.165, 0.1, 0.0],
				[0.26, 0.152, 0.102, 0.004], [0.18, 0.136, 0.09, 0.004], [0.1, 0.12, 0.078, 0.0], [0.02, 0.118, 0.078, 0.0], [-0.05, 0.128, 0.084, 0.0]], 6)
			if base == "z_vest":
				for r in rings:
					r[1] *= 1.045
					r[2] *= 1.07
				rings.append_array([[-0.07, 0.136, 0.09, 0.0], [-0.09, 0.14, 0.094, 0.0]])
				g = _loft(rings, 48, true, false, 0.035, variant)
				# Scooped low at the neck, cut away round the arms: there (the
				# "tip" of the shape) the skin shows.
				var cut: PackedFloat32Array = g[3]
				for k in cut.size():
					var y: float = g[0][k].y
					var a := absf(wrapf(TAU * (k % 48) / 48.0, -PI, PI))   # 0 at the front, PI at the back
					var front := a < PI / 2
					var mid := a if front else PI - a
					var neck := y > (0.375 if front else 0.425) + 0.09 * pow(mid / 0.62, 3.0)
					var arm := y > 0.36 + 0.11 * pow(absf(a - PI / 2) / 0.62, 3.0)
					cut[k] = 1.0 if (k >= cut.size() - 1 or y > 0.478 or (neck and mid < 0.62) or (arm and absf(a - PI / 2) < 0.62)) else 0.0
				g[3] = cut
			else:
				g = _loft(rings, 48)
			var ribs := 0.007 if base == "z_torso" else 0.003
			_bend(g, func(p: Vector3) -> Vector3:
				var out := Vector3(p.x, 0, p.z).normalized()
				var ax := absf(p.x)
				var front := smoothstep(0.0, 0.03, p.z)
				var back := smoothstep(0.0, -0.03, p.z)
				var q := p + out * (_rib(p) - 0.45) * ribs * smoothstep(0.06, 0.1, p.y) * smoothstep(0.34, 0.29, p.y)
				# The breastbone's furrow, and the spine's, knobbed.
				q.z -= 0.006 * smoothstep(0.02, 0.0, ax) * smoothstep(0.1, 0.2, p.y) * smoothstep(0.42, 0.34, p.y) * front
				q.z += (0.007 - 0.004 * absf(sin(p.y * 75.0))) * smoothstep(0.022, 0.0, ax) * smoothstep(0.0, 0.08, p.y) * smoothstep(0.46, 0.4, p.y) * back
				# Collarbones, out to the shoulders, and the hollows over them.
				var cb := p.y - (0.418 + ax * 0.08)
				q.z += 0.008 * smoothstep(0.011, 0.0, absf(cb)) * smoothstep(0.012, 0.03, ax) * smoothstep(0.16, 0.13, ax) * front
				q.z -= 0.006 * smoothstep(0.03, 0.0, absf(cb - 0.022)) * smoothstep(0.03, 0.06, ax) * smoothstep(0.14, 0.1, ax) * front
				# A slack, wasted chest over the ribs; shoulder blades behind.
				q.z += 0.006 * smoothstep(0.06, 0.0, Vector2(ax - 0.075, (p.y - 0.33) * 1.2).length()) * front
				q.z -= 0.008 * smoothstep(0.07, 0.0, Vector2((ax - 0.085) * 0.9, (p.y - 0.33) * 0.7).length()) * back
				# The belly fallen in under the ribs, the hip bones standing out below.
				q.z -= 0.012 * smoothstep(0.09, 0.0, Vector2(ax * 0.9, p.y - 0.1).length()) * front
				q += out * 0.006 * smoothstep(0.04, 0.0, Vector2(ax - 0.1, p.y - 0.0).length()) * front
				return q)
		"z_chest_top":   # what shows at an open neck
			g = _loft(_fine([[0.5, 0.05, 0.048, -0.012], [0.475, 0.075, 0.058, -0.012], [0.455, 0.112, 0.068, -0.012], [0.43, 0.14, 0.078, -0.01], [0.41, 0.14, 0.08, -0.008]], 3), 24, true, false)
		"z_neck":
			# From between the shoulders up into the skull: the cords standing
			# out from behind the ears to the breastbone, the windpipe between.
			g = _loft(_fine([[0.63, 0.04, 0.047, 0.014], [0.57, 0.04, 0.046, 0.01], [0.51, 0.043, 0.047, 0.002], [0.47, 0.054, 0.052, -0.004], [0.44, 0.08, 0.06, -0.01], [0.42, 0.1, 0.064, -0.01]], 5), 24)
			_bend(g, func(p: Vector3) -> Vector3:
				var a := atan2(p.x, p.z)
				var up := clampf((p.y - 0.45) / 0.14, 0.0, 1.0)
				var d := 0.006 * smoothstep(0.3, 0.0, absf(absf(a) - lerpf(0.3, 1.3, up))) * smoothstep(0.42, 0.47, p.y)   # the cords
				d += 0.004 * smoothstep(0.03, 0.0, absf(p.y - 0.535)) * smoothstep(0.35, 0.0, absf(a))                     # the Adam's apple
				d -= 0.004 * smoothstep(0.3, 0.0, absf(a)) * smoothstep(0.05, 0.0, absf(p.y - 0.475))                      # the hollow of the throat
				return p + Vector3(sin(a), 0, cos(a)) * d)
		"z_neckband":
			g = _loft(_fine([[0.062, 0.062, 0.054, -0.01], [0.04, 0.066, 0.06, -0.008], [0.01, 0.085, 0.072, -0.004]], 3), 24, false, false)
		"z_collar":
			g = _loft(_fine([[0.06, 0.066, 0.058, -0.01], [0.02, 0.09, 0.078, -0.004], [-0.02, 0.112, 0.092, 0.0]], 3), 24, false, false)
			_bend(g, func(p: Vector3) -> Vector3:   # open at the throat, its points lying forward
				var front := smoothstep(0.03, 0.07, p.z) * smoothstep(0.03, 0.0, absf(p.x))
				return p + Vector3(0, -0.035 * front, 0.0))
		"z_placket":
			g = _loft(_fine([[0.4, 0.011, 0.003, 0.103], [0.3, 0.011, 0.003, 0.11], [0.18, 0.011, 0.003, 0.11], [0.06, 0.011, 0.003, 0.102], [-0.06, 0.011, 0.003, 0.106], [-0.1, 0.011, 0.003, 0.108]], 3), 6)
		"z_button":
			g = _ellipsoid(Vector3(0.006, 0.006, 0.003), 8, 4)
		"z_pocket":
			g = _ellipsoid(Vector3(0.034, 0.036, 0.007), 12, 8, func(p: Vector3) -> Vector3:
				# Squared off: a patch pocket.
				return Vector3(signf(p.x) * minf(absf(p.x) * 1.5, 0.032), signf(p.y) * minf(absf(p.y) * 1.5, 0.034), p.z))
		"z_pocket_flap":
			g = _ellipsoid(Vector3(0.036, 0.013, 0.008), 12, 6, func(p: Vector3) -> Vector3:
				return Vector3(signf(p.x) * minf(absf(p.x) * 1.5, 0.034), p.y - (0.006 - absf(p.x) * 0.18) * (1.0 if p.y < 0.0 else 0.0), p.z))
		"z_skull":
			g = _ellipsoid(SKULL, 64, 46, _skull)
		"z_hair":
			# A shell just off the scalp, cut along a ragged hairline.
			g = _ellipsoid(SKULL, 40, 28, func(p: Vector3) -> Vector3:
				var f := clampf(p.z / SKULL.z * 0.5 + 0.5, 0.0, 1.0)   # 0 at the back, 1 at the front
				var ragged := 0.006 * sin(atan2(p.x, p.z) * 11.0) + 0.004 * sin(atan2(p.x, p.z) * 23.0)
				var keep := p.y > lerpf(-0.05, 0.072, f * f) - absf(p.x) * 0.2 * f + ragged
				return _skull(p) * (1.035 if keep else 0.96))
		"z_strand":
			g = _loft(_fine([[0.0, 0.0045, 0.002, 0.0], [-0.04, 0.005, 0.002, 0.004], [-0.09, 0.004, 0.002, 0.002], [-0.13, 0.0015, 0.001, 0.004]], 2), 4)
		"z_tooth":
			g = _ellipsoid(Vector3(0.0029, 0.0062, 0.0026), 6, 4, func(p: Vector3) -> Vector3:
				return Vector3(p.x * (1.0 + clampf(p.y / 0.0062, -1.0, 0.0) * -0.25), maxf(p.y, -0.0035), p.z))
		"z_nostril":
			g = _ellipsoid(Vector3(0.0036, 0.0022, 0.004), 8, 4)
		"z_eyeball":
			g = _ellipsoid(Vector3(0.0115, 0.0115, 0.0115), 18, 12)
		"z_pupil":
			g = _ellipsoid(Vector3(0.0042, 0.0042, 0.0016), 10, 4)
		"z_lid":
			# A heavy upper lid, half closed over the eye.
			g = _ellipsoid(Vector3(0.0128, 0.0128, 0.0128), 18, 12, func(p: Vector3) -> Vector3:
				return Vector3(p.x, maxf(p.y, 0.003), p.z))
		"z_ear":
			g = _ellipsoid(Vector3(0.006, 0.031, 0.018), 16, 12, func(p: Vector3) -> Vector3:
				var q := p
				q.z *= 1.0 - 0.45 * clampf(-p.y / 0.031, 0.0, 1.0)   # down to the lobe
				var r := Vector2(p.y / 0.031, p.z / 0.018).length()
				q.x += (0.005 * smoothstep(0.75, 0.3, r) - 0.002 * smoothstep(0.2, 0.0, absf(r - 0.85))) * -signf(p.x)   # hollowed inside a rolled rim
				return q)
		"z_sleeve":
			g = _loft(_fine([[0.042, 0.014, 0.02, 0.0], [0.032, 0.036, 0.04, 0.0], [0.008, 0.052, 0.053, 0.0], [-0.03, 0.056, 0.055, 0.0], [-0.09, 0.054, 0.053, 0.0], [-0.14, 0.056, 0.054, 0.0]], 4), 20, true, false, 0.025, variant)
		"z_sleeve_long":
			g = _loft(_fine([[0.042, 0.014, 0.02, 0.0], [0.032, 0.036, 0.04, 0.0], [0.008, 0.053, 0.054, 0.0], [-0.03, 0.057, 0.057, 0.0], [-0.15, 0.05, 0.052, 0.0], [-0.29, 0.046, 0.048, -0.002],
				[-0.42, 0.04, 0.043, 0.0], [-0.5, 0.036, 0.039, 0.0], [-0.525, 0.037, 0.04, 0.0]], 4), 16, true, false, 0.03, variant)
			_bend(g, func(p: Vector3) -> Vector3:   # rucked up at the elbow
				var a := atan2(p.x, p.z)
				var k := 0.004 * sin(p.y * 80.0 + sin(a * 2.0) * 2.0) * smoothstep(0.1, 0.0, absf(p.y + 0.3)) + 0.002 * sin(a * 4.0 + p.y * 12.0)
				return p + Vector3(sin(a), 0, cos(a)) * k)
		"z_arm":
			# Shoulder to wrist (the right arm; mirrored for the left): the
			# cap of the shoulder, a thin upper arm, the elbow's point, cords
			# down the forearm to the wrist bones.
			g = _loft(_fine([[0.034, 0.016, 0.024, 0.0], [0.024, 0.036, 0.042, 0.0], [0.0, 0.046, 0.052, 0.0], [-0.06, 0.046, 0.051, 0.0], [-0.13, 0.039, 0.045, 0.004], [-0.21, 0.034, 0.039, 0.002],
				[-0.27, 0.032, 0.035, -0.002], [-0.295, 0.034, 0.036, -0.004], [-0.34, 0.035, 0.039, 0.0], [-0.41, 0.031, 0.035, 0.0], [-0.49, 0.024, 0.028, 0.0], [-0.545, 0.02, 0.025, 0.0], [-0.575, 0.019, 0.025, 0.0]], 3), 16)
			_bend(g, func(p: Vector3) -> Vector3:
				var a := atan2(p.x, p.z)
				var out := Vector3(sin(a), 0, cos(a))
				var d := 0.006 * smoothstep(0.035, 0.0, absf(p.y + 0.295)) * smoothstep(0.5, 1.0, -cos(a))                 # the point of the elbow
				d -= 0.004 * smoothstep(0.07, 0.0, absf(p.y + 0.08)) * smoothstep(0.6, 0.0, absf(a - PI / 2))              # under the shoulder's cap, outside
				d += 0.0025 * smoothstep(-0.36, -0.42, p.y) * smoothstep(-0.57, -0.5, p.y) * maxf(0.0, cos(a * 4.0))       # cords and bones of the forearm
				d += 0.004 * smoothstep(0.02, 0.0, absf(p.y + 0.55)) * smoothstep(0.5, 1.0, absf(cos(a)))                  # the wrist bones
				return p + out * d)
		"z_palm":
			g = _ellipsoid(Vector3(0.016, 0.045, 0.035), 14, 9)
		"z_finger":
			# Three bones, knuckled, ending in a long nail.
			g = _loft(_fine([[0.0, 0.0078, 0.0078, 0.0], [-0.012, 0.0064, 0.0066, 0.0], [-0.028, 0.0074, 0.0074, 0.0], [-0.04, 0.006, 0.0062, 0.001],
				[-0.054, 0.0066, 0.0066, 0.002], [-0.066, 0.0052, 0.0054, 0.004], [-0.078, 0.0036, 0.004, 0.007]], 1), 6, true, true, 0.0, 0, 0.22)
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
				if seg > 16:   # finely made: tears a few points wide, not a sawtooth
					var a2 := TAU * k / seg
					h = absf(sin(a2 * 2.5 + variant * 1.7)) * (0.55 + 0.45 * sin(a2 * 7.0 + variant * 2.3)) + (0.25 if k % 3 == 0 else 0.0)
				y -= ragged * (h * h) - ragged * 0.3
				if i > 0:
					y = minf(y, rings[i - 1][0] - 0.002)
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


## The shape of a dead head, pressed into an egg (p: a point on the egg;
## points bunch up towards the face, where the detail is): a heavy brow over
## deep sockets, the bridge and tip of a nose, sharp cheekbones over hollow
## cheeks, lips drawn back off an open mouth, a jaw and a chin.
static func _skull(p: Vector3) -> Vector3:
	var h := Vector2(p.x / SKULL.x, p.z / SKULL.z)
	var a := atan2(h.x, h.y)
	a -= 0.45 * sin(a)
	var q := Vector3(SKULL.x * h.length() * sin(a), p.y, SKULL.z * h.length() * cos(a))
	var e := q   # on the egg
	var y := q.y
	var ax := absf(q.x)
	var low := clampf(-y / SKULL.y, 0.0, 1.0)
	# The jaw keeps its width down to its angle, then turns in to the chin.
	q.x *= 1.0 + 0.2 * smoothstep(0.3, 0.72, low) - 0.12 * smoothstep(0.78, 1.0, low) - 0.05 * clampf(e.z / SKULL.z, 0.0, 1.0)
	q.y = maxf(q.y, -SKULL.y * 0.97)
	q.y -= 0.014 * smoothstep(0.03, SKULL.y, y)   # not so high a crown
	if e.z < 0.0:   # the back of the head rounds out, then tucks in to the neck
		q.z *= 1.0 + 0.05 * (1.0 - low) - 0.55 * low * low
		return q
	var face := smoothstep(0.0, 0.045, e.z)
	var dz := 0.036 * smoothstep(0.22, 0.95, low)                                              # an egg falls away below: bring the jaw forward
	dz -= 0.004 * smoothstep(0.05, 0.11, y)                                                    # the forehead slopes back
	dz += 0.0055 * smoothstep(0.016, 0.0, absf(y - 0.026 + ax * 0.08)) * smoothstep(0.072, 0.05, ax)   # the brow
	dz -= 0.0012 * (0.5 + 0.5 * cos(TAU * y / 0.013)) * smoothstep(0.036, 0.045, y) * smoothstep(0.09, 0.08, y) * smoothstep(0.055, 0.04, ax)   # its furrows
	dz -= 0.017 * smoothstep(1.0, 0.35, Vector2((ax - 0.032) / 0.023, (y - 0.005) / 0.0155).length())   # eye sockets
	dz += 0.002 * smoothstep(0.012, 0.0, Vector2(ax - 0.032, (y + 0.014) * 1.5).length())               # bags under them
	dz += 0.0055 * smoothstep(0.024, 0.0, Vector2((ax - 0.052) * 0.8, y + 0.014).length())              # cheekbones
	dz -= 0.01 * smoothstep(0.036, 0.0, Vector2(ax - 0.045, (y + 0.058) * 0.7).length())                # hollow cheeks
	dz -= 0.004 * smoothstep(0.03, 0.0, Vector2(ax - 0.066, (y - 0.035) * 0.6).length())                # temples
	# The nose: a thin bridge from between the eyes, widening to the tip and the wings.
	var t := clampf((0.014 - y) / 0.052, 0.0, 1.0)
	var wide := lerpf(0.0055, 0.0115, t * t)
	var nose := lerpf(0.004, 0.023, pow(t, 1.25)) * smoothstep(wide * 1.9, wide * 0.45, ax)
	nose *= smoothstep(-0.05, -0.039, y) * smoothstep(0.03, 0.012, y)
	nose += 0.007 * smoothstep(0.0075, 0.002, Vector2(ax - 0.0105, (y + 0.035) * 0.9).length())         # the wings of the nostrils
	dz += nose
	# The mouth: lips over the teeth, a groove down from each side of the nose, the mouth hanging open.
	dz += 0.0055 * smoothstep(0.034, 0.012, ax) * smoothstep(0.026, 0.008, absf(y + 0.064))
	dz -= 0.0025 * smoothstep(0.0045, 0.0, absf(ax - lerpf(0.014, 0.03, clampf((-0.036 - y) / 0.04, 0.0, 1.0)))) * smoothstep(-0.03, -0.04, y) * smoothstep(-0.085, -0.07, y)
	dz -= 0.015 * smoothstep(1.0, 0.8, Vector2(ax / 0.0225, (y + 0.066) / 0.0105).length())
	dz += 0.005 * smoothstep(0.022, 0.0, Vector2(ax, y + 0.101).length())                               # the chin
	dz -= 0.003 * smoothstep(0.008, 0.0, absf(y + 0.086)) * smoothstep(0.02, 0.008, ax)                 # the dip over it
	q.z += dz * face
	return q


## A finer set of rings through the same shape (sub steps between each two),
## rounded off so the tube bends smoothly instead of in facets.
static func _fine(rings: Array, sub: int) -> Array:
	var out := []
	var n := rings.size()
	for i in n - 1:
		var p0: Array = rings[maxi(i - 1, 0)]
		var p1: Array = rings[i]
		var p2: Array = rings[i + 1]
		var p3: Array = rings[mini(i + 2, n - 1)]
		for s in sub:
			var t := float(s) / sub
			var r := [lerpf(p1[0], p2[0], t)]
			for c in range(1, 4):
				var v: float = 0.5 * ((2.0 * p1[c]) + (-p0[c] + p2[c]) * t + (2.0 * p0[c] - 5.0 * p1[c] + 4.0 * p2[c] - p3[c]) * t * t
					+ (-p0[c] + 3.0 * p1[c] - 3.0 * p2[c] + p3[c]) * t * t * t)
				# Never bulge past the rings either side.
				r.append(clampf(v, minf(p1[c], p2[c]) - absf(p1[c] - p2[c]) * 0.1, maxf(p1[c], p2[c]) + absf(p1[c] - p2[c]) * 0.1))
			out.append(r)
	out.append(rings[n - 1].duplicate())
	return out


## Moves every point of a shape through deform(p), and works out its normals again.
static func _bend(g: Array, deform: Callable) -> void:
	var v: PackedVector3Array = g[0]
	for k in v.size():
		v[k] = deform.call(v[k])
	g[0] = v
	g[1] = _normals(v, g[2])


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
