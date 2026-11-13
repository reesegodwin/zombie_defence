# Models made in Blender (tools/blender/*.py writes them to assets/models/).
# Each .glb is read down to one plain mesh (positions, normals and colours per
# vertex) like the ones the props and guns build in code, so it takes the same
# materials, snow and lighting. When a model isn't there, mesh() returns null
# and the caller builds its code version as before.
extends RefCounted

static var _cache := {}


## The model's mesh, or null if there's no assets/models/<model_name>.glb.
static func mesh(model_name: String) -> ArrayMesh:
	if _cache.has(model_name):
		return _cache[model_name]
	var m: ArrayMesh = null
	var path := "res://assets/models/%s.glb" % model_name
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		if scene != null:
			var root := scene.instantiate()
			m = _flatten(root)
			root.free()
	_cache[model_name] = m
	return m


# Every mesh under the node, in the node's space, as one surface.
static func _flatten(root: Node) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform if node != root else xf
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var sc = arr[Mesh.ARRAY_COLOR]
				var idx = arr[Mesh.ARRAY_INDEX]
				var order: PackedInt32Array = idx if idx != null else PackedInt32Array(range(sv.size()))
				for i in order:
					v.append(xf * sv[i])
					n.append((xf.basis * sn[i]).normalized())
					c.append(sc[i] if sc != null else Color.WHITE)
		for ch in node.get_children():
			stack.append([ch, xf])
	if v.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m


static var _skinned := {}


## A skinned model's raw arrays: "vertex", "normal", "color", "index", and per
## vertex four "bones" (by name, from "names") with their "weights"; or {} if
## there's no assets/models/<model_name>.glb.
static func skinned(model_name: String) -> Dictionary:
	if _skinned.has(model_name):
		return _skinned[model_name]
	var out := {}
	var path := "res://assets/models/%s.glb" % model_name
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var root := scene.instantiate() if scene != null else null
		var mi: MeshInstance3D = _find_mesh(root) if root != null else null
		if mi != null and mi.mesh != null and mi.skin != null:
			var arr := mi.mesh.surface_get_arrays(0)
			var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			var names := PackedStringArray()
			for i in mi.skin.get_bind_count():
				var nm := String(mi.skin.get_bind_name(i))
				if nm == "" and skel != null:
					nm = skel.get_bone_name(mi.skin.get_bind_bone(i))
				names.append(nm)
			out = {
				"vertex": arr[Mesh.ARRAY_VERTEX], "normal": arr[Mesh.ARRAY_NORMAL],
				"color": arr[Mesh.ARRAY_COLOR], "index": arr[Mesh.ARRAY_INDEX],
				"bones": arr[Mesh.ARRAY_BONES], "weights": arr[Mesh.ARRAY_WEIGHTS], "names": names,
			}
		if root != null:
			root.free()
	_skinned[model_name] = out
	return out


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
