# Procedural sound effects, built once at startup so the project needs no audio files.
extends Node

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var last_played := {}
var muted := false
var _next := 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams["gun"] = _shot(0.12, 0.55, 900.0)
	streams["smg"] = _shot(0.07, 0.35, 1400.0)
	streams["shotgun"] = _shot(0.28, 0.8, 500.0)
	streams["rifle"] = _shot(0.3, 0.75, 700.0)
	streams["launch"] = _thump(0.18, 140.0, 0.5)
	streams["boom"] = _boom(0.9)
	streams["hit"] = _thump(0.09, 90.0, 0.45)
	streams["die"] = _squelch()
	streams["groan"] = _groan()
	streams["crash"] = _boom(1.6)
	streams["fire"] = _crackle()
	streams["build"] = _tones([220.0, 330.0], 0.07, 0.25)
	streams["coin"] = _tones([660.0, 990.0], 0.06, 0.2)
	streams["levelup"] = _tones([392.0, 523.0, 659.0, 784.0], 0.09, 0.25)
	streams["horn"] = _horn()


func play(sname: String) -> void:
	if muted or not streams.has(sname):
		return
	var now := Time.get_ticks_msec()
	var gap := 45 if sname in ["smg", "hit", "die"] else 20
	if now - int(last_played.get(sname, -1000)) < gap:
		return
	last_played[sname] = now
	var p := players[_next]
	_next = (_next + 1) % players.size()
	p.stream = streams[sname]
	p.volume_db = -6.0 if sname in ["smg", "hit"] else -3.0
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


# --- Synthesis --------------------------------------------------------------
func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _env(t: float, dur: float, attack := 0.004) -> float:
	if t < attack:
		return t / attack
	return pow(maxf(0.0, 1.0 - (t - attack) / (dur - attack)), 2.2)


# A gunshot: a sharp noise crack through a falling low-pass filter plus a low thump.
func _shot(dur: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var c := cutoff * (1.0 - t / dur) + 120.0
		var a := clampf(TAU * c / RATE, 0.0, 1.0)
		lp += (randf_range(-1, 1) - lp) * a
		var thump := sin(TAU * 70.0 * t) * exp(-t * 30.0)
		out[i] = (lp * 2.2 + thump * 0.6) * _env(t, dur, 0.001) * vol
	return _make(out)


func _thump(dur: float, freq: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * freq * (1.0 - t / dur * 0.6) / RATE
		out[i] = (sin(ph) + randf_range(-0.3, 0.3)) * _env(t, dur, 0.002) * vol
	return _make(out)


func _boom(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.06
		var low := sin(TAU * (55.0 - 25.0 * t / dur) * t)
		out[i] = (lp * 3.0 + low * 0.7) * _env(t, dur, 0.003) * 0.9
	return _make(out)


func _squelch() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.12
		out[i] = (lp * 2.0 + sin(TAU * (180.0 - 400.0 * t) * t) * 0.4) * _env(t, dur, 0.01) * 0.5
	return _make(out)


func _groan() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 85.0 + sin(t * 7.0) * 8.0 - t * 20.0
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		lp += (saw - lp) * 0.08
		var e := sin(PI * t / dur)
		out[i] = lp * e * 0.35
	return _make(out)


func _crackle() -> AudioStreamWAV:
	var dur := 0.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.2
		var pop := randf_range(-1, 1) if randf() < 0.004 else 0.0
		out[i] = (lp * 0.8 + pop) * _env(t, dur, 0.05) * 0.5
	return _make(out)


func _tones(freqs: Array, each: float, vol: float) -> AudioStreamWAV:
	var n := int(each * freqs.size() * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var k := mini(int(t / each), freqs.size() - 1)
		var lt := t - k * each
		var f: float = freqs[k]
		out[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * _env(lt, each, 0.005) * vol
	return _make(out)


func _horn() -> AudioStreamWAV:
	var dur := 1.4
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += (110.0 + sin(t * 5.0) * 2.0) / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		var e := minf(1.0, t / 0.15) * minf(1.0, (dur - t) / 0.4)
		out[i] = (saw * 0.5 + sin(TAU * ph) * 0.5) * e * 0.4
	return _make(out)
