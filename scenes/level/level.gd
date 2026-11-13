# Ties the level's lights to the time of night, and blinks the bunker beacon.
# The spotlights on the walls face down the lanes; each lane's stay dark until
# the dead first start coming down it, then flicker on and stay on.
extends Node3D

const D = preload("res://scripts/defs.gd")
const Culvert = preload("res://scenes/level/culvert.gd")
const GroundFog = preload("res://scenes/level/ground_fog.gd")
const Grass = preload("res://scenes/level/grass.gd")
const BaseProps = preload("res://scenes/level/base_props.gd")
const Weather = preload("res://scenes/level/weather.gd")
const Guns = preload("res://scenes/actors/guns.gd")

var ground_fog: Node3D
var grass: Node3D
var weather: Node3D
var culverts: Array = []
var _yard_lights: Array = []     # the lamps in the yard (base_props.gd)


## Bricks up the pipes of lanes that never open on this level (open_at INF),
## lays the yard out as its base (bases.gd) and colours the country.
func set_level(open_at: Array, def := {}) -> void:
	apply_base(def.get("base", "outpost"))
	$Ground.set_lanes([open_at[0] != INF, open_at[1] != INF, open_at[2] != INF])
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
	_seen_frames = 0
	_apply_spots(0.0)
	apply_palette(def.get("palette", "green"))


# --- The base's yard and the country ----------------------------------------------
const Bases = preload("res://scripts/bases.gd")
## Each prop in bases.gd and the node(s) it moves here.
const PROP_NODES := {"bunker": "Bunker", "hut1": "Hut1", "hut2": "Hut2", "barrel1": "Barrel1", "barrel2": "Barrel2",
	"fire": "FireBarrel", "tent": "Tent", "generator": "Generator", "worklamp": "WorkLamp", "lamp1": "LampPost1",
	"lamp2": "LampPost2", "workshop": "WorkshopBench", "research": "ResearchDesk", "woodpile": "Woodpile"}
const CRATES := ["Crate1", "Crate2", "Crate3", "Crate4"]
var _home := {}          # node name -> its transform as built (the outpost's layout)
var base := ""


## Moves the yard's buildings and clutter to where they stand in base key.
func apply_base(key: String) -> void:
	if not Bases.BASES.has(key):
		key = "outpost"
	if _home.is_empty():
		for nm in PROP_NODES.values() + CRATES:
			var n := get_node_or_null(nm) as Node3D
			if n:
				_home[nm] = n.transform
	var prev_base := base
	base = key
	# The ground fog keeps clear of the buildings: lay it again round where
	# they stand now (not needed the first time, at the outpost it was made for).
	if ground_fog != null and key != prev_base and not (prev_base == "" and key == "outpost"):
		ground_fog.set_quality(ground_fog.quality)
	var props: Dictionary = Bases.BASES[key]["props"]
	var home_props: Dictionary = Bases.BASES["outpost"]["props"]
	for prop in PROP_NODES:
		_place(PROP_NODES[prop], props[prop], home_props[prop])
	# The base's own landmark(s): a water tower, a boxcar, watchtowers...
	var ex := get_node_or_null("BaseExtras")
	if ex == null:
		ex = Node3D.new()
		ex.name = "BaseExtras"
		add_child(ex)
	for c in ex.get_children():
		c.queue_free()
	for e in Bases.EXTRAS.get(key, []):
		var mi := MeshInstance3D.new()
		mi.mesh = BaseProps.extra(e[0])
		mi.material_override = Culvert._material()
		mi.position = Vector3(e[1], 0.0, e[2])
		mi.rotation.y = float(e[3])
		ex.add_child(mi)
	# The crates move as a stack, turned about its middle.
	var at: Array = props["crates"]
	var was: Array = home_props["crates"]
	var turn := Basis(Vector3.UP, float(at[2]))
	for nm in CRATES:
		var n := get_node_or_null(nm) as Node3D
		if n == null:
			continue
		var t: Transform3D = _home[nm]
		var off := turn * (t.origin - Vector3(was[0], t.origin.y, was[1]))
		n.transform = Transform3D(turn * t.basis, Vector3(at[0], t.origin.y, at[1]) + Vector3(off.x, 0.0, off.z))


func _place(nm: String, at: Array, was: Array) -> void:
	var n := get_node_or_null(nm) as Node3D
	if n == null or not _home.has(nm):
		return
	var t: Transform3D = _home[nm]
	n.transform = Transform3D(Basis(Vector3.UP, float(at[2])) * t.basis, Vector3(at[0], t.origin.y, at[1]))


## Colours the ground, grass and trees as the level's country (bases.gd
## PALETTES), and remembers its haze for the sky (main.gd).
var haze := Color.WHITE

func apply_palette(key: String) -> void:
	var g: Array = Bases.pull(key, "grass")
	var so: Array = Bases.pull(key, "soil")
	var gm = $Ground.get_surface_override_material(0)
	if gm is ShaderMaterial:
		gm.set_shader_parameter("grass_pull", Vector4(g[0].r, g[0].g, g[0].b, g[1]))
		gm.set_shader_parameter("soil_pull", Vector4(so[0].r, so[0].g, so[0].b, so[1]))
	var tu: Array = Bases.pull(key, "tufts")
	grass.set_pull(tu[0], tu[1])
	var tr: Array = Bases.pull(key, "trees")
	$Forest.set_pull(tr[0], tr[1])
	haze = Bases.PALETTES.get(key, {}).get("haze", Color.WHITE)
	weather.set_kind(Bases.PALETTES.get(key, {}).get("weather", ""))
	Culvert.set_snow(float(Bases.PALETTES.get(key, {}).get("snow", 0.0)))


