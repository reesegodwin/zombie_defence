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
