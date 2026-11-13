# Co-op over the network: one player hosts (their game is the real one), up
# to three friends join. The host sends everyone the whole state of the game
# SNAPSHOT_HZ times a second (compressed), plus the moments worth seeing or
# hearing as they happen (toasts, sounds, a wall giving way...). A friend's
# game is a copy that only shows what the host sends, smoothed between
# snapshots; what they do (aim, shoot, walk, click) goes to the host, which
# does it in the real game.
#
# The connection itself is swappable: ENet (an IP address and a port) works
# everywhere now; on Steam the same thing runs over Steam's networking with
# invites (SteamMultiplayerPeer, from the GodotSteam add-on) once the game has
# its Steam app ID: see host() and join().
#
# Grit is the team's: the host's camp is the one everyone spends from, and
# its upgrades apply to every player.
extends Node

const PORT := 24565
const MAX_FRIENDS := 3
const SNAPSHOT_HZ := 15.0
## What a snapshot leaves out: the friends' own copies make these themselves
## (particles), or they don't matter on a screen (the director's counters).
const SKIP := ["parts", "texts", "tracers", "spawn_acc", "horde_acc", "_cycle_done", "_repair_debt", "input_aim", "input_firing", "inputs", "input_auto", "death_mul"]
## The game's signals a friend's copy replays as the host's fire them.
const EVENTS := ["toast", "sound", "zombie_died", "exploded", "wall_breached", "wall_patched", "side_opened",
	"turret_destroyed", "new_day", "level_started", "truck_coming", "survivor_arrived", "trip_returned", "run_won", "inv_changed"]

signal status(text: String)          # for the lobby screen
signal joined                        # a friend: the host has taken us in

var main
var peer: MultiplayerPeer = null
var names := {}                      # peer id -> player name
var _send_t := 0.0
var _prev := {}                      # (friends) the last two snapshots' positions, to smooth between
var _cur := {}
var _cur_t := 0.0
var _gap := 1.0 / SNAPSHOT_HZ


func active() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return active() and multiplayer.is_server()


func is_friend() -> bool:
	return active() and not multiplayer.is_server()


func my_peer() -> int:
	return multiplayer.get_unique_id() if active() else 1


# --- Connecting ----------------------------------------------------------------
func host(pname := "You") -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, MAX_FRIENDS)
	if err != OK:
		return "Couldn't host (port %d busy?)" % PORT
	_use(p)
	names[1] = pname
	status.emit("Hosting. Friends join with your address, port %d." % PORT)
	return ""


func join(address: String, pname := "Friend") -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address.strip_edges(), PORT)
	if err != OK:
		return "Couldn't reach %s" % address
	_use(p)
	names[0] = pname
	status.emit("Joining %s..." % address)
	return ""


func leave() -> void:
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null
	names.clear()


func _use(p: MultiplayerPeer) -> void:
	peer = p
	multiplayer.multiplayer_peer = p
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(func(): status.emit("Couldn't connect."); leave())
		multiplayer.server_disconnected.connect(func(): status.emit("The host left."); leave(); main.host_left())


func _on_connected() -> void:
	_hello.rpc_id(1, names.get(0, "Friend"))


func _on_peer_connected(_id: int) -> void:
	pass   # they introduce themselves (_hello)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		main.game.remove_player(id)
		main.hud.toast("%s left." % names.get(id, "A friend"), "info")
		names.erase(id)


