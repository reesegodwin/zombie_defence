# The survivors' models: made in Blender (tools/blender builds them, from the
# people in tools/blender/people.py; art/survivors has the .blend files) and
# loaded here from assets/models/survivors.
#
# The actor script (survivor.gd) poses a body by turning plain joints: "hips"
# and "spine" on the node itself, and under them "hip_l/r", "knee_l/r",
# "neck", "head", "shoulder_l/r", "elbow_l/r", "hand_l/r" ("l" being the -x
# side). With every joint unturned the limbs hang straight down; turning a
# shoulder or hip by -PI/2 on x swings it forward (+z). A model's own skeleton
# rests differently (arms out, feet apart), so each frame this node works out
# where each bone must be for the joints as they are, and the skin follows.
extends Node

const DIR := "res://assets/models/survivors/"
## The models there are, by name (see tools/blender/people.py), each with the
## skin and hair colours it was painted in (the game tints it from those to
## each survivor's own).
const MODELS := ["drifter", "clerk", "rancher", "scavenger"]
const SKIN := {"drifter": Color(0.68, 0.51, 0.41), "clerk": Color(0.71, 0.55, 0.43), "rancher": Color(0.69, 0.51, 0.41), "scavenger": Color(0.74, 0.57, 0.48)}
const HAIR := {"drifter": Color(0.13, 0.10, 0.08), "clerk": Color(0.06, 0.055, 0.05), "rancher": Color(0.24, 0.19, 0.15), "scavenger": Color(0.40, 0.31, 0.21)}
## Which model wears each of body.gd's outfits (a man's; every woman is the
## scavenger). "" where there's none yet: those are still built in code.
const OUTFITS := {"scout": "drifter", "hooded": "drifter", "jacket": "rancher", "ranger": "rancher", "soldier": "clerk", "tank": "clerk", "trooper": ""}
## The game's joint -> the model's bone.
const BONES := {
	"hips": "pelvis", "spine": "spine_01", "neck": "neck_01", "head": "head",
	"shoulder_r": "upperarm_l", "elbow_r": "lowerarm_l", "hand_r": "hand_l", "hip_r": "thigh_l", "knee_r": "calf_l", "foot_r": "foot_l",
	"shoulder_l": "upperarm_r", "elbow_l": "lowerarm_r", "hand_l": "hand_r", "hip_l": "thigh_r", "knee_l": "calf_r", "foot_l": "foot_r",
}
## A limb joint -> the joint at its far end (its bone is straightened to hang down between them).
const LIMBS := {"hip": "knee", "knee": "foot", "shoulder": "elbow", "elbow": "hand"}
const FINGERS := ["index", "middle", "ring", "pinky"]

var skeleton: Skeleton3D
var body: Node3D              # the node the joints are on
var _joints: Array = []
var _bones: Array = []
var _keep: Array = []         # how each bone sits on its joint
var _from_body: Transform3D   # the body's space -> the skeleton's


