# Static game data: map layout, zombie types, weapons, items.
# Loaded with preload() so it works without the editor's class cache.
extends RefCounted

# --- Map --------------------------------------------------------------------
#   y = 0 ......... the dead enter here (far edge, top right of the screen)
#   y = WALL_Y .... the wall, spanning the lane from X0 to X1
#   y = WALK_Y .... the walkway the survivors stand on
#   y > WALK_Y .... the base (bottom left of the screen), from BASE_X0 to
#                   BASE_X1 across and back to BASE_Y1, fenced all round
const N := 22
const X0 := 4
const X1 := 18
const WALL_Y := 14.0
const WALL_T := 0.6
const WALK_Y := 15.2
const BASE_X0 := 1.0
const BASE_X1 := 21.0
const BASE_Y1 := 28.0     # the back fence, with the gate to the pass in it

# --- The three walls --------------------------------------------------------
# Each wall guards a lane the dead walk down. A lane has its own frame: u runs
# along the wall, v runs from the lane's far edge (v = 0, where the dead come
# in) towards the base; the wall stands at v = WALL_Y and its walkway at
# v = WALK_Y, so all three walls share the numbers above. A point in the lane
# is o + t * u + n * v. The front lane is the original one (u = x, v = y).
# The side lanes start hidden in darkness and open up as the night goes on.
const LANES := [
	{"name": "Front", "o": Vector2(0, 0), "t": Vector2(1, 0), "n": Vector2(0, 1), "u0": 4.0, "u1": 18.0, "weight": 1.0},
	{"name": "West", "o": Vector2(-13, 0), "t": Vector2(0, -1), "n": Vector2(1, 0), "u0": -27.0, "u1": -16.0, "weight": 0.7},
	{"name": "East", "o": Vector2(35, 0), "t": Vector2(0, 1), "n": Vector2(-1, 0), "u0": 16.0, "u1": 27.0, "weight": 0.7},
]
# Seconds into the run each lane opens: the west on the morning of day 3, the
# east on the morning of day 5 (half a minute after dawn). Once a lane opens
# the dead take SIDE_GRACE seconds to start coming down it, so there's time to
# move people over.
const SIDE_OPEN_AT := [0.0, 590.0, 1150.0]   # day 3 and day 5, half a minute after dawn
# Levels: which lanes the dead come down, and when each side lane opens
# (INF: never; its pipe is sealed). grit: how much more Grit a run pays.
const LEVELS := [
	{"name": "The Road", "short": "1 lane",
		"desc": "One way in: the dead only come down the lane in front of your wall. The side pipes are sealed.",
		"open_at": [0.0, INF, INF], "grit": 1.0},
	{"name": "The Crossroads", "short": "3 lanes",
		"desc": "Three walls to hold: the west lane opens on the morning of day 3, the east on day 5.",
		"open_at": SIDE_OPEN_AT, "grit": 1.25},
	{"name": "The Siege", "short": "3 lanes from day 1",
		"desc": "All three lanes from the first morning, and the dead come thicker and tougher. The mountain pass at your back stays safe.",
		"open_at": [0.0, 15.0, 15.0], "grit": 1.5, "spawn": 1.15, "hp": 1.1},
	{"name": "Last Stand", "short": "endless",
		"desc": "No truck is coming. All three lanes, and the waves never end: hold out as long as you can. Grit for every night held.",
		"open_at": [0.0, 15.0, 15.0], "grit": 1.75, "spawn": 1.2, "hp": 1.15, "endless": true},
]
# The dead come in at the far end of each lane: v = LANE_START (the wall is at
# v = WALL_Y, so they walk WALL_Y - LANE_START tiles to reach it).
const LANE_START := -8.0
# Each lane ends in a concrete culvert: the dead come out of its sewer pipes.
# PIPES: for each lane, where across it (u) each pipe's mouth is.
const PIPES := [[7.5, 14.5], [-21.5], [21.5]]
const PIPE_V := LANE_START - 1.6     # the face of the headwall, down each lane
const PIPE_R := 1.3                  # pipe radius, metres (inside)
const PIPE_SPAWN_V := PIPE_V - 0.45  # where the dead appear, just out of the dark
const SIDE_WARNING := 40.0                  # seconds of warning before one opens
const SIDE_GRACE := 60.0
const HUB := Vector2(11.2, 22.5)            # the middle of the yard, on the way to the gate

