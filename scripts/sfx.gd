# Procedural sound effects, built once at startup so the project needs no audio files.
# The zombies' voices (moans, snarls, death croaks) come from a small voice
# synthesiser, modelled on recordings of moaning actors; they take a moment to
# make, so they're built on a worker thread and join in when they're ready.
extends Node

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var last_played := {}
var muted := false
var _next := 0
var _voice_task := -1


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
	streams["crash"] = _boom(1.6)
	streams["fire"] = _crackle()
	streams["build"] = _tones([220.0, 330.0], 0.07, 0.25)
	streams["coin"] = _tones([660.0, 990.0], 0.06, 0.2)
	streams["levelup"] = _tones([392.0, 523.0, 659.0, 784.0], 0.09, 0.25)
	streams["horn"] = _horn()
	# Reloading: the magazine release clicks and the empty one slides out...
	streams["reload"] = _mech([[0.0, "click", 0.7], [0.025, "slide", 0.5], [0.11, "click", 0.35]])
	# ...then a fresh one is seated and the slide racked back and slammed home.
	streams["reloaded"] = _mech([[0.0, "clack", 0.8], [0.17, "slide", 0.55], [0.245, "clack", 1.0]])
	# Zombie voices: built in the background (see _build_voices). A web build
	# has no threads, so there they're built a moment after startup instead.
	if OS.has_feature("web"):
		_build_voices.call_deferred()
	else:
		_voice_task = WorkerThreadPool.add_task(_build_voices)


func _exit_tree() -> void:
	if _voice_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_voice_task)
		_voice_task = -1


## How long (ms) before the same sound can play again, so a horde doesn't
## turn into one wall of noise.
const GAPS := {"smg": 45, "hit": 45, "die": 45, "zdie": 160, "snarl": 220,
	"groan_walker": 350, "groan_runner": 450, "groan_brute": 900, "groan": 1500}
## Volume (dB) per sound; zombie voices vary around theirs, as if near or far.
const VOLUMES := {"smg": -6.0, "hit": -6.0, "zdie": -7.0, "snarl": -9.0,
	"groan_walker": -9.0, "groan_runner": -10.0, "groan_brute": -6.0, "groan": -4.0}


func play(sname: String) -> void:
	if muted or not streams.has(sname):
		return
	var now := Time.get_ticks_msec()
	var gap: int = GAPS.get(sname, 20)
	if now - int(last_played.get(sname, -100000)) < gap:
		return
	last_played[sname] = now
	var p := players[_next]
	_next = (_next + 1) % players.size()
	var st = streams[sname]
	var voice := st is Array
	p.stream = st[randi() % st.size()] if voice else st
	p.volume_db = VOLUMES.get(sname, -3.0) + (randf_range(-5.0, 1.0) if voice else 0.0)
	p.pitch_scale = randf_range(0.9, 1.1) if voice else randf_range(0.92, 1.08)
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
	return _make(_squelch_samples())


func _squelch_samples() -> PackedFloat32Array:
	var dur := 0.22
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.12
		out[i] = (lp * 2.0 + sin(TAU * (180.0 - 400.0 * t) * t) * 0.4) * _env(t, dur, 0.01) * 0.5
	return out


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


# Gun mechanics: metal-on-metal clicks and clacks (a burst of bright noise plus
# a few fast-dying inharmonic rings) and the scrape of a slide. events is a
# list of [start seconds, "click" | "clack" | "slide", loudness].
func _mech(events: Array) -> AudioStreamWAV:
	var dur := 0.0
	for e in events:
		dur = maxf(dur, e[0] + (0.1 if e[1] == "slide" else 0.09))
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for e in events:
		var start := int(e[0] * RATE)
		var kind: String = e[1]
		var vol: float = e[2]
		var lp := 0.0
		var len := int((0.1 if kind == "slide" else 0.09) * RATE)
		for k in len:
			var i := start + k
			if i >= n:
				break
			var t := float(k) / RATE
			var noise := randf_range(-1, 1)
			lp += (noise - lp) * 0.35
			var bright := noise - lp            # high-passed noise: the metallic tick
			var v := 0.0
			match kind:
				"click":
					v = bright * exp(-t * 900.0) * 1.2
					v += (sin(TAU * 3300.0 * t) * 0.5 + sin(TAU * 4900.0 * t) * 0.3) * exp(-t * 90.0)
				"clack":
					v = bright * exp(-t * 500.0) * 1.5
					v += (sin(TAU * 1650.0 * t) * 0.45 + sin(TAU * 2700.0 * t) * 0.35 + sin(TAU * 4100.0 * t) * 0.2) * exp(-t * 45.0)
					v += sin(TAU * 170.0 * t) * exp(-t * 60.0) * 0.6
				"slide":
					var e2 := sin(PI * clampf(t / 0.1, 0.0, 1.0))
					v = (bright * 0.6 + lp * 0.4) * e2 * 0.5
					v += sin(TAU * (900.0 + 1400.0 * t / 0.1) * t) * e2 * 0.08
			out[i] += v * vol * 0.55
	return _make(out)


