# The skeleton inside a skinned body (scenes/actors/body.gd, the zombies).
# The actor scripts pose a body by turning its joints, plain Node3Ds; every
# frame this copies them onto the bones, one for one, and the skin follows.
extends Skeleton3D

var joints: Array = []   # the joint for each bone, in bone order


func _process(_dt: float) -> void:
	for i in joints.size():
		var n: Node3D = joints[i]
		set_bone_pose_position(i, n.position)
		set_bone_pose_rotation(i, n.quaternion)
