# The aiming reticle over the battlefield, drawn in place of the mouse cursor:
# a black ring crossed by four ticks, with a dot where you're aiming. The
# ticks slide out to show how far a shot could stray at that distance (your
# gun's spread, worse further out, tighter with aim skill), and back in when
# you aim closer or pick up a steadier gun. A thin pale edge keeps it visible
# on dark ground at night.
extends Control

const Game = preload("res://scripts/game.gd")

const RING := 9.5        # ring radius, pixels
const RING_W := 3.5
const TICK_IN := 5.5     # ticks run from here out (at perfect aim)...
const TICK_OUT := 14.5   # ...to here
const TICK_W := 3.2
const DOT := 2.2
const MAX_SPREAD := 90.0 # pixels the ticks can move out
const EDGE := Color(0.95, 0.95, 0.95, 0.75)
const INK := Color(0.02, 0.02, 0.02, 1.0)

var main: Node
var spread := 0.0        # how far the ticks are pushed out, pixels (eased)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	var want := 0.0
	var show := _wanted()
	if show:
		want = _spread_px()
	spread = lerpf(spread, want, 1.0 - exp(-dt * 14.0))
	if show != visible:
		visible = show
	if show:
		queue_redraw()


## Shown over open battlefield: not over buttons or panels, not while you're
## hovering a survivor (that's the pointing hand), not when the cursor's hidden.
func _wanted() -> bool:
	if main == null or not main.started or main.game.over:
		return false
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return false
	if main.pointing():
		return false   # the hand: picking someone, sending them, placing something
	return get_viewport().gui_get_hovered_control() == main.hud.field


## How far a shot could stray at the aimed spot, in screen pixels.
func _spread_px() -> float:
	var g = main.game
	if g.crew.is_empty() or g.input_aim == null:
		return 0.0
	var me = main.local_player()
	if me == null:
		return 0.0
	if me["hp"] <= 0.0:
		return 0.0
	var aim: Vector2 = g.input_aim
	var dist := aim.distance_to(Vector2(me["x"], me["y"]))
	var metres := dist * tan(Game.aim_spread(me, dist))
	var ppm: float = get_viewport_rect().size.y / main.rig.cam.size   # pixels a metre
	return clampf(metres * ppm, 0.0, MAX_SPREAD)


func _draw() -> void:
	# Where the battlefield last saw the cursor (what aiming uses too).
	var c: Vector2 = main._mouse_screen if main._mouse_screen != null else get_local_mouse_position()
	# The pale edge first, then the black on top.
	_shape(c, 1.4, EDGE)
	_shape(c, 0.0, INK)


func _shape(c: Vector2, grow: float, col: Color) -> void:
	draw_arc(c, RING, 0.0, TAU, 40, col, RING_W + grow * 2.0, true)
	draw_circle(c, DOT + grow, col, true, -1.0, true)
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a: Vector2 = c + dir * (TICK_IN + spread - grow)
		var b: Vector2 = c + dir * (TICK_OUT + spread + grow)
		draw_line(a, b, col, TICK_W + grow * 2.0, true)