# --- Zombie voices ------------------------------------------------------------
# A moan is a voice: a train of glottal pulses (with the jitter and shimmer of a
# ruined throat, period-doubling growl, and stretches of creaky "vocal fry"),
# plus breath noise, through three formant resonators that shape the vowel,
# from a closed-mouth "mm" opening to "uh", "oh" or "aah". The pitch rises and
# falls in an arch, low (around 90-140 Hz), with most of the sound below 1 kHz:
# a dark, muffled moan. Each set is a few takes, picked at random when played.

## Vowels as [F1, F2, F3] in Hz.
const MM := [300.0, 950.0, 2400.0]
const UH := [540.0, 1250.0, 2800.0]
const OH := [460.0, 900.0, 2600.0]
const AA := [720.0, 1300.0, 2800.0]


func _build_voices() -> void:
	var v := {}
	# Walkers: long shambling moans, a grunt, an anguished cry, a gurgle.
	v["groan_walker"] = [
		_moan({"dur": 1.7, "f0": 96.0, "rise": 1.35, "fall": 0.9, "to": UH, "rough": 0.3, "fry_at": 0.62, "fry_len": 0.3, "seed": 1}),
		_moan({"dur": 1.3, "f0": 106.0, "rise": 1.2, "fall": 0.85, "hum": 0.28, "to": OH, "rough": 0.2, "seed": 2}),
		_moan({"dur": 0.6, "f0": 92.0, "rise": 1.15, "fall": 0.8, "to": UH, "rough": 0.5, "seed": 3}),
		_moan({"dur": 1.0, "f0": 140.0, "rise": 1.22, "fall": 0.85, "to": AA, "rough": 0.25, "breath": 0.3, "seed": 4}),
		_moan({"dur": 1.25, "f0": 86.0, "rise": 1.1, "fall": 0.8, "to": UH, "rough": 0.65, "fry_at": 0.3, "fry_len": 0.5, "breath": 0.2, "seed": 5}),
		_moan({"dur": 1.6, "f0": 100.0, "rise": 1.3, "fall": 0.88, "hum": 0.15, "to": UH, "rough": 0.35, "dip": 0.38, "seed": 6}),
	]
	# Brutes: deeper, longer, rougher, from a bigger chest.
	v["groan_brute"] = [
		_moan({"dur": 2.0, "f0": 66.0, "rise": 1.3, "fall": 0.85, "to": UH, "rough": 0.55, "fry_at": 0.6, "fry_len": 0.35, "size": 0.82, "seed": 11}),
		_moan({"dur": 1.6, "f0": 72.0, "rise": 1.2, "fall": 0.8, "hum": 0.3, "to": OH, "rough": 0.45, "size": 0.8, "seed": 12}),
		_moan({"dur": 1.1, "f0": 62.0, "rise": 1.15, "fall": 0.75, "to": UH, "rough": 0.75, "fry_at": 0.4, "fry_len": 0.5, "size": 0.85, "seed": 13}),
	]
	# Runners: short, breathless and raspy.
	v["groan_runner"] = [
		_moan({"dur": 0.7, "f0": 135.0, "rise": 1.3, "fall": 0.85, "to": AA, "rough": 0.5, "breath": 0.55, "size": 1.12, "seed": 21}),
		_moan({"dur": 0.5, "f0": 150.0, "rise": 1.2, "fall": 0.8, "to": UH, "rough": 0.55, "breath": 0.5, "size": 1.12, "seed": 22}),
		_moan({"dur": 0.9, "f0": 125.0, "rise": 1.4, "fall": 0.9, "to": AA, "rough": 0.4, "breath": 0.45, "fry_at": 0.7, "fry_len": 0.25, "size": 1.1, "seed": 23}),
	]
	# Snarls, when they claw at the wall or at someone.
	v["snarl"] = [
		_moan({"dur": 0.4, "f0": 120.0, "rise": 1.25, "fall": 0.8, "hum": 0.0, "from": UH, "to": AA, "rough": 0.85, "breath": 0.55, "attack": 0.03, "seed": 31}),
		_moan({"dur": 0.32, "f0": 105.0, "rise": 1.3, "fall": 0.75, "hum": 0.0, "from": UH, "to": AA, "rough": 0.9, "breath": 0.6, "attack": 0.025, "seed": 32}),
		_moan({"dur": 0.45, "f0": 135.0, "rise": 1.15, "fall": 0.8, "hum": 0.0, "from": OH, "to": AA, "rough": 0.8, "breath": 0.5, "attack": 0.03, "seed": 33}),
	]
	# Dying: a choked croak that falls away into a gurgle, over the squelch.
	var squelch := _squelch_samples()
	v["zdie"] = []
	for k in 3:
		var croak := _moan_samples({"dur": 0.6 + k * 0.1, "f0": 105.0 - k * 10.0, "rise": 1.1, "fall": 0.55, "hum": 0.0, "from": UH, "to": MM,
			"rough": 0.6, "fry_at": 0.35, "fry_len": 0.65, "breath": 0.3, "attack": 0.02, "seed": 41 + k})
		v["zdie"].append(_make(_mix([[squelch, 0.0, 1.0], [croak, 0.02, 0.8]])))
	# Many voices far off in the dark, for the warning before a side opens.
	var parts := []
	var starts := [0.0, 0.35, 0.8, 1.2, 1.7]
	for k in starts.size():
		parts.append([_moan_samples({"dur": 1.6 + k * 0.15, "f0": 82.0 + k * 13.0, "rise": 1.3, "fall": 0.85, "hum": 0.2,
			"to": [UH, OH, AA][k % 3], "rough": 0.4, "fry_at": 0.6, "fry_len": 0.3, "seed": 51 + k}), starts[k], 0.6])
	v["groan"] = [_make(_lowpass(_mix(parts), 0.25))]
	_voices_ready.call_deferred(v)


