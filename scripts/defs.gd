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

# Isometric tile size in pixels.
const TW := 64.0
const TH := 32.0

const MAX_CREW := 5
const WIRE_MAX := 24.0
const STORAGE_MAX := 24
const HORDE_EVERY := 70.0

const ZTYPES := {
	"walker": {"name": "Walker", "hp": 40.0, "speed": 0.6, "dmg": 8.0, "rate": 1.0, "xp": 1, "r": 0.2, "scale": 1.0,
		"skin": Color("8fa27a"), "shirts": [Color("4f5d6b"), Color("6b4f4a"), Color("5d5a42"), Color("3f5248")]},
	"runner": {"name": "Runner", "hp": 24.0, "speed": 1.35, "dmg": 5.0, "rate": 0.6, "xp": 2, "r": 0.17, "scale": 0.88,
		"skin": Color("a7b48a"), "shirts": [Color("7a3b3b"), Color("8a5a2b")]},
	"brute": {"name": "Brute", "hp": 260.0, "speed": 0.38, "dmg": 34.0, "rate": 1.5, "xp": 8, "r": 0.32, "scale": 1.55,
		"skin": Color("6f8a62"), "shirts": [Color("2f3a40"), Color("3b3330")]},
}

const WEAPONS := {
	"pistol": {"name": "Pistol", "dmg": 14.0, "rate": 0.34, "spread": 0.03, "range": 13.0, "pellets": 1, "pierce": 1, "knock": 0.04, "len": 9.0, "sound": "gun",
		"desc": "Reliable and accurate. Where everyone starts."},
	"smg": {"name": "SMG", "dmg": 7.0, "rate": 0.085, "spread": 0.09, "range": 11.0, "pellets": 1, "pierce": 1, "knock": 0.02, "len": 12.0, "sound": "smg",
		"desc": "Sprays fast and loose. Shreds crowds of walkers."},
	"shotgun": {"name": "Shotgun", "dmg": 10.0, "rate": 0.75, "spread": 0.3, "range": 7.5, "pellets": 7, "pierce": 1, "knock": 0.18, "len": 15.0, "sound": "shotgun",
		"desc": "Seven pellets at close range. Knocks the dead back off the wall."},
	"rifle": {"name": "Hunting rifle", "dmg": 55.0, "rate": 0.85, "spread": 0.004, "range": 22.0, "pellets": 1, "pierce": 4, "knock": 0.1, "len": 18.0, "sound": "rifle",
		"desc": "One heavy round that punches through four bodies."},
	"launcher": {"name": "Grenade launcher", "dmg": 70.0, "rate": 1.25, "spread": 0.02, "range": 16.0, "pellets": 1, "pierce": 1, "knock": 0.0, "splash": 1.7, "len": 14.0, "sound": "launch",
		"desc": "Lobbed grenades that blow apart whole clusters."},
}

const NAMES := ["Dana", "Marek", "Priya", "Hollis", "June", "Tomas", "Ada", "Kofi", "Rosa", "Lev", "Imke", "Sol"]
const JACKETS := [Color("7a5c3a"), Color("4d5a3c"), Color("5c3f4f"), Color("3d4f5c"), Color("6b6b4a")]
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


# Grid coordinates (tiles, continuous) -> world pixels.
static func g2w(gx: float, gy: float) -> Vector2:
	return Vector2((gx - gy) * TW * 0.5, (gx + gy) * TH * 0.5)


static func w2g(p: Vector2) -> Vector2:
	return Vector2(p.y / TH + p.x / TW, p.y / TH - p.x / TW)