## A friend says hello: they get a character in the run.
@rpc("any_peer", "reliable")
func _hello(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var n := 1
	for k in names:
		n += 1
	if n > MAX_FRIENDS + 1:
		return
	names[id] = pname
	if main.game.me(id) == null:
		main.game.add_player(id, pname)
	main.hud.toast("%s joined." % pname, "good")
	_welcome.rpc_id(id)


@rpc("authority", "reliable")
func _welcome() -> void:
	status.emit("Joined.")
	joined.emit()


# --- Host: sending the game ---------------------------------------------------
## Called by main every frame while hosting.
func host_tick(dt: float) -> void:
	_send_t += dt
	if _send_t < _gap:
		return
	_send_t = 0.0
	var data: Dictionary = main.game.to_save()
	for k in SKIP:
		data.erase(k)
	data["bullets"] = main.game.bullets
	data["_started"] = main.started
	data["_paused"] = main.paused
	data["_grit"] = {"grit": main.progress.grit, "levels": main.progress.levels, "heat": main.progress.heat, "reached": main.progress.reached}
	var bytes := var_to_bytes(data)
	var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	_snapshot.rpc(packed, bytes.size())


## Wires the host's game so its moments go out to the friends.
func bind_host(g) -> void:
	for ev in EVENTS:
		var e: String = ev
		g.connect(e, func(a = null, b = null, c = null):
			if is_host():
				_event.rpc(e, [a, b, c]))


@rpc("authority", "unreliable_ordered")
func _snapshot(packed: PackedByteArray, size: int) -> void:
	var data = bytes_to_var(packed.decompress(size, FileAccess.COMPRESSION_ZSTD))
	if not data is Dictionary:
		return
	var g = main.game
	_prev = _cur
	_cur = _positions(data)
	_gap = clampf(Time.get_ticks_msec() / 1000.0 - _cur_t, 0.03, 0.3) if _cur_t > 0.0 else 1.0 / SNAPSHOT_HZ
	_cur_t = Time.get_ticks_msec() / 1000.0
	var grit: Dictionary = data["_grit"]
	main.progress.grit = grit["grit"]
	main.progress.levels = grit["levels"]
	main.progress.heat = grit["heat"]
	main.progress.reached = grit["reached"]
	var bullets: Array = data["bullets"]
	for k in ["_grit", "_started", "_paused", "bullets"]:
		data.erase(k)
	var mine = g.me(my_peer())
	var here = Vector2(mine["x"], mine["y"]) if mine != null else null
	g.from_save(data)
	g.bullets = bullets
	# You: where you've walked to here, unless the host has you somewhere else.
	mine = g.me(my_peer())
	if mine != null and here != null and here.distance_to(Vector2(mine["x"], mine["y"])) < 1.2:
		mine["x"] = here.x
		mine["y"] = here.y
	if not main.started and data.get("time", 0.0) >= 0.0:
		main.friend_started()


@rpc("authority", "reliable")
func _event(name: String, args: Array) -> void:
	var g = main.game
	var n: int = g.get_signal_list().filter(func(s): return s["name"] == name)[0]["args"].size()
	g.callv("emit_signal", [name] + args.slice(0, n))


## (Friends) where everyone is, by id: to smooth between snapshots.
static func _positions(data: Dictionary) -> Dictionary:
	var out := {}
	for z in data.get("zombies", []):
		out["z%d" % z["id"]] = Vector2(z["x"], z["y"])
	for c in data.get("crew", []):
		out["c%d" % c["id"]] = Vector2(c["x"], c["y"])
	return out


## (Friends) every frame: slide the dead and the crew from where they were
## in the last snapshot to where they are in this one.
func smooth() -> void:
	if _prev.is_empty():
		return
	var t := clampf((Time.get_ticks_msec() / 1000.0 - _cur_t) / _gap, 0.0, 1.0)
	var g = main.game
	for z in g.zombies:
		var k := "z%d" % z["id"]
		if _prev.has(k) and _cur.has(k):
			var p: Vector2 = _prev[k].lerp(_cur[k], t)
			z["x"] = p.x
			z["y"] = p.y
	for c in g.crew:
		if c.get("peer", -1) == my_peer():
			continue   # you: as you walk (see main)
		var k := "c%d" % c["id"]
		if _prev.has(k) and _cur.has(k):
			var p: Vector2 = _prev[k].lerp(_cur[k], t)
			c["x"] = p.x
			c["y"] = p.y


# --- Friends: sending what we do ------------------------------------------------
## Called by main every frame while joined: our aim, trigger and walking.
func friend_tick(aim, firing: bool, walk: Vector2, dt: float) -> void:
	_friend_input.rpc_id(1, aim if aim != null else Vector2.INF, firing, walk, dt)


@rpc("any_peer", "unreliable_ordered")
func _friend_input(aim: Vector2, firing: bool, walk: Vector2, dt: float) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	main.game.inputs[id] = {"aim": null if aim == Vector2.INF else aim, "firing": firing}
	if walk != Vector2.ZERO:
		main.game.walk_player(walk, clampf(dt, 0.0, 0.05), id)


## Something a friend did (moved someone, bought something, ...): the host does it.
func send_action(method: String, args: Array) -> void:
	_action.rpc_id(1, method, args)


## What a friend may ask the host's game to do.
const ACTIONS := ["move_survivor", "move_survivor_to", "toggle_repair", "repair_turret", "board_truck", "board_all",
	"buy", "build", "start_research", "send_scavenger", "place_trap", "move_trap", "pick_up_trap", "throw_item",
	"use_supply", "salvage", "start_reload_peer", "camp_buy", "move_item"]


@rpc("any_peer", "reliable")
func _action(method: String, args: Array) -> void:
	if not multiplayer.is_server() or not method in ACTIONS:
		return
	var id := multiplayer.get_remote_sender_id()
	var r = main.do_action(method, args, id)
	if r is Dictionary and r.get("msg", "") != "":
		_reply.rpc_id(id, r["msg"], r.has("ok"))


@rpc("authority", "reliable")
func _reply(msg: String, ok: bool) -> void:
	main.hud.toast(msg, "info" if ok else "danger")
