extends SceneTree
## Dev tool: synthesizes every sound effect and the lobby music loop into assets/sfx and
## assets/music as 16-bit WAV. Cartoony, tiny, no samples needed.
## Run: godot_console --headless --path . -s tools/gen_sfx.gd

const RATE := 22050
const SFX_DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MUSIC_DIR))
	_save("postit_stick", _squeak())
	_save("jump", _boing())
	_save("ui_click", _click())
	_save("ui_confirm", _confirm())
	_save("vote", _tick())
	_save("ding_yes", _ding(880.0, 1320.0))
	_save("ding_no", _buzz())
	_save("confetti", _confetti())
	_save("countdown", _countdown())
	_save("emote_0", _whistle())
	_save("emote_1", _laugh())
	_save("emote_2", _slap())
	_save("bonk", _bonk())
	_save("chair", _creak())
	_save_music("lobby_loop", _music_loop())
	print("sfx generated")
	quit()


# --------------------------------------------------------------- synthesis

func _env(t: float, attack: float, decay: float, total: float) -> float:
	if t < attack:
		return t / attack
	var d := (t - attack) / maxf(0.0001, total - attack)
	return pow(1.0 - clampf(d, 0.0, 1.0), decay)


func _render(seconds: float, fn: Callable) -> PackedFloat32Array:
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = clampf(fn.call(float(i) / RATE), -1.0, 1.0)
	return out


func _squeak() -> PackedFloat32Array:
	return _render(0.28, func(t: float):
		var f := 1400.0 + 900.0 * sin(t * 40.0) + 600.0 * t
		return sin(TAU * f * t) * 0.5 * _env(t, 0.01, 1.5, 0.28))


func _boing() -> PackedFloat32Array:
	return _render(0.45, func(t: float):
		var f := 220.0 + 260.0 * exp(-t * 6.0) * sin(t * 50.0)
		return (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * 0.45 * _env(t, 0.005, 1.2, 0.45))


func _click() -> PackedFloat32Array:
	return _render(0.07, func(t: float): return sin(TAU * 900.0 * t) * 0.5 * _env(t, 0.002, 3.0, 0.07))


func _confirm() -> PackedFloat32Array:
	return _render(0.35, func(t: float):
		var f := 660.0 if t < 0.12 else 990.0
		return sin(TAU * f * t) * 0.45 * _env(t, 0.005, 1.5, 0.35))


func _tick() -> PackedFloat32Array:
	return _render(0.05, func(t: float): return (randf() * 2.0 - 1.0) * 0.4 * _env(t, 0.001, 4.0, 0.05))


func _ding(f1: float, f2: float) -> PackedFloat32Array:
	return _render(0.6, func(t: float): return (sin(TAU * f1 * t) * 0.35 + sin(TAU * f2 * t) * 0.25) * _env(t, 0.003, 2.0, 0.6))


func _buzz() -> PackedFloat32Array:
	return _render(0.45, func(t: float):
		var sq := 1.0 if fmod(t * 110.0, 1.0) < 0.5 else -1.0
		return sq * 0.3 * _env(t, 0.01, 1.0, 0.45) * (1.0 if fmod(t, 0.15) < 0.1 else 0.0))


func _confetti() -> PackedFloat32Array:
	return _render(1.2, func(t: float):
		var v := 0.0
		for k in 5:
			var start := k * 0.12
			if t >= start:
				var lt := t - start
				var f := 660.0 * pow(1.2, k)
				v += sin(TAU * f * lt) * 0.18 * _env(lt, 0.003, 2.5, 0.5)
		return v + (randf() * 2.0 - 1.0) * 0.08 * _env(t, 0.01, 1.0, 1.2))


func _countdown() -> PackedFloat32Array:
	return _render(0.25, func(t: float): return sin(TAU * 523.0 * t) * 0.4 * _env(t, 0.005, 2.0, 0.25))


func _whistle() -> PackedFloat32Array:
	return _render(0.5, func(t: float):
		var f := 900.0 + 500.0 * sin(t * 12.0)
		return sin(TAU * f * t) * 0.35 * _env(t, 0.02, 1.0, 0.5))


func _laugh() -> PackedFloat32Array:
	return _render(0.9, func(t: float):
		var pulse := 1.0 if fmod(t * 7.0, 1.0) < 0.45 else 0.2
		var f := 330.0 - 60.0 * t
		return (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.01 * t)) * 0.3 * pulse * _env(t, 0.02, 1.0, 0.9))


