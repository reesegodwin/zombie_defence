# Static game data: map layout, zombie types, weapons, items.
# Loaded with preload() so it works without the editor's class cache.
extends RefCounted

# --- Map --------------------------------------------------------------------
#   y = 0 ......... the dead enter here (far edge, top right of the screen)
#   y = WALL_Y .... the wall, spanning the lane from X0 to X1
#   y = WALK_Y .... the walkway the survivors stand on
#   y > WALK_Y .... the base (bottom left of the screen)
const N := 22
const X0 := 4
const X1 := 18
const WALL_Y := 14.0
const WALL_T := 0.6
const WALK_Y := 15.2

const MAX_CREW := 5
const WIRE_MAX := 24.0
const STORAGE_MAX := 24
const HORDE_EVERY := 75.0
const FIRST_HORDE := 150.0
const START_SCRAP := 80

# --- Scavenging, strangers, food -------------------------------------------
const WALK_SPEED := 1.5                 # tiles per second, walking to and from the pass
# The route from the back of the base up through the mountain pass (x, y).
const PASS_PATH := [Vector2(11.2, 17.2), Vector2(11.2, 23.0), Vector2(11.7, 26.5), Vector2(12.5, 30.0), Vector2(12.6, 34.0), Vector2(12.1, 38.0)]
const SCRAP_TIERS := [[12, 24], [24, 42], [45, 80]]   # low, medium, high: min and max scrap
const SCRAP_NAMES := ["Low", "Medium", "High"]
const FIRST_STRANGER_AT := 30.0        # seconds into a run when the first survivor walks in
const STRANGER_EVERY_WHEN_ALONE := 25.0 # after that, only once you've lost everyone: average wait
const START_FOOD := 6.0
const FOOD_PER_MINUTE := 0.5            # eaten by each survivor (you included), all the time
const FOOD_BAR_MIN := 20.0              # the food bar's scale: this much, or more if you hold more
const HUNGRY_SLOWDOWN := 1.25           # hungry crews take this much longer between shots

# --- Repairing the wall -----------------------------------------------------
# Click a survivor on the walkway to set them repairing; they stop shooting.
const REPAIR_PER_SECOND := 12.0         # wall restored per second, per repairer
const WALL_PER_SCRAP := 10.0            # wall restored for each scrap spent

# --- Skills -----------------------------------------------------------------
# Every survivor turns up with one to three random skills, each at level 1, 2
# or 3. "fx" holds the effect at each level (index 0 = level 1):
#   repair   multiplies how fast they repair the wall
#   thrift   multiplies how much wall each scrap buys when they repair
#   aim      multiplies their damage; their spread shrinks to (2 - fx) of normal
#   quick    multiplies the time between their shots (lower is faster)
#   scrounge multiplies the scrap they bring back and their odds of lucky finds
#   fleet    multiplies how long their scavenging trips take (lower is faster)
#   careful  multiplies their chance of dying on a scavenging trip
# "player": false means you never roll it (you can't leave the wall).
const SKILLS := {
	"repair": {"name": "Handy", "fx": [1.25, 1.5, 1.85], "fmt": "Repairs the wall %s faster", "player": true},
	"thrift": {"name": "Thrifty", "fx": [1.25, 1.5, 1.85], "fmt": "Gets %s more wall out of each scrap when repairing", "player": true},
	"aim": {"name": "Sharpshooter", "fx": [1.1, 1.2, 1.32], "fmt": "Aims better: %s more damage and a tighter spread", "player": true},
	"quick": {"name": "Quick hands", "fx": [0.92, 0.85, 0.77], "fmt": "Shoots %s faster", "player": true},
	"scrounge": {"name": "Scrounger", "fx": [1.2, 1.4, 1.65], "fmt": "Brings back %s more scrap and finds more on trips", "player": false},
	"fleet": {"name": "Fleet-footed", "fx": [0.88, 0.76, 0.64], "fmt": "Scavenging trips take %s less time", "player": false},
	"careful": {"name": "Careful", "fx": [0.6, 0.35, 0.15], "fmt": "%s less likely to die out scavenging", "player": false},
}
const SKILL_COUNT_ODDS := [0.5, 0.4, 0.1]   # chance of having 1, 2 or 3 skills
const SKILL_LEVEL_ODDS := [0.55, 0.32, 0.13] # chance of a skill being level 1, 2 or 3
const LEVEL_MARKS := ["I", "II", "III"]

