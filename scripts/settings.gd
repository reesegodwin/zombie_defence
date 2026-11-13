# Display settings: window mode, window size and interface size. Saved to
# user://settings.cfg. On the very first run the game fits itself to the
# player's screen: a maximised window, with the interface scaled to match.
extends RefCounted

const PATH := "user://settings.cfg"
const MODES := ["Windowed", "Maximized", "Fullscreen"]
# Window sizes offered in windowed mode (only those that fit the screen show).
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
const UI_SCALES := [0.75, 0.9, 1.0, 1.15, 1.3, 1.5]
## Graphics presets, cheapest first ("Very Low" is for the oldest PCs: see main.apply_graphics).
const GRAPHICS := ["Very Low", "Low", "Medium", "High"]

var mode := "Maximized"
var size := Vector2i(1600, 900)
var ui_scale := 1.0
var fog := "High"          # ground fog quality: Off, Low, Medium, High (see ground_fog.gd)
var graphics := "High"     # Low, Medium, High: anti-aliasing, shadows, effects, lights (main.gd apply_graphics)
var detected := false      # true on the very first run, when graphics was picked for this PC
var path := PATH            # (tests use their own file)
var tutorial := true       # the highlight-and-arrow tutorial (scenes/ui/tutorial.gd)
var tutorial_done: Array = []   # its steps already done on this computer (each shows once, ever)


static func load_or_detect(p := PATH) -> RefCounted:
	var s = load("res://scripts/settings.gd").new()
	s.path = p
	var cfg := ConfigFile.new()
	if cfg.load(p) == OK:
		s.mode = cfg.get_value("display", "mode", s.mode)
		s.size = cfg.get_value("display", "size", s.size)
		s.ui_scale = cfg.get_value("display", "ui_scale", s.ui_scale)
		s.fog = cfg.get_value("graphics", "fog", s.fog)
		s.tutorial = cfg.get_value("tutorial", "on", true)
		s.tutorial_done = cfg.get_value("tutorial", "done", [])
		s.graphics = cfg.get_value("graphics", "quality", "")
		if s.graphics == "":
			s.pick_graphics()   # saved before there was a Graphics setting
	else:
		s.detect()
	return s


## First run: pick a window that suits the screen the game opened on.
func detect() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen).size
	mode = "Maximized"
	pick_graphics()
	detected = true
	# The biggest 16:9 size that fits, for when they switch to windowed.
	size = SIZES[0]
	for sz in SIZES:
		if sz.x <= usable.x and sz.y <= usable.y - 40:
			size = sz
	ui_scale = 1.0


## Picks Graphics (and Fog to match) for this computer: High on a separate
## graphics card, Low on built-in (integrated) graphics, in a browser, or when
## it can't tell.
func pick_graphics() -> void:
	var t := RenderingServer.get_video_adapter_type()
	graphics = "High" if t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU and not OS.has_feature("web") else "Low"
	fog = {"High": "High", "Medium": "Medium", "Low": "Low", "Very Low": "Low"}[graphics]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", mode)
	cfg.set_value("display", "size", size)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("graphics", "fog", fog)
	cfg.set_value("graphics", "quality", graphics)
	cfg.set_value("tutorial", "on", tutorial)
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.save(path)


## Window sizes that fit on the current screen.
static func sizes_that_fit() -> Array:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var out: Array = []
	for sz in SIZES:
		if sz.x <= usable.x and sz.y <= usable.y:
			out.append(sz)
	if out.is_empty():
		out.append(SIZES[0])
	return out


## Applies the settings to the game window. The interface is drawn for a
## 1600 x 900 screen and stretched to fit the window, so a bigger window means
## bigger text too; ui_scale nudges it from there.
func apply(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return   # in a browser the page owns the window
	var win := tree.root
	match mode:
		"Fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"Maximized":
			# Fill the usable screen first, in case the system can't maximise.
			var r := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(r.size)
			DisplayServer.window_set_position(r.position)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(size)
			var screen := DisplayServer.window_get_current_screen()
			var r := DisplayServer.screen_get_usable_rect(screen)
			DisplayServer.window_set_position(r.position + (r.size - size) / 2)
	win.content_scale_factor = ui_scale
