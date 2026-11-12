# The lie of the land: how high the ground is at any (x, z). The base, the
# ground along each wall and the trail to the pass are level; the lanes the dead
# walk down roll gently; beyond them the land rises into hills and hollows that
# grow with distance. The ground mesh, the trees and the
# mountains all ask this one function, so everything sits on the same ground.
extends RefCounted

const D = preload("res://scripts/defs.gd")

const SEED := 4242
const BLEND := 6.0        # metres over which flat ground rises into the hills
const HILLS := 4.2        # height of the big rolls, in metres
const BUMPS := 0.6        # height of the small lumps on top
const FAR_GAIN := 0.035   # hills get this much taller per metre further out (up to double)
const LANE_ROLL := 0.35   # how far the lanes rise and dip, in metres
const WALL_FLAT := 2.5    # the lanes stay level this close to their wall
# Heights are worked out once on a grid and read back from it (see sample()).
const GRID_AREA := Rect2(-42, -42, 106, 106)
const GRID_STEP := 0.5

static var _big: FastNoiseLite
static var _small: FastNoiseLite
static var _flat: Array = []   # Rect2s (x, z) that stay level
static var _lanes: Array = []  # Rect2s (x, z) of the lanes' ground, which rolls gently
static var _grid := PackedFloat32Array()
static var _gw := 0
static var _gh := 0


static func _setup() -> void:
	if _big != null:
		return
	_big = FastNoiseLite.new()
	_big.seed = SEED
	_big.frequency = 0.045
	_big.fractal_octaves = 3
	_small = FastNoiseLite.new()
	_small.seed = SEED + 1
	_small.frequency = 0.22
	_small.fractal_octaves = 2
	# Each lane's ground, with room around it.
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var a: Vector2 = L["o"] + L["t"] * (L["u0"] - 3.0) + L["n"] * (D.LANE_START - 6.0)
		var b: Vector2 = L["o"] + L["t"] * (L["u1"] + 3.0) + L["n"] * (D.WALK_Y + 1.5)
		var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())
		_flat.append(r)
		_lanes.append(r)
	# The base.
	_flat.append(Rect2(D.BASE_X0 - 1.5, D.WALL_Y - 1.0, D.BASE_X1 - D.BASE_X0 + 3.0, D.BASE_Y1 - D.WALL_Y + 2.5))


## Distance from (x, z) to the nearest flat ground (0 inside it).
static func _flat_distance(p: Vector2) -> float:
	var best := INF
	for r in _flat:
		var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
		var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	# The trail up through the pass stays level too.
	var pts: Array = D.PASS_PATH
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, maxf(0.0, p.distance_to(a.lerp(b, t)) - 2.0))
	if p.y > pts[-1].y:
		best = minf(best, maxf(0.0, absf(p.x - pts[-1].x) - 2.0))
	return best


## Gentle rolls in the lanes: none along the walls, so the walls stand level.
static func _lane_roll(p: Vector2) -> float:
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = p - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] - 3.0 and u <= L["u1"] + 3.0 and v >= D.LANE_START - 6.0 and v <= D.WALL_Y:
			var near_wall := smoothstep(D.WALL_Y - WALL_FLAT, D.WALL_Y - WALL_FLAT - 3.0, v)
			return _big.get_noise_2d(p.x * 2.2 + 100.0, p.y * 2.2) * LANE_ROLL * near_wall + _small.get_noise_2d(p.x, p.y) * 0.06 * near_wall
	return 0.0


## Ground height at (x, z), in metres, worked out from scratch (slow: the
## grid in sample() is what the game reads).
static func height(x: float, z: float) -> float:
	_setup()
	var d := _flat_distance(Vector2(x, z))
	if d <= 0.0:
		return _lane_roll(Vector2(x, z))
	var mask := smoothstep(0.0, BLEND, d)
	var far := 1.0 + minf(1.0, maxf(0.0, d - BLEND) * FAR_GAIN)
	# Rolls that are mostly above ground, with the odd hollow.
	var h := (_big.get_noise_2d(x, z) * 0.5 + 0.35) * HILLS * far + _small.get_noise_2d(x, z) * BUMPS
	return maxf(-0.6, h) * mask


## Ground height at (x, z), read from a grid worked out once (fast).
static func sample(x: float, z: float) -> float:
	if _grid.is_empty():
		_build_grid()
	var fx := clampf((x - GRID_AREA.position.x) / GRID_STEP, 0.0, _gw - 1.001)
	var fz := clampf((z - GRID_AREA.position.y) / GRID_STEP, 0.0, _gh - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_grid[j * _gw + i], _grid[j * _gw + i + 1], tx)
	var b := lerpf(_grid[(j + 1) * _gw + i], _grid[(j + 1) * _gw + i + 1], tx)
	return lerpf(a, b, tz)


const BAKED := "res://assets/baked/terrain.res"


static func _build_grid() -> void:
	_gw = int(GRID_AREA.size.x / GRID_STEP) + 1
	_gh = int(GRID_AREA.size.y / GRID_STEP) + 1
	# A build made by the CI has the grid worked out already (tools/bake.gd).
	if ResourceLoader.exists(BAKED):
		var r = load(BAKED)
		if r != null and r.has_meta("grid") and r.get_meta("grid").size() == _gw * _gh:
			_grid = r.get_meta("grid")
			return
	_grid.resize(_gw * _gh)
	for j in _gh:
		for i in _gw:
			_grid[j * _gw + i] = height(GRID_AREA.position.x + i * GRID_STEP, GRID_AREA.position.y + j * GRID_STEP)


## True inside a lane's ground (for the dirt).
static func in_lane(x: float, z: float) -> bool:
	_setup()
	for side in D.LANES.size():
		var L: Dictionary = D.LANES[side]
		var d: Vector2 = Vector2(x, z) - L["o"]
		var u := d.dot(L["t"])
		var v := d.dot(L["n"])
		if u >= L["u0"] and u <= L["u1"] and v >= D.LANE_START - 0.5 and v <= D.WALL_Y + 0.6:
			return true
	return false