# --- Lulls -------------------------------------------------------------------
# Every so often the dead thin out for a while: just a straggler every few
# seconds, however late it is, and a horde that's due waits until it's over.
const FIRST_LULL := 70.0
const LULL_EVERY := [50.0, 75.0]      # seconds from the end of one lull to the next
const LULL_LENGTH := [25.0, 35.0]
const LULL_RATE := 0.2                # zombies a second during a lull (one every 5 s)

const WIRE_LIMIT := 3        # barbed-wire coils out on the ground at once
const STORAGE_MAX := 24

# --- Day and night ----------------------------------------------------------
# Each cycle is a day then a night. By day the dead only drift in and the
# lulls happen; when night falls the horde comes, with a second wave at
# midnight, and more of them keep coming until dawn.
const DAY_LENGTH := 180.0
const NIGHT_LENGTH := 100.0
const CYCLE := DAY_LENGTH + NIGHT_LENGTH
const TWILIGHT := 15.0          # seconds the light takes to fade at dusk (and return at dawn)
const DUSK_WARNING := 20.0      # warned this long before nightfall
const DAY_SPAWN := 0.35         # share of the normal spawn rate by day
const NIGHT_SPAWN := 0.72       # and by night
const NIGHT_WIND_DOWN := 45.0  # the last seconds of the night: no more horde, only a trickle of stragglers, so dawn finds it mostly dealt with
const WIND_DOWN_SPAWN := 0.15  # that trickle, as a share of the normal spawn rate
const MIDNIGHT_WAVE := 0.5      # the midnight wave, as a share of the nightfall horde

# --- How fast the night gets harder -----------------------------------------
# Zombies a second (outside lulls and hordes): SPAWN_BASE + t * SPAWN_LINEAR
# + (t / SPAWN_CURVE)^2 * 0.6, with t the seconds survived. Their health is
# multiplied by 1 + t / HP_LINEAR + (t / HP_CURVE)^2, and their speed by
# 1 + t / SPEED_RAMP (at most +35%). Raise the divisors to slow the ramp.
const SPAWN_BASE := 0.3
const SPAWN_LINEAR := 0.002
const SPAWN_CURVE := 480.0
const HP_LINEAR := 550.0
const HP_CURVE := 950.0
const SPEED_RAMP := 1600.0
const THREAT_EVERY := 60.0            # seconds per threat level shown on screen
const HORDE_SIZE := [3, 30.0]         # a nightfall horde is 3 + one more per 30 seconds survived
const START_SCRAP := 120
const RUNNERS_FROM := 90.0            # seconds before the first runners can turn up
const BRUTES_FROM := 200.0            # and the first brutes

