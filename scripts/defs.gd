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
const HORDE_EVERY := 70.0

# Zombie types and weapons live in data/zombies/*.tres and data/weapons/*.tres
# so they can be tuned in the Inspector. They are read into plain dictionaries
# here, keyed by file name.
const ZOMBIE_KEYS := ["walker", "runner", "brute"]
const WEAPON_KEYS := ["pistol", "smg", "shotgun", "rifle", "launcher"]
static var ZTYPES: Dictionary = _load_dir("res://data/zombies/", ZOMBIE_KEYS)

static var WEAPONS: Dictionary = _load_dir("res://data/weapons/", WEAPON_KEYS)


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
	"repair": {"kind": "supply", "short": "FIX", "name": "Repair kit", "desc": "Use it to repair half of the wall."},
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