# --- Spotlights -------------------------------------------------------------------
var _spots := [[], [], []]       # per lane: SpotLight3Ds
var _lenses: Array = []          # per lane: the glowing lens material
var _lit := [false, false, false]
var _on_t := [0.0, 0.0, 0.0]     # seconds since each lane's lights came on
var _night := 0.0
const SPOT_DAY := 3.0            # a floodlight's strength by day ...
const SPOT_NIGHT := 8.0          # ... and at night
const MAST_H := 2.95             # floodlight mast height above the walkway (light ~3.4 m up)
const SPOT_REACH := 10.0         # how far beyond the wall each one is aimed, metres
var _holders := [[], [], []]     # per side lane: the lamp posts (hidden where it's never used)


func _build_spotlights() -> void:
	for side in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.25, 0.22)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.93, 0.75)
		m.emission_energy_multiplier = 0.0
		_lenses.append(m)
	# Two floodlight masts on each walkway, each throwing its own pool down the
	# lane. They replace the front walkway's old lamp posts and the floodlight
	# that used to sit on the bunker.
	for l in lanterns.get_children():
		l.visible = false
	floodlight.visible = false
	for n in ["Mast", "Lamp"]:
		var b := get_node_or_null("Bunker/" + n)
		if b:
			b.visible = false
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.07
	post.height = MAST_H
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.15, 0.16)
	for side in 3:
		var L: Dictionary = D.LANES[side]
		var us: Array = D.PIPES[0] if side == 0 else [lerpf(L["u0"], L["u1"], 0.3), lerpf(L["u0"], L["u1"], 0.7)]
		for u in us:
			var p: Vector2 = Vector2(L["o"]) + L["t"] * u + L["n"] * (D.WALK_Y + 0.55)
			var holder := Node3D.new()
			holder.position = Vector3(p.x, D.DECK_H, p.y)
			add_child(holder)
			var pm := MeshInstance3D.new()
			pm.mesh = post
			pm.material_override = metal
			pm.position.y = MAST_H / 2.0
			holder.add_child(pm)
			if side > 0:
				_holders[side].append(holder)
			var aim: Vector2 = Vector2(L["o"]) + L["t"] * u + L["n"] * (D.WALL_Y - SPOT_REACH)
			_add_spot(side, holder, Vector3(0, MAST_H + 0.05, 0), Vector3(aim.x, 0.0, aim.y))


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
	# Like the bunker's floodlight: a wide, long, cool-white pool on the ground,
	# starting at the wall and running out down the lane.
	sp.light_color = Color(0.85, 0.92, 1.0)
	sp.spot_range = 34.0
	sp.spot_angle = 34.0
	sp.spot_attenuation = 0.4
	sp.light_energy = 0.0
	sp.position.z = -0.15
	pivot.add_child(sp)
	_spots[side].append(sp)



## Graphics: the floodlights cast shadows on High only.
func spot_detail(_full: bool) -> void:
	# Both lamps stay lit on every setting, without shadows: six shadowed
	# floodlights would each draw the whole scene again.
	for side in 3:
		for sp in _spots[side]:
			sp.shadow_enabled = false


## Shows or hides every spotlight beam (for the performance check).
func spots_enabled(on: bool) -> void:
	for side in 3:
		for sp in _spots[side]:
			sp.visible = on


## Called every frame with which lanes the dead are coming down: a lane's
## lights come on the first time, and stay on.
func update_lights(live: Array, dt: float) -> void:
	_seen_frames += 1
	for side in 3:
		if live[side] and not _lit[side]:
			_lit[side] = true
			# On already at the start of a run; a lane waking up later fades up.
			_on_t[side] = 0.0 if _seen_frames > 30 else 10.0
		if _lit[side]:
			_on_t[side] += dt
	_apply_spots(dt)


func _apply_spots(_dt: float) -> void:
	for side in 3:
		var b := 0.0
		if _lit[side]:
			# A smooth fade up (no flicker).
			b = smoothstep(0.0, 0.8, _on_t[side])
		for sp in _spots[side]:
			var full := lerpf(4.0, 12.0, _night) if sp == floodlight else lerpf(SPOT_DAY, SPOT_NIGHT, _night)
			sp.light_energy = full * b
		if side < _lenses.size():
			_lenses[side].emission_energy_multiplier = 3.0 * b


@onready var beacon: OmniLight3D = $Bunker/Beacon
@onready var beacon_bulb: MeshInstance3D = $Bunker/BeaconBulb
@onready var floodlight: SpotLight3D = $Bunker/Floodlight
@onready var lanterns: Node3D = $Lanterns

var _t := 0.0
var _seen_frames := 0   # frames of lights updates since the level was set up


func _ready() -> void:
	# Aim the floodlight down the lane at the tree line.
	floodlight.look_at(Vector3(11.5, 0.0, 7.0))
	_build_spotlights()
	# The base's buildings and clutter, in full detail.
	_yard_lights = BaseProps.dress(self)
	# Fog lying low on the ground, round the dead's shins.
	ground_fog = GroundFog.new()
	add_child(ground_fog)
	# Tufts of grass on the forest floor and along the lanes.
	grass = Grass.new()
	grass.name = "Grass"
	add_child(grass)
	# Snow or ash falling, on some levels.
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
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