# --- Scavenging, strangers, food -------------------------------------------
const WALK_SPEED := 2.2                 # tiles per second, walking to and from the pass
const PLAYER_SPEED := 3.4               # you, walking with WASD (tiles per second)
const BACKPEDAL := 0.5                  # walking backwards (away from where you aim): this share of that pace
# The route from the back of the base up through the mountain pass (x, y).
const PASS_PATH := [Vector2(11.2, 22.5), Vector2(11.2, 29.0), Vector2(11.7, 32.5), Vector2(12.5, 36.0), Vector2(12.6, 40.0), Vector2(12.1, 44.0)]
const SCRAP_TIERS := [[20, 36], [38, 64], [70, 120]]   # low, medium, high: min and max scrap
const SCRAP_NAMES := ["Low", "Medium", "High"]
# --- When a wall breaks -------------------------------------------------------
# A broken wall lets that lane's dead into the base, where they go for the
# crew. The run ends when nobody in the base is left alive. Repairing a broken
# wall to PATCH_AT of its strength closes the gap again.
const SURVIVOR_HP := 100.0
const BITE := 1.3               # damage to a survivor per hit, as a multiple of the zombie's wall damage
const HEAL_PER_SECOND := 3.0    # survivors recover this fast with no zombie within HEAL_CLEAR tiles
const HEAL_CLEAR := 5.0
const PATCH_AT := 0.25
const EARLY_CLOSE := 2                   # a run opens with this many zombies already in the lane...
const EARLY_V := [6.0, 7.5]             # ...partway down it (the wall is at WALL_Y)
const FIRST_STRANGER_AT := 30.0        # seconds into a run when the first survivor walks in
const STRANGER_EVERY_WHEN_ALONE := 25.0 # after that, only once you've lost everyone: average wait
const START_FOOD := 6.0
const FOOD_PER_MINUTE := 0.5            # eaten by each survivor (you included), all the time
const FOOD_BAR_MIN := 20.0              # the food bar's scale: this much, or more if you hold more
const HUNGRY_SLOWDOWN := 1.25           # hungry crews take this much longer between shots
const HOT_MEAL := {"rate": 0.85, "seconds": 45.0}   # Field kitchen: faster shooting after sundown
const PANTRY := {"food": 6.0, "eat": 0.9}           # the camp's Pantry: more food, eaten slower

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
#   scrounge multiplies the scrap they bring back and their odds of guns and bombs
#   forager  multiplies their odds of finding food (and the amount, by its square root)
#   cook     multiplies how fast the whole crew eats while they're at the base
#   fleet    multiplies how long their scavenging trips take (lower is faster)
#   careful  multiplies their chance of dying on a scavenging trip
# "player": false means you never roll it (you can't leave the wall).
const SKILLS := {
	"repair": {"name": "Handy", "fx": [1.25, 1.5, 1.85], "fmt": "Repairs the wall %s faster", "player": true},
	"thrift": {"name": "Thrifty", "fx": [1.25, 1.5, 1.85], "fmt": "Gets %s more wall out of each scrap when repairing", "player": true},
	"aim": {"name": "Sharpshooter", "fx": [1.1, 1.2, 1.32], "fmt": "Aims better: %s more damage and a tighter spread", "player": true},
	"quick": {"name": "Quick hands", "fx": [0.92, 0.85, 0.77], "fmt": "Shoots %s faster", "player": true},
	"scrounge": {"name": "Scrounger", "fx": [1.2, 1.4, 1.65], "fmt": "Brings back %s more scrap and finds guns and bombs more often", "player": false},
	"forager": {"name": "Forager", "fx": [1.3, 1.6, 2.0], "fmt": "Finds food %s more often on trips, and more of it", "player": false},
	"cook": {"name": "Cook", "fx": [0.9, 0.8, 0.7], "fmt": "While they're at the base, the whole crew eats %s less", "player": true},
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

# --- The wall ---------------------------------------------------------------
# It starts as a fence. Research carpentry, then masonry, and build the next
# tier in the workshop: it gets tougher and is patched up by the difference.
const WALL_TIERS := [
	{"name": "Fence", "hp": 500.0},
	{"name": "Wooden wall", "hp": 850.0},
	{"name": "Stone wall", "hp": 1400.0},
]

# --- Buildings --------------------------------------------------------------
# Turrets are bought in the workshop and then placed in the yard by clicking. They can't go on a walkway, on another building, on the
# props below or on the path to the gate. The SPOTS are where the automated
# test bot puts them.
const MAX_TURRETS := 4
# Turning: nobody snaps onto a new target. Radians a second, and how close to
# lined up (radians) the gun must be before it fires.
const TURN_RATE := 4.5            # the crew, swinging onto auto-fire targets
const TURN_RATE_MANUAL := 9.0     # you, following the mouse
const TURRET_TURN := 2.4          # a turret's motorised swivel
const AIM_TOLERANCE := 0.09
# Once a wall is down: how the dead hunt inside the base.
const SPREAD_CHANCE := 0.3        # this share of them pick another target than the nearest
const FLANK := 0.6                # inside, each makes for its own spot on a ring round its target, this far out per metre away...
const FLANK_MAX := 4.5            # ...up to this many metres, so the pack fans out and surrounds instead of queueing
const FLANK_TURN := 1.9           # each comes round to its own side of the target, up to this far (radians) off its straight line
const FLANK_CLOSE := 2.0          # and within this, straight for them
const RETARGET := Vector2(0.8, 1.6)   # seconds between choosing again (random in range)
const TURRET_REPAIR := 14.0       # turret health restored per second, per repairer
const TURRET_PER_SCRAP := 5.0     # turret health for each scrap spent
const GAP_HALF := 1.5             # (old saves: a broken wall's gap, this far either side of where it gave way)
# Each wall is built in sections about WALL_SEG metres long, each with its own
# strength (WALL_SEG_HP of the wall tier's), broken and repaired on its own.
const WALL_SEG := 2.8
const WALL_SEG_HP := 0.45
const TURRET_HP := 160.0          # the dead can tear a turret down
const TURRET_REACH := 1.8         # how close to a turret a zombie at the wall must be to claw at it
const BUILD_SIZE := {"turret": Vector2(1.2, 1.2), "radio": Vector2(1.6, 1.6)}
const RADIO_SPOT := Vector2(17.8, 25.0)       # where the test bot puts the radio
const RADIO_EVERY := 180.0                    # a survivor hears the radio about this often (seconds, on average)
const GATE_PATH := Rect2(9.9, 20.8, 2.6, 7.6)
const BLOCKERS := [
	Rect2(3.6, 16.8, 2.8, 2.4),    # bunker
	Rect2(13.2, 17.3, 1.7, 1.4),   # hut
	Rect2(14.5, 18.7, 1.9, 1.8),   # hut
	Rect2(8.6, 17.8, 1.8, 1.8),    # crates
	Rect2(11.8, 19.0, 0.8, 0.8),   # barrel
	Rect2(12.3, 19.7, 1.0, 1.0),   # fire barrel
	Rect2(7.9, 19.8, 2.0, 2.2),    # tent and barrel
	GATE_PATH,                     # the path to the gate (and where the army truck parks)
	Rect2(3.6, 26.1, 1.4, 1.0),    # generator
	Rect2(5.2, 25.4, 0.4, 0.4),    # its work lamp
	Rect2(16.1, 26.6, 1.8, 0.9),   # workbench
	Rect2(13.4, 26.8, 1.6, 0.8),   # woodpile
	Rect2(7.8, 24.3, 0.4, 0.4),    # lamp post
	Rect2(14.3, 24.3, 0.4, 0.4),   # lamp post
]
const TURRET_SPOTS := [Vector2(2.9, 15.0), Vector2(19.1, 15.0), Vector2(6.8, 22.0), Vector2(15.8, 22.6)]
const TURRET := {"dmg": 9.0, "rate": 0.55, "range": 9.0, "spread": 0.05, "pellets": 1, "pierce": 1, "knock": 0.03, "sound": "smg"}

# --- Research ---------------------------------------------------------------
# Scrap is spent when a project starts; it then takes "time" seconds. One at a
# time. Workshop entries with "needs" stay locked until that research is done.
# "fx" upgrades apply as soon as the research finishes:
#   turret_dmg / turret_rate / turret_range multiply the turrets' numbers
#   food_find multiplies the chance of food on a trip
#   food_yield multiplies how much food a trip brings back
#   eat multiplies how fast the crew eats
#   hunger multiplies the slowdown when the food runs out
const RESEARCH_BRANCHES := ["Guns", "Gear", "Traps", "Defences", "Turrets", "Provisions"]
const RESEARCH := {
	# Guns
	"firearms": {"branch": 0, "name": "SMG", "cost": 20, "time": 15.0, "needs": [], "desc": "Fix up automatic weapons. Unlocks the SMG."},
	"shotguns": {"branch": 0, "name": "Scatter guns", "cost": 40, "time": 30.0, "needs": ["firearms"], "desc": "Unlocks the shotgun."},
	"rifles": {"branch": 0, "name": "Long guns", "cost": 60, "time": 40.0, "needs": ["shotguns"], "desc": "Unlocks the hunting rifle."},
	"launchers": {"branch": 0, "name": "Grenade launchers", "cost": 90, "time": 50.0, "needs": ["rifles", "explosives"], "desc": "Unlocks the grenade launcher."},
	# Gear
	"reloading": {"branch": 1, "name": "Hand loading", "cost": 30, "time": 25.0, "needs": ["firearms"], "desc": "Unlocks hollow points."},
	"gunsmith": {"branch": 1, "name": "Gunsmithing", "cost": 35, "time": 30.0, "needs": ["reloading"], "desc": "Unlocks the hair trigger."},
	"drills": {"branch": 1, "name": "Combat drills", "cost": 45, "time": 35.0, "needs": ["gunsmith"], "desc": "Unlocks drilling the crew."},
	"firebombs": {"branch": 1, "name": "Firebombs", "cost": 30, "time": 25.0, "needs": ["fuel"], "desc": "Unlocks molotovs: throw one where you click to set the ground alight."},
	"pipebombs": {"branch": 1, "name": "Pipe bombs", "cost": 40, "time": 30.0, "needs": ["explosives"], "desc": "Unlocks pipe bombs: throw one where you click to blow apart everything nearby."},
	# Traps
	"spikes": {"branch": 2, "name": "Spike strips", "cost": 15, "time": 15.0, "needs": [], "desc": "Unlocks the spike strip."},
	"beartraps": {"branch": 2, "name": "Bear traps", "cost": 25, "time": 20.0, "needs": ["spikes"], "desc": "Unlocks the bear trap."},
	"fuel": {"branch": 2, "name": "Fuel slicks", "cost": 20, "time": 20.0, "needs": ["spikes"], "desc": "Unlocks the fuel slick."},
	"explosives": {"branch": 2, "name": "Explosives", "cost": 40, "time": 35.0, "needs": ["beartraps"], "desc": "Unlocks the landmine."},
	# Defences
	"shelving": {"branch": 3, "name": "Shelving", "cost": 15, "time": 10.0, "needs": [], "desc": "Unlocks extra storage shelves."},
	"carpentry": {"branch": 3, "name": "Carpentry", "cost": 40, "time": 30.0, "needs": [], "desc": "Unlocks the wooden wall."},
	"barbed": {"branch": 3, "name": "Barbed wire", "cost": 30, "time": 25.0, "needs": ["carpentry"], "desc": "Unlocks wire coils."},
	"masonry": {"branch": 3, "name": "Masonry", "cost": 80, "time": 50.0, "needs": ["carpentry"], "desc": "Unlocks the stone wall."},
	"radio": {"branch": 3, "name": "Radio", "cost": 45, "time": 35.0, "needs": ["carpentry"], "desc": "Unlocks the radio station: it broadcasts, and now and then a survivor who hears it finds their way in."},
	# Turrets
	"turrets": {"branch": 4, "name": "Auto-turrets", "cost": 60, "time": 40.0, "needs": ["firearms", "carpentry"], "desc": "Unlocks the auto-turret: it shoots on its own from a corner of the base."},
	"turret_ammo": {"branch": 4, "name": "Heavy rounds", "cost": 50, "time": 35.0, "needs": ["turrets"], "desc": "Turrets do 50% more damage.", "fx": {"turret_dmg": 1.5}},
	"turret_feed": {"branch": 4, "name": "Belt feed", "cost": 70, "time": 45.0, "needs": ["turret_ammo"], "desc": "Turrets fire 40% faster.", "fx": {"turret_rate": 0.6}},
	"turret_optics": {"branch": 4, "name": "Turret optics", "cost": 60, "time": 40.0, "needs": ["turret_ammo"], "desc": "Turrets reach a third further.", "fx": {"turret_range": 1.33}},
	# Provisions
	"foraging": {"branch": 5, "name": "Foraging", "cost": 30, "time": 25.0, "needs": [], "desc": "Scavengers find food 50% more often, and never come back without at least 1 food.", "fx": {"food_find": 1.5}},
	"rationing": {"branch": 5, "name": "Rationing", "cost": 40, "time": 30.0, "needs": ["foraging"], "desc": "The crew eats 25% less.", "fx": {"eat": 0.75}},
	"smokehouse": {"branch": 5, "name": "Smokehouse", "cost": 50, "time": 35.0, "needs": ["rationing"], "desc": "Food brought back from trips goes 50% further.", "fx": {"food_yield": 1.5}},
	"kitchen": {"branch": 5, "name": "Field kitchen", "cost": 60, "time": 40.0, "needs": ["smokehouse"], "desc": "Going hungry hurts half as much, and a hot meal at sundown has everyone shooting 15% faster for the first part of the night.", "fx": {"hunger": 0.5}},
}

# --- Workshop: what scrap buys ---------------------------------------------
# Items go to base storage. Buildings, wall, shelving and drill take effect at
# once; some get dearer each time. Everything needs its research first.
const SHOP := {
	"smg": {"cost": 35, "name": "SMG", "needs": "firearms"},
	"shotgun": {"cost": 45, "name": "Shotgun", "needs": "shotguns"},
	"rifle": {"cost": 70, "name": "Hunting rifle", "needs": "rifles"},
	"launcher": {"cost": 110, "name": "Grenade launcher", "needs": "launchers"},
	"hollow": {"cost": 30, "name": "Hollow points", "needs": "reloading"},
	"trigger": {"cost": 30, "name": "Hair trigger", "needs": "gunsmith"},
	"molotov": {"cost": 12, "name": "Molotov", "needs": "firebombs"},
	"pipebomb": {"cost": 18, "name": "Pipe bomb", "needs": "pipebombs"},
	"wire": {"cost": 25, "name": "Wire coil", "needs": "barbed", "desc": "A coil of barbed wire to lay across a lane: the dead crossing it are slowed and cut. Up to 3 out at once."},
	"spikes": {"cost": 15, "name": "Spike strip", "needs": "spikes"},
	"beartrap": {"cost": 20, "name": "Bear trap", "needs": "beartraps"},
	"mine": {"cost": 15, "name": "Landmine", "needs": "explosives"},
	"slick": {"cost": 15, "name": "Fuel slick", "needs": "fuel"},
	"wall_wood": {"cost": 70, "name": "Wooden wall", "needs": "carpentry", "desc": "Replace the fence with a wooden wall: much tougher."},
	"wall_stone": {"cost": 140, "name": "Stone wall", "needs": "masonry", "desc": "Rebuild the wall in stone: tougher still."},
	"radio": {"cost": 60, "name": "Radio station", "needs": "radio", "desc": "Broadcasts day and night: now and then a survivor hears it and walks in through the pass on their own (while there's room in the crew). Click in the base to put it where you like. One only."},
	"turret": {"cost": 70, "name": "Auto-turret", "needs": "turrets", "desc": "A turret that shoots on its own. Click in the base to put it where you like. Up to four."},
	"shelves": {"cost": 30, "name": "Shelving", "needs": "shelving", "desc": "Base storage holds 4 more items."},
	"drill": {"cost": 50, "name": "Drill the crew", "needs": "drills", "desc": "Everyone else on the wall does 30% more damage and fires 12% faster."},
}
const SHOP_SECTIONS := [
	["Base", ["wall_wood", "wall_stone", "turret", "radio", "shelves", "drill"]],
	["Guns", ["smg", "shotgun", "rifle", "launcher"]],
	["Gear", ["hollow", "trigger"]],
	["Throwables", ["molotov", "pipebomb"]],
	["Traps", ["spikes", "beartrap", "mine", "slick"]],
	["Traps", ["wire"]],
]

# Zombie types and weapons live in data/zombies/*.tres and data/weapons/*.tres
# so they can be tuned in the Inspector. They are read into plain dictionaries
# here, keyed by file name.
const ZOMBIE_KEYS := ["walker", "runner", "brute"]
const WEAPON_KEYS := ["pistol", "smg", "shotgun", "rifle", "launcher"]
static var ZTYPES: Dictionary = _load_dir("res://data/zombies/", ZOMBIE_KEYS)

static var WEAPONS: Dictionary = _load_dir("res://data/weapons/", WEAPON_KEYS)
const SITE_KEYS := ["gas_station", "farmhouse", "hardware_store", "trailer_park", "radio_tower", "police_station", "rail_yard", "ranger_cabin"]
static var SITES: Dictionary = _load_dir("res://data/sites/", SITE_KEYS)


static func _load_dir(dir: String, keys: Array) -> Dictionary:
	var out := {}
	for k in keys:
		var res = load(dir + k + ".tres")
		out[k] = res.to_dict()
	return out

const NAMES := ["Dana", "Marek", "Priya", "Hollis", "June", "Tomas", "Ada", "Kofi", "Rosa", "Lev", "Imke", "Sol"]
const PLAYER_COLOURS := [Color("3e5a6e"), Color("7a3b30"), Color("3f6a3a"), Color("6a5a2a"), Color("5a3f6e")]   # co-op players' jackets
const JACKETS := [Color("7a5c3a"), Color("4d5a3c"), Color("5c3f4f"), Color("3d4f5c"), Color("6b6b4a")]
const DECK_H := 0.45     # walkway height, in metres
const SKINS := [Color("e0b896"), Color("c49270"), Color("8d5e3e"), Color("f1cfb0"), Color("a8775a")]
const CREW_SLOTS := [0.0, 2.0, -2.0, 4.0, -4.0, 5.8, -5.8]   # spots on the front wall, measured from its middle: you start at 0, the crew take the rest, nearest the middle first

# kind: weapon | mod (gear) | supply | trap. "short" is the label drawn in a slot.
const ITEMS := {
	"pistol": {"kind": "weapon", "short": "PST"},
	"smg": {"kind": "weapon", "short": "SMG"},
	"shotgun": {"kind": "weapon", "short": "SHT"},
	"rifle": {"kind": "weapon", "short": "RFL"},
	"launcher": {"kind": "weapon", "short": "GL"},
	"hollow": {"kind": "mod", "short": "HP", "name": "Hollow points", "desc": "Whoever carries these does 25% more damage."},
	"trigger": {"kind": "mod", "short": "HT", "name": "Hair trigger", "desc": "Whoever carries this fires 15% faster."},
	"molotov": {"kind": "throw", "short": "MOL", "name": "Molotov", "desc": "One use. Use it, then click where to throw it: the ground there burns for a few seconds."},
	"pipebomb": {"kind": "throw", "short": "PIPE", "name": "Pipe bomb", "desc": "One use. Use it, then click where to throw it: it blows apart everything nearby."},
	"wire": {"kind": "trap", "short": "WIRE", "uses": 60.0, "name": "Wire coil", "desc": "Drag it onto the ground in a lane: a coil of barbed wire across it. The dead crossing it are slowed hard and cut. Up to 3 out at once. Wears down with use."},
	"spikes": {"kind": "trap", "short": "SPK", "uses": 40.0, "name": "Spike strip", "desc": "Hurts and slows every zombie that crosses it. Wears down with use."},
	"beartrap": {"kind": "trap", "short": "BEAR", "uses": 6.0, "name": "Bear trap", "desc": "Snaps shut on the first zombie in and holds it in place. Six snaps before it breaks."},
	"mine": {"kind": "trap", "short": "MINE", "uses": 1.0, "name": "Landmine", "desc": "Blows up the first zombie that steps on it, and everything around it. One use."},
	"slick": {"kind": "trap", "short": "FUEL", "uses": 60.0, "name": "Fuel slick", "desc": "Slows the dead. A firebomb or explosion lights it into a big fire. Dries up after a minute."},
}

const KIND_COLORS := {
	"weapon": Color("c9a24a"),
	"mod": Color("6fa3c9"),
	"supply": Color("7dbb6a"),
	"throw": Color("e05a4a"),
	"trap": Color("d0703f"),
}
const KIND_TAG := {"weapon": "Weapon", "mod": "Gear", "supply": "Supply", "trap": "Trap", "throw": "Throwable"}

# Throwables: how far a survivor can throw, and what a pipe bomb does.
const THROW_RANGE := 11.0
const PIPEBOMB := {"dmg": 170.0, "splash": 2.3}

# Tearing an item down in storage gives back this share of its workshop cost.
const SALVAGE_SHARE := 0.4

const TRAP_R := {"spikes": 0.8, "beartrap": 0.35, "mine": 0.35, "slick": 0.9, "wire": 1.3}
## Traps laid across a lane as a strip: length (along the wall) and depth, metres.
const TRAP_SIZE := {"spikes": Vector2(1.6, 0.55), "wire": Vector2(2.6, 0.6)}

# Chip colours by wall tier (fence, wooden wall, stone wall).
const WALL_MATS := [
	{"name": "Fence", "top": Color("8a6a45"), "left": Color("5e452c"), "right": Color("71543a"), "chips": [Color("6e5236"), Color("8a6a45"), Color("4a3626")]},
	{"name": "Timber", "top": Color("8a6a45"), "left": Color("5e452c"), "right": Color("71543a"), "chips": [Color("6e5236"), Color("8a6a45"), Color("4a3626")]},
	{"name": "Stone", "top": Color("9a9a92"), "left": Color("62625c"), "right": Color("7a7a73"), "chips": [Color("8a8a82"), Color("5a5a54"), Color("a8a89e")]},
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


# --- Runs and the camp (roguelite progression) --------------------------------
# A run is won by holding out WIN_NIGHTS nights: the rescue convoy comes at the
# next dawn. Win or lose, the run pays Grit, which is spent at the camp on
# upgrades that last from run to run (saved in user://progress.cfg).
const WIN_NIGHTS := 5
const GRIT := {"base": 5, "night": 10, "kills_per": 20, "research": 1, "survivor": 2, "win": 50}
# Heat: each win unlocks the next level. Every level adds these on top.
const MAX_HEAT := 5
const HEAT_SPAWN := 0.15      # more zombies a second, per level
const HEAT_HP := 0.12         # tougher zombies, per level
const HEAT_GRIT := 0.25       # more Grit, per level

const META_CATS := ["Your skills", "Starting kit", "Blueprints", "Base"]
# Scavenger's eye: per level, how much likelier lucky finds are, and how much more scrap.
const SCAV_EYE_FIND := 0.2
const SCAV_EYE_SCRAP := 0.1
# Upgrades that take hold at once when bought in the middle of a run (the rest
# wait for the next run: you can't start a run you're already in).
const META_LIVE := ["salvager", "p_repair", "p_thrift", "p_aim", "p_quick", "commander", "tough", "quartermaster", "scav_eye"]
# cat: which column; costs: Grit for each level; needs: upgrades bought first.
# Your skills raise your own character's skill to at least that level.
const META := {
	"salvager": {"cat": 0, "name": "Salvager", "costs": [10, 50, 100], "desc": "Every zombie killed gives 1 scrap per level (2 per level for brutes)."},
	"p_repair": {"cat": 0, "name": "Handy", "costs": [15, 30, 50], "desc": "You repair faster (your Handy skill, at least this level)."},
	"p_thrift": {"cat": 0, "name": "Thrifty", "costs": [15, 30, 50], "desc": "You get more wall out of each scrap (Thrifty, at least this level)."},
	"p_aim": {"cat": 0, "name": "Sharpshooter", "costs": [20, 40, 65], "desc": "You hit harder and straighter (Sharpshooter, at least this level)."},
	"p_quick": {"cat": 0, "name": "Quick hands", "costs": [20, 40, 65], "desc": "You shoot and reload faster (Quick hands, at least this level)."},
	"commander": {"cat": 0, "name": "Commander", "costs": [25, 50], "desc": "The rest of the crew does 10% more damage per level."},
	"tough": {"cat": 0, "name": "Tough", "costs": [20, 40, 60], "desc": "Every wall is 10% tougher per level, whatever it's built from."},
	"quartermaster": {"cat": 0, "name": "Quartermaster", "costs": [25, 50], "desc": "Everything in the workshop costs 8% less per level."},
	"scav_eye": {"cat": 0, "name": "Scavenger's eye", "costs": [20, 40, 70], "desc": "Whoever goes scavenging finds more: per level, survivors, guns, food and molotovs or pipe bombs turn up 20% more often, and they bring back 10% more scrap."},
	"kit_scrap": {"cat": 1, "name": "Scrap stash", "costs": [5, 15, 30, 45], "desc": "Start with 25 more scrap per level."},
	"kit_smg": {"cat": 1, "name": "SMG", "costs": [40], "desc": "Start with an SMG instead of the pistol."},
	"kit_traps": {"cat": 1, "name": "Spike strips", "costs": [20, 30], "desc": "Start with two spike strips in storage per level."},
	"kit_food": {"cat": 1, "name": "Tinned food", "costs": [10, 20], "desc": "Start with 4 more food per level."},
	"kit_survivor": {"cat": 1, "name": "A friend", "costs": [60, 90, 130], "desc": "Start with one more survivor already on the wall beside you per level."},
	"bp_firearms": {"cat": 2, "name": "SMG", "costs": [25], "research": "firearms", "desc": "Start every run with the SMG researched."},
	"bp_spikes": {"cat": 2, "name": "Spike strips", "costs": [15], "research": "spikes", "desc": "Start every run with Spike strips researched."},
	"bp_carpentry": {"cat": 2, "name": "Carpentry", "costs": [35], "research": "carpentry", "desc": "Start every run with Carpentry researched."},
	"bp_foraging": {"cat": 2, "name": "Foraging", "costs": [30], "research": "foraging", "desc": "Start every run with Foraging researched."},
	"bp_rationing": {"cat": 2, "name": "Rationing", "costs": [40], "research": "rationing", "needs": ["bp_foraging"], "desc": "Start every run with Rationing researched."},
	"bp_shelving": {"cat": 2, "name": "Shelving", "costs": [15], "research": "shelving", "desc": "Start every run with Shelving researched."},
	"bp_reloading": {"cat": 2, "name": "Hand loading", "costs": [30], "research": "reloading", "needs": ["bp_firearms"], "desc": "Start every run with Hand loading researched."},
	"bp_shotguns": {"cat": 2, "name": "Scatter guns", "costs": [35], "research": "shotguns", "needs": ["bp_firearms"], "desc": "Start every run with Scatter guns researched."},
	"bp_turrets": {"cat": 2, "name": "Auto-turrets", "costs": [55], "research": "turrets", "needs": ["bp_firearms", "bp_carpentry"], "desc": "Start every run with Auto-turrets researched."},
	"base_wood": {"cat": 3, "name": "Wooden walls", "costs": [60], "desc": "Start with wooden walls instead of fences."},
	"base_shelves": {"cat": 3, "name": "Shelving", "costs": [20, 35], "desc": "Start with 4 more storage slots per level."},
	"base_pantry": {"cat": 3, "name": "Pantry", "costs": [40], "desc": "Start with 6 more food, kept well enough that the crew eats 10% less all run."},
	"base_turret": {"cat": 3, "name": "Turret", "costs": [70], "desc": "Start with an auto-turret on the front corner."},
}
