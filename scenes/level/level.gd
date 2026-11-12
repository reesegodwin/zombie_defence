# Ties the level's lights to the time of night, and blinks the bunker beacon.
# The spotlights on the walls face down the lanes; each lane's stay dark until
# the dead first start coming down it, then flicker on and stay on.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Culvert = preload("res://scenes/level/culvert.gd")
const GroundFog = preload("res://scenes/level/ground_fog.gd")
const BaseProps = preload("res://scenes/level/base_props.gd")
const Guns = preload("res://scenes/actors/guns.gd")

var ground_fog: Node3D
var culverts: Array = []
var _yard_lights: Array = []     # the lamps in the yard (base_props.gd)


## Bricks up the pipes of lanes that never open on this level (open_at INF).
func set_level(open_at: Array) -> void:
	# A lane that's never used here: no sewer at its end, just woods.
	for side in culverts.size():
		var unused: bool = open_at[side] == INF
		culverts[side].visible = not unused
		if side > 0:
			$Forest.set_wooded(side, unused)
	# No lamps on a wall whose lane never brings the dead.
	for side in [1, 2]:
		for h in _holders[side]:
			h.visible = open_at[side] != INF
	for side in _lit.size():   # a new base: every spotlight dark again
		_lit[side] = false
		_on_t[side] = 0.0
	_apply_spots(0.0)


# --- Spotlights -------------------------------------------------------------------
var _spots := [[], [], []]       # per lane: SpotLight3Ds
var _lenses: Array = []          # per lane: the glowing lens material
var _lit := [false, false, false]
var _on_t := [0.0, 0.0, 0.0]     # seconds since each lane's lights came on
var _night := 0.0
var _holders := [[], [], []]     # per side lane: the lamp posts (hidden where it's never used)
var _beams := [[], [], []]       # per lane: the visible beams' materials
const BEAM := preload("res://assets/shaders/light_beam.gdshader")


func _build_spotlights() -> void:
	for side in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.25, 0.22)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.93, 0.75)
		m.emission_energy_multiplier = 0.0
		_lenses.append(m)
	# The front walkway's lamp posts become spotlights over the front lane.
	for l in lanterns.get_children():
		l.get_node("Light").visible = false
		l.get_node("Bulb").visible = false
		_add_spot(0, l, Vector3(0, 1.42, 0), Vector3(l.position.x, 0.0, D.WALL_Y - 7.0))
	# And spotlights on posts along the west and east walkways.
	var post := CylinderMesh.new()
	post.top_radius = 0.04
	post.bottom_radius = 0.05
	post.height = 1.4
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.15, 0.16)
	for side in [1, 2]:
		var L: Dictionary = D.LANES[side]
		for f in [0.2, 0.5, 0.8]:
			var u: float = lerpf(L["u0"], L["u1"], f)
			var p: Vector2 = Vector2(L["o"]) + L["t"] * u + L["n"] * (D.WALK_Y + 0.55)
			var holder := Node3D.new()
			holder.position = Vector3(p.x, D.DECK_H, p.y)
			add_child(holder)
			var pm := MeshInstance3D.new()
			pm.mesh = post
			pm.material_override = metal
			pm.position.y = 0.7
			holder.add_child(pm)
			_holders[side].append(holder)
			var aim: Vector2 = Vector2(L["o"]) + L["t"] * u + L["n"] * (D.WALL_Y - 7.0)
			_add_spot(side, holder, Vector3(0, 1.42, 0), Vector3(aim.x, 0.0, aim.y))
	# The bunker's floodlight lights the front lane too.
	_spots[0].append(floodlight)