func _voices_ready(v: Dictionary) -> void:
	for k in v:
		streams[k] = v[k]


func _moan(p: Dictionary) -> AudioStreamWAV:
	return _make(_moan_samples(p))


## One voice. p: dur (s), f0 (Hz), rise and fall (pitch at the peak and the
## end, relative to f0), from / to (vowels; "from" defaults to the closed "mm"),
## hum (s of closed mouth before it opens), rough (0-1: jitter, growl and
## grit), fry_at / fry_len (where creaky fry takes over, as fractions of the
## length), breath (0-1), dip (a catch in the voice at that fraction), size
## (vocal tract: below 1 is bigger and darker), attack (s), seed.
func _moan_samples(p: Dictionary) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = p.get("seed", 1)
	var dur: float = p["dur"]
	var f0: float = p["f0"]
	var rise: float = p.get("rise", 1.2)
	var fall: float = p.get("fall", 0.85)
	var from: Array = p.get("from", MM)
	var to: Array = p["to"]
	var hum: float = p.get("hum", 0.12)
	var rough: float = p.get("rough", 0.3)
	var fry_at: float = p.get("fry_at", 2.0)
	var fry_len: float = p.get("fry_len", 0.0)
	var breath: float = p.get("breath", 0.15)
	var dip: float = p.get("dip", -1.0)
	var size: float = p.get("size", 1.0)
	var attack: float = p.get("attack", minf(0.18, dur * 0.25))
	var peak := rng.randf_range(0.3, 0.45)
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# Glottal pulse state.
	var phase := 0.0
	var period_mul := 1.0
	var amp := 1.0
	var odd := false
	var g_prev := 0.0
	# Formant resonators: two past outputs each.
	var y1 := [0.0, 0.0, 0.0]
	var y2 := [0.0, 0.0, 0.0]
	var gains := [1.0, 2.6, 1.8]   # the higher resonators ring quieter: lift them
	var bws := [110.0, 160.0, 260.0]
	var lp := 0.0
	var grit := 0.0
	var hiss := 0.0
	var y_prev := 0.0
	var dc := 0.0
	var dc_out := 0.0
	var drift := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := t / dur
		# Pitch: an arch, with a slow wobble and a wandering drift.
		var f := f0
		if x < peak:
			f *= lerpf(1.0, rise, smoothstep(0.0, 1.0, x / peak))
		else:
			f *= lerpf(rise, fall, smoothstep(0.0, 1.0, (x - peak) / (1.0 - peak)))
		drift += (rng.randf_range(-1.0, 1.0) - drift) * 0.0008
		f *= 1.0 + sin(TAU * 4.5 * t) * 0.012 + drift * 0.08
		var fry := fry_len > 0.0 and x >= fry_at and x < fry_at + fry_len
		# The glottis: a new pulse each period, its length and strength jittered.
		phase += f / RATE / period_mul
		if phase >= 1.0:
			phase -= 1.0
			odd = not odd
			var jit := 0.025 + rough * 0.05
			period_mul = 1.0 + rng.randfn(0.0, jit)
			amp = 1.0 + rng.randfn(0.0, 0.08 + rough * 0.15)
			if rough > 0.0 and odd:
				amp *= 1.0 - rough * 0.45      # period doubling: a growl an octave down
			if fry:
				# Creak: slow, irregular, sharp pulses.
				period_mul = rng.randf_range(1.8, 3.2)
				amp = rng.randf_range(0.5, 1.3)
		var open := 0.35 if fry else 0.6
		var g := pow(sin(PI * phase / open), 2.0) if phase < open else 0.0
		var pulse := (g - g_prev) * 6.0 * amp       # the flow's slope: what the ear hears
		g_prev = g
		# Grit: rough, low-frequency amplitude noise.
		grit += (rng.randf_range(-1.0, 1.0) - grit) * 0.02
		pulse *= 1.0 + grit * rough * 2.5
		var noise := rng.randf_range(-1.0, 1.0) * (breath * 0.5 + (0.25 if fry else 0.0))
		var src := pulse + noise * (0.4 + g)
		# The vowel: closed "mm" for the hum, then opening, then drifting on.
		var open_t := clampf((t - hum) / 0.25, 0.0, 1.0) if hum > 0.0 else 1.0
		var shape := smoothstep(0.0, 1.0, open_t)
		var close_end := smoothstep(0.75, 1.0, x) * 0.35   # the mouth sags shut at the end
		var y := 0.0
		for k in 3:
			var fk: float = lerpf(from[k], to[k], shape)
			fk = lerpf(fk, MM[k], close_end) * size
			var r := exp(-PI * bws[k] / RATE)
			var c := 2.0 * r * cos(TAU * fk / RATE)
			var v: float = (1.0 - r) * src + c * y1[k] - r * r * y2[k]
			y2[k] = y1[k]
			y1[k] = v
			y += v * gains[k]
		# A chest rumble under it: the low harmonics, which carry most of a moan.
		lp += (pulse - lp) * 0.06
		y += lp * 0.15
		# Breath on top: the hiss of air through a torn throat.
		hiss += (noise - hiss) * 0.3
		y += (noise - hiss) * 0.12 * (0.3 + breath)
		# Loudness: a swell up, follow the pitch a little, a catch, fade away.
		var e := smoothstep(0.0, 1.0, minf(1.0, t / attack))
		e *= pow(1.0 - smoothstep(0.55, 1.0, x), 1.3)
		e *= 0.75 + 0.25 * (f / (f0 * rise))
		if dip > 0.0:
			e *= 1.0 - 0.8 * exp(-pow((x - dip) * 14.0, 2.0))
		y *= e
		# Tilt toward the treble (the open mouth radiates the highs), remove DC,
		# then a soft clip for a strained throat.
		var tilted := y - 0.55 * y_prev
		y_prev = y
		dc_out = tilted - dc + 0.995 * dc_out
		dc = tilted
		out[i] = tanh(dc_out * (1.5 + rough))
	return _normalize(out, 0.8)


func _normalize(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for s in a:
		m = maxf(m, absf(s))
	for i in a.size():
		a[i] *= peak / m
	return a


## Layers sounds: parts are [samples, start (s), gain].
func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for pt in parts:
		n = maxi(n, int(pt[1] * RATE) + pt[0].size())
	var out := PackedFloat32Array()
	out.resize(n)
	for pt in parts:
		var s0 := int(pt[1] * RATE)
		var smp: PackedFloat32Array = pt[0]
		for i in smp.size():
			out[s0 + i] += smp[i] * pt[2]
	return _normalize(out, 0.85)


## One-pole low-pass (a: 0-1, smaller is darker): distance.
func _lowpass(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var lp := 0.0
	for i in a.size():
		lp += (a[i] - lp) * k
		a[i] = lp
	return _normalize(a, 0.8)