## Puts a model on root and returns its joints (as body.gd does), with
## "meshes" (its MeshInstance3Ds), "rig" (this node, added to root), "leg"
## (hip joint to sole, metres) and "height".
## skin, hair, jacket: this survivor's own colours (null for the model's).
static func build(root: Node3D, model: String, skin = null, hair = null, jacket = null) -> Dictionary:
	var scene: Node3D = load(DIR + model + ".gltf").instantiate()
	root.add_child(scene)
	if hair == null:
		hair = HAIR[model]
	for m in scene.find_children("*", "MeshInstance3D", true, false):
		var tint = null
		if m.name == "Body" and skin != null:
			# From the skin it was painted with to theirs (worked out in linear light, as the shader multiplies).
			var a: Color = skin.srgb_to_linear()
			var b: Color = SKIN[model].srgb_to_linear()
			tint = Color(minf(a.r / b.r, 1.35), minf(a.g / b.g, 1.35), minf(a.b / b.b, 1.35)).linear_to_srgb()
		elif m.name in ["Hair", "Beard"]:
			tint = Color(minf(hair.r * 1.5, 1.0), minf(hair.g * 1.5, 1.0), minf(hair.b * 1.5, 1.0))   # the locks' texture is grey
		elif m.name in ["Jacket", "Shirt"] and jacket != null:
			tint = Color.WHITE.lerp(jacket.lightened(0.45), 0.55)     # a wash of their colour, to tell two alike apart
		if tint != null:
			var mat: BaseMaterial3D = m.get_active_material(0).duplicate()
			mat.albedo_color = tint
			m.set_surface_override_material(0, mat)
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var rig = new()
	rig.name = "Rig"
	rig.skeleton = sk
	rig.body = root
	var to_body := _relative(sk, root)
	rig._from_body = to_body.affine_inverse()
	var rest := {}      # where each joint's bone is at rest, in the body's space
	for jn in BONES:
		rest[jn] = to_body * sk.get_bone_global_rest(sk.find_bone(BONES[jn]))
	var j := {"meshes": scene.find_children("*", "MeshInstance3D", true, false), "rig": rig}
	var at := {}        # where each joint is with nothing turned
	j["hips"] = _joint(root, "Hips", rest["hips"].origin)
	j["spine"] = _joint(root, "Spine", rest["spine"].origin)
	at["hips"] = rest["hips"].origin
	at["spine"] = rest["spine"].origin
	for pair in [["neck", "spine"], ["head", "neck"]]:
		j[pair[0]] = _joint(j[pair[1]], pair[0].capitalize(), rest[pair[0]].origin - rest[pair[1]].origin)
		at[pair[0]] = rest[pair[0]].origin
	for s in ["l", "r"]:
		for chain in [["hips", "hip", "knee", "foot"], ["spine", "shoulder", "elbow", "hand"]]:
			var first: String = chain[1] + "_" + s
			j[first] = _joint(j[chain[0]], first.capitalize(), rest[first].origin - rest[chain[0]].origin)
			at[first] = rest[first].origin
			for k in [2, 3]:    # each further joint straight below the last, as far as its bone is long
				var above: String = chain[k - 1] + "_" + s
				var n: String = chain[k] + "_" + s
				var length: float = (rest[n].origin - rest[above].origin).length()
				j[n] = _joint(j[above], n.capitalize(), Vector3(0, -length, 0))
				at[n] = at[above] + Vector3(0, -length, 0)
	# How each bone sits on its joint: as it rests, but with the limbs turned to hang straight down.
	for jn in BONES:
		var basis: Basis = rest[jn].basis
		var part: String = jn.get_slice("_", 0)
		var s: String = jn.get_slice("_", 1)
		var limb: String = part if LIMBS.has(part) else ("elbow" if part == "hand" else "")
		if limb != "":
			var along: Vector3 = (rest[LIMBS[limb] + "_" + s].origin - rest[limb + "_" + s].origin).normalized()
			basis = Basis(Quaternion(along, Vector3.DOWN)) * basis
		rig._joints.append(j[jn])
		rig._bones.append(sk.find_bone(BONES[jn]))
		rig._keep.append(basis)
	# Parents before children, so each bone is placed on one already in place.
	var order := range(rig._bones.size())
	order.sort_custom(func(a, b): return rig._bones[a] < rig._bones[b])
	rig._joints = order.map(func(i): return rig._joints[i])
	rig._keep = order.map(func(i): return rig._keep[i])
	rig._bones = order.map(func(i): return rig._bones[i])
	j.erase("foot_l")
	j.erase("foot_r")
	j["leg"] = at["hip_l"].y
	j["height"] = (to_body * sk.get_bone_global_rest(sk.find_bone("head"))).origin.y + 0.2
	root.add_child(rig)
	rig._grip()
	return j


## The model for a survivor's look (survivor.gd's look_of): by their build and
## outfit. "" if there's none for it.
static func for_look(look: Dictionary) -> String:
	var outfit: String = OUTFITS.get(look.get("model", ""), "")
	if outfit == "":
		return ""
	return "scavenger" if look["build"] == "f" else outfit


static func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	return node


## A node's transform in the space of one above it.
static func _relative(node: Node3D, above: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != above:
		t = n.transform * t
		n = n.get_parent()
	return t


## Curls the fingers, to hold a gun (the models rest open handed).
func _grip() -> void:
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		var curl := 0.0
		for f in FINGERS:
			if n.begins_with(f):
				curl = 0.75 if n.contains("_01") else 0.95
		if n.begins_with("thumb"):
			curl = 0.35
		if curl > 0.0:
			var q := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(i, q * Quaternion(Vector3.RIGHT, curl))


func _process(_dt: float) -> void:
	for i in _bones.size():
		var t := _relative(_joints[i], body)
		skeleton.set_bone_global_pose(_bones[i], _from_body * Transform3D(t.basis * _keep[i], t.origin))