# Chance of a scavenger never coming back: SCAVENGE_DEATH for a trip that is
# SCAVENGE_DEATH_REF seconds long, scaled by the site's trip length.
const SCAVENGE_DEATH := 0.05
const SCAVENGE_DEATH_REF := 90.0

# --- Workshop: what scrap buys ---------------------------------------------
# Items go to base storage. Shelving, wall and drill take effect at once and
# get dearer each time.
const SHOP := {
	"smg": {"cost": 35, "name": "SMG"},
	"shotgun": {"cost": 45, "name": "Shotgun"},
	"rifle": {"cost": 70, "name": "Hunting rifle"},
	"launcher": {"cost": 110, "name": "Grenade launcher"},
	"hollow": {"cost": 30, "name": "Hollow points"},
	"trigger": {"cost": 30, "name": "Hair trigger"},
	"molotov": {"cost": 40, "name": "Molotov crate"},
	"wire": {"cost": 25, "name": "Wire coil"},
	"spikes": {"cost": 15, "name": "Spike strip"},
	"beartrap": {"cost": 20, "name": "Bear trap"},
	"mine": {"cost": 15, "name": "Landmine"},
	"slick": {"cost": 15, "name": "Fuel slick"},
	"shelves": {"cost": 30, "name": "Shelving", "desc": "Base storage holds 4 more items."},
	"reinforce": {"cost": 60, "name": "Reinforce the wall", "desc": "The wall gets 30% tougher, fully built: timber, then stone, then steel."},
	"drill": {"cost": 50, "name": "Drill the crew", "desc": "Everyone else on the wall does 30% more damage and fires 12% faster."},
}
const SHOP_SECTIONS := [
	["Guns", ["smg", "shotgun", "rifle", "launcher"]],
	["Gear", ["hollow", "trigger", "molotov"]],
	["Traps", ["spikes", "beartrap", "mine", "slick"]],
	["Supplies", ["wire"]],
	["Base", ["reinforce", "shelves", "drill"]],
]

# Zombie types and weapons live in data/zombies/*.tres and data/weapons/*.tres
# so they can be tuned in the Inspector. They are read into plain dictionaries
# here, keyed by file name.
const ZOMBIE_KEYS := ["walker", "runner", "brute"]
const WEAPON_KEYS := ["pistol", "smg", "shotgun", "rifle", "launcher"]
static var ZTYPES: Dictionary = _load_dir("res://data/zombies/", ZOMBIE_KEYS)

static var WEAPONS: Dictionary = _load_dir("res://data/weapons/", WEAPON_KEYS)
const SITE_KEYS := ["gas_station", "farmhouse", "hardware_store", "trailer_park", "radio_tower", "police_station", "rail_yard"]
static var SITES: Dictionary = _load_dir("res://data/sites/", SITE_KEYS)