## A lamp housing and its beam on parent at pos, aimed at target (world).
func _add_spot(side: int, parent: Node3D, pos: Vector3, target: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	pivot.look_at(target, Vector3.UP)
	var k := Guns.Kit.new()
	k.cyl(Vector3(0, 0, 0.05), 0.13, 0.26, Color(0.18, 0.19, 0.18), 10)        # can
	k.cyl(Vector3(0, 0, -0.1), 0.15, 0.05, Color(0.1, 0.1, 0.1), 10)           # rim
	k.box(Vector3(0, -0.14, 0.05), Vector3(0.05, 0.12, 0.05), Color(0.15, 0.15, 0.15))   # yoke
	var can := MeshInstance3D.new()
	can.mesh = k.mesh()
	can.material_override = Guns.material()
	pivot.add_child(can)
	var lens := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.12
	disc.height = 0.02
	lens.mesh = disc
	lens.rotation.x = PI / 2
	lens.position.z = -0.13
	lens.material_override = _lenses[side]
	pivot.add_child(lens)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.93, 0.78)
	sp.spot_range = 17.0
	sp.spot_angle = 22.0
	sp.spot_attenuation = 0.7
	sp.light_energy = 0.0
	sp.position.z = -0.15
	pivot.add_child(sp)
	_spots[side].append(sp)
	# The light you can see coming out of it: a long, soft cone.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 1.9
	cone.height = 8.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var bm := ShaderMaterial.new()
	bm.shader = BEAM
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.rotation.x = PI / 2       # the cone's +y (narrow end) back toward the lamp, the wide end out along -z
	beam.position.z = -4.1
	sp.add_child(beam)             # hidden with the light (Low graphics)
	_beams[side].append(bm)


## Low graphics: just the bunker floodlight and the middle lamp on each walkway
## light up; the rest of the lamps stay dark (their beams cost the most).
func spot_detail(full: bool) -> void:
	for side in 3:
		var list: Array = _spots[side].filter(func(sp): return sp != floodlight)
		for k in list.size():
			list[k].visible = full or k == list.size() / 2


## Shows or hides every spotlight beam (for the performance check).
func spots_enabled(on: bool) -> void:
	for side in 3:
		for sp in _spots[side]:
			sp.visible = on


## Called every frame with which lanes the dead are coming down: a lane's
## lights come on the first time, and stay on.
func update_lights(live: Array, dt: float) -> void:
	for side in 3:
		if live[side] and not _lit[side]:
			_lit[side] = true
			_on_t[side] = 0.0
		if _lit[side]:
			_on_t[side] += dt
	_apply_spots(dt)


func _apply_spots(_dt: float) -> void:
	for side in 3:
		var b := 0.0
		if _lit[side]:
			# A stuttering start, as if the generator's catching.
			var t: float = _on_t[side]
			b = 1.0 if t > 1.1 else (1.0 if fmod(t * 7.3, 1.0) > 0.45 else 0.15)
		for sp in _spots[side]:
			var full := lerpf(4.0, 12.0, _night) if sp == floodlight else lerpf(2.5, 7.0, _night)
			sp.light_energy = full * b
		if side < _lenses.size():
			_lenses[side].emission_energy_multiplier = 3.0 * b
		for bm in _beams[side]:
			bm.set_shader_parameter("strength", b * lerpf(0.35, 1.0, _night))

@onready var beacon: OmniLight3D = $Bunker/Beacon
@onready var beacon_bulb: MeshInstance3D = $Bunker/BeaconBulb
@onready var floodlight: SpotLight3D = $Bunker/Floodlight
@onready var lanterns: Node3D = $Lanterns

var _t := 0.0


func _ready() -> void:
	# Aim the floodlight down the lane at the tree line.
	floodlight.look_at(Vector3(11.5, 0.0, 7.0))
	_build_spotlights()
	# The base's buildings and clutter, in full detail.
	_yard_lights = BaseProps.dress(self)
	# Fog lying low on the ground, round the dead's shins.
	ground_fog = GroundFog.new()
	add_child(ground_fog)
	# The sewer pipes at the far end of every lane.
	for side in D.LANES.size():
		var c := Culvert.new()
		add_child(c)
		c.build(side)
		culverts.append(c)


## darkness: 0 (dusk) .. 1 (deep night)
func set_darkness(k: float, dt: float) -> void:
	_t += dt
	ground_fog.set_night(k)
	var on := fmod(_t, 1.6) < 0.18
	beacon.light_energy = 3.0 if on else 0.0
	beacon_bulb.visible = on
	_night = k
	for l in _yard_lights:
		l.light_energy = lerpf(0.5, 3.2, k) * (0.96 + 0.04 * sin(_t * 7.0 + l.position.x))
