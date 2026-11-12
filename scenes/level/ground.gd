# The ground: a grid mesh shaped by scripts/terrain.gd (flat where the game is
# played, rolling hills beyond), tinted darker in hollows, lighter on tops and
# earthy on steep slopes. Built in code, and shown in the editor too.
@tool
extends MeshInstance3D

const Terrain = preload("res://scripts/terrain.gd")
const D = preload("res://scripts/defs.gd")

## The ground covers this square of the world (x, z), in metres.
@export var area := Rect2(-42, -42, 106, 106)
## Metres between grid points. Smaller is smoother but heavier.
@export var spacing := 0.7


func _ready() -> void:
	_build()


func _build() -> void:
	var nx := int(area.size.x / spacing) + 1
	var nz := int(area.size.y / spacing) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = Terrain.sample(area.position.x + i * spacing, area.position.y + j * spacing)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var origin := global_position if is_inside_tree() else Vector3.ZERO
	for j in nz:
		for i in nx:
			var x := area.position.x + i * spacing
			var z := area.position.y + j * spacing
			var h := heights[j * nx + i]
			# Slope from the neighbours, for the tint.
			var hx := heights[j * nx + mini(i + 1, nx - 1)] - heights[j * nx + maxi(i - 1, 0)]
			var hz := heights[mini(j + 1, nz - 1) * nx + i] - heights[maxi(j - 1, 0) * nx + i]
			var slope := clampf(Vector2(hx, hz).length() / (2.0 * spacing), 0.0, 1.0)
			var c := Color(0.72, 0.8, 0.72).lerp(Color(1.18, 1.12, 0.9), clampf(h / 4.5, 0.0, 1.0))
			if h < 0.0:
				c = c.lerp(Color(0.5, 0.6, 0.52), clampf(-h / 0.6, 0.0, 1.0))
			c = c.lerp(Color(1.0, 0.78, 0.58), smoothstep(0.3, 0.8, slope))
			st.set_color(c)
			st.set_uv(Vector2(x - area.position.x, z - area.position.y) / 90.0)
			st.add_vertex(Vector3(x, h, z) - Vector3(origin.x, 0, origin.z))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			for idx in [a, b, c, b, d, c]:
				st.add_index(idx)
	st.generate_normals()
	mesh = st.commit()
	# The grass material, tinted by the colours above.
	var m = get_surface_override_material(0)
	if m is StandardMaterial3D and not m.vertex_color_use_as_albedo:
		m = m.duplicate()
		m.vertex_color_use_as_albedo = true
		set_surface_override_material(0, m)
	_build_lanes()


## The dirt tracks the dead walk down, laid over the rolling ground. They
## replace the level's flat Lane board, whose material they borrow.
func _build_lanes() -> void:
	var board = get_parent().get_node_or_null("Lane") if is_inside_tree() else null
	if board == null:
		return
	board.visible = false
	for c in get_children():
		c.queue_free()
	var dirt: Material = board.get_surface_override_material(0)
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var u0: float = L["u0"]
		var u1: float = L["u1"]
		var v0: float = D.LANE_START - 0.5
		var v1: float = D.WALL_Y + 0.6
		var step := 0.5
		var nu := int((u1 - u0) / step) + 1
		var nv := int((v1 - v0) / step) + 1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in nv:
			for i in nu:
				var u := minf(u0 + i * step, u1)
				var v := minf(v0 + j * step, v1)
				var p: Vector2 = L["o"] + L["t"] * u + L["n"] * v
				st.set_uv(p / 14.0)
				st.add_vertex(Vector3(p.x, Terrain.sample(p.x, p.y) + 0.03, p.y) - Vector3(global_position.x, 0, global_position.z))
		for j in nv - 1:
			for i in nu - 1:
				var a := j * nu + i
				var b := a + 1
				var c := a + nu
				var d := c + 1
				# Wind the triangles so they face up whichever way the lane runs.
				var flip: bool = L["t"].x * L["n"].y - L["t"].y * L["n"].x < 0.0
				for idx in ([a, c, b, b, c, d] if flip else [a, b, c, b, d, c]):
					st.add_index(idx)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = dirt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
