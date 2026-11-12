# The ground: a grid mesh shaped by scripts/terrain.gd (flat where the game is
# played, rolling hills beyond), tinted darker in hollows, lighter on tops and
# earthy on steep slopes. Built in code, and shown in the editor too.
@tool
extends MeshInstance3D

const Terrain = preload("res://scripts/terrain.gd")
const D = preload("res://scripts/defs.gd")

## The ground covers this square of the world (x, z), in metres.
@export var area := Rect2(-98, -98, 236, 221)
## Metres between grid points. Smaller is smoother but heavier.
@export var spacing := 0.9


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
			# How much of each dirt patch is here (the shader roughens the edge):
			# UV2.x the front lane, UV2.y a side lane, alpha the yard.
			var w := _dirt_weights(Vector2(x, z))
			c.a = w.z
			st.set_color(c)
			st.set_uv2(Vector2(w.x, w.y))
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
	# Grass, with the lanes' and the yard's dirt painted in (ground.gdshader).
	var grass_tex: Texture2D = null
	var dirt_tex: Texture2D = null
	var gm = get_surface_override_material(0)
	if gm is StandardMaterial3D:
		grass_tex = gm.albedo_texture
	var board = get_parent().get_node_or_null("Lane") if is_inside_tree() else null
	if board:
		board.visible = false
		var dm = board.get_surface_override_material(0)
		if dm is StandardMaterial3D:
			dirt_tex = dm.albedo_texture
	var yard = get_parent().get_node_or_null("Yard") if is_inside_tree() else null
	if yard:
		yard.visible = false
	for c in get_children():
		c.queue_free()   # the old dirt strips
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("grass_tex", grass_tex)
	m.set_shader_parameter("dirt_tex", dirt_tex)
	set_surface_override_material(0, m)
	_mat = m


const SHADER := preload("res://assets/shaders/ground.gdshader")
const EDGE := 1.1   # metres the dirt fades into the grass over


## (front lane, side lane, yard) dirt amounts at p, 0..1, soft at the edges.
static func _dirt_weights(p: Vector2) -> Vector3:
	var w := Vector3.ZERO
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - Vector2(L["o"])
		var u: float = d.dot(L["t"])
		var v: float = d.dot(L["n"])
		var out := maxf(maxf(L["u0"] - u, u - L["u1"]), maxf((D.PIPE_V + 0.4) - v, v - (D.WALL_Y + 0.6)))
		var k := 1.0 - smoothstep(-EDGE, EDGE, out)
		if side == 0:
			w.x = maxf(w.x, k)
		else:
			w.y = maxf(w.y, k)
	var oy := maxf(maxf(D.BASE_X0 - 0.3 - p.x, p.x - (D.BASE_X1 + 0.3)), maxf((D.WALL_Y + 0.2) - p.y, p.y - D.BASE_Y1))
	w.z = 1.0 - smoothstep(-EDGE, EDGE, oy)
	return w
var _mat: ShaderMaterial


## Lanes that are never used on this level are forest floor, not dirt.
func set_lanes(on: Array) -> void:
	if _mat:
		for k in 3:
			_mat.set_shader_parameter(["front_on", "west_on", "east_on"][k], 1.0 if on[k] else 0.0)