func _slap() -> PackedFloat32Array:
	return _render(0.18, func(t: float): return (randf() * 2.0 - 1.0) * 0.6 * _env(t, 0.001, 3.5, 0.18))


func _bonk() -> PackedFloat32Array:
	return _render(0.3, func(t: float):
		var f := 160.0 * exp(-t * 4.0) + 60.0
		return sin(TAU * f * t) * 0.6 * _env(t, 0.002, 2.0, 0.3))


func _creak() -> PackedFloat32Array:
	return _render(0.35, func(t: float):
		var f := 300.0 + 200.0 * sin(t * 30.0)
		var sq := 1.0 if fmod(t * f, 1.0) < 0.3 else -1.0
		return sq * 0.15 * _env(t, 0.02, 1.0, 0.35))


## Plucked-string loop (Karplus-Strong), 8 bars, ukulele-ish, C-G-Am-F.
func _music_loop() -> PackedFloat32Array:
	var bpm := 108.0
	var beat := 60.0 / bpm
	var bars := 8
	var total := beat * 4.0 * bars
	var n := int(RATE * total)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords := [[261.63, 329.63, 392.0, 523.25], [196.0, 246.94, 293.66, 392.0], [220.0, 261.63, 329.63, 440.0], [174.61, 220.0, 261.63, 349.23]]
	var pattern := [0, 2, 1, 3, 0, 2, 1, 3]   # eighth-note strum order within a beat
	var step := beat / 2.0
	var steps := int(total / step)
	for s in steps:
		var bar := int(floor(s * step / (beat * 4.0)))
		var chord: Array = chords[bar % 4]
		var note_idx: int = pattern[s % pattern.size()]
		var f: float = chord[note_idx]
		if s % 8 == 7:
			f = chord[0] * 2.0
		_pluck(out, int(s * step * RATE), f, 0.9 if s % 2 == 0 else 0.6)
	# gentle bass on beats
	for b in int(total / beat):
		var chord: Array = chords[int(floor(b / 4.0)) % 4]
		_pluck(out, int(b * beat * RATE), float(chord[0]) / 2.0, 0.5)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		for i in n:
			out[i] = out[i] / peak * 0.6
	return out


func _pluck(buf: PackedFloat32Array, start: int, freq: float, gain: float) -> void:
	var period := int(RATE / freq)
	if period < 2:
		return
	var ring := PackedFloat32Array()
	ring.resize(period)
	for i in period:
		ring[i] = randf() * 2.0 - 1.0
	var length := mini(int(RATE * 1.4), buf.size() - start)
	var idx := 0
	for i in length:
		var v := ring[idx]
		var nxt := ring[(idx + 1) % period]
		ring[idx] = (v + nxt) * 0.5 * 0.996
		buf[start + i] += v * gain * 0.35
		idx = (idx + 1) % period


# ------------------------------------------------------------------ output

func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _save(name: String, samples: PackedFloat32Array) -> void:
	var wav := _to_wav(samples)
	var err := wav.save_to_wav(SFX_DIR + name + ".wav")
	print("%s.wav %s (%d samples)" % [name, "ok" if err == OK else error_string(err), samples.size()])


func _save_music(name: String, samples: PackedFloat32Array) -> void:
	var wav := _to_wav(samples, true)
	var err := wav.save_to_wav(MUSIC_DIR + name + ".wav")
	print("%s.wav %s (%.1f s)" % [name, "ok" if err == OK else error_string(err), samples.size() / float(RATE)])