static func _load_dir(dir: String, keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		var res = load(dir + k + ".tres")
		out[k] = res.to_dict()
	return out

const NAMES := ["Dana", "Marek", "Priya", "Hollis", "June", "Tomas", "Ada", "Kofi", "Rosa", "Lev", "Imke", "Sol"]
const JACKETS := [Color("7a5c3a"), Color("4d5a3c"), Color("5c3f4f"), Color("3d4f5c"), Color("6b6b4a")]
const DECK_H := 0.45     # walkway height, in metres
const SKINS := [Color("e0b896"), Color("c49270"), Color("8d5e3e"), Color("f1cfb0"), Color("a8775a")]
const CREW_SLOTS := [0.0, -3.0, 3.0, -5.5, 5.5]

# kind: weapon | mod (gear) | supply | trap. "short" is the label drawn in a slot.
const ITEMS := {
	"pistol": {"kind": "weapon", "short": "PST"},
	"smg": {"kind": "weapon", "short": "SMG"},
	"shotgun": {"kind": "weapon", "short": "SHT"},
	"rifle": {"kind": "weapon", "short": "RFL"},
	"launcher": {"kind": "weapon", "short": "GL"},
	"hollow": {"kind": "mod", "short": "HP", "name": "Hollow points", "desc": "Whoever carries these does 25% more damage."},
	"trigger": {"kind": "mod", "short": "HT", "name": "Hair trigger", "desc": "Whoever carries this fires 15% faster."},
	"molotov": {"kind": "mod", "short": "MOL", "name": "Molotov crate", "desc": "Whoever carries this throws a firebomb into the thickest crowd every 10 seconds."},
	"wire": {"kind": "supply", "short": "WIRE", "name": "Wire coil", "desc": "Use it to string barbed wire: the dead take 8 more damage a second at the wall."},
	"spikes": {"kind": "trap", "short": "SPK", "uses": 40.0, "name": "Spike strip", "desc": "Hurts and slows every zombie that crosses it. Wears down with use."},
	"beartrap": {"kind": "trap", "short": "BEAR", "uses": 6.0, "name": "Bear trap", "desc": "Snaps shut on the first zombie in and holds it in place. Six snaps before it breaks."},
	"mine": {"kind": "trap", "short": "MINE", "uses": 1.0, "name": "Landmine", "desc": "Blows up the first zombie that steps on it, and everything around it. One use."},
	"slick": {"kind": "trap", "short": "FUEL", "uses": 60.0, "name": "Fuel slick", "desc": "Slows the dead. A firebomb or explosion lights it into a big fire. Dries up after a minute."},
}

const KIND_COLORS := {
	"weapon": Color("c9a24a"),
	"mod": Color("6fa3c9"),
	"supply": Color("7dbb6a"),
	"trap": Color("d0703f"),
}
const KIND_TAG := {"weapon": "Weapon", "mod": "Gear", "supply": "Supply", "trap": "Trap"}

const TRAP_R := {"spikes": 0.6, "beartrap": 0.35, "mine": 0.35, "slick": 0.9}

const WALL_MATS := [
	{"name": "Timber", "top": Color("8a6a45"), "left": Color("5e452c"), "right": Color("71543a"), "chips": [Color("6e5236"), Color("8a6a45"), Color("4a3626")]},
	{"name": "Stone", "top": Color("9a9a92"), "left": Color("62625c"), "right": Color("7a7a73"), "chips": [Color("8a8a82"), Color("5a5a54"), Color("a8a89e")]},
	{"name": "Steel", "top": Color("93a6b3"), "left": Color("55636d"), "right": Color("6e808b"), "chips": [Color("7b8c97"), Color("4c5860"), Color("c8d3da")]},
]


static func item_name(key: String) -> String:
	var it: Dictionary = ITEMS[key]
	if it.has("name"):
		return it["name"]
	return WEAPONS[key]["name"]


static func item_desc(key: String) -> String:
	var it: Dictionary = ITEMS[key]
	if it.has("desc"):
		return it["desc"]
	return WEAPONS[key]["desc"]


static func item_kind(key: String) -> String:
	return ITEMS[key]["kind"]



## "Handy II"
static func skill_label(key: String, lvl: int) -> String:
	return "%s %s" % [SKILLS[key]["name"], LEVEL_MARKS[lvl - 1]]


## "Repairs the wall 50% faster"
static func skill_desc(key: String, lvl: int) -> String:
	var fx: float = SKILLS[key]["fx"][lvl - 1]
	return SKILLS[key]["fmt"] % ("%d%%" % int(round(absf(fx - 1.0) * 100.0)))


## A survivor's skill multiplier (1.0 if they don't have the skill).
static func skill_fx(s: Dictionary, key: String) -> float:
	var lvl: int = s.get("skills", {}).get(key, 0)
	return 1.0 if lvl <= 0 else float(SKILLS[key]["fx"][lvl - 1])
