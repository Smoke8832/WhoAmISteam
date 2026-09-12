extends Node
## In-game voice. Two codecs share one pipeline:
##   codec 0 = Steam Voice (compressed by Steam, decoded with decompressVoice) in Steam rooms
##   codec 1 = raw PCM16 mono 16 kHz (Godot microphone capture) in LAN rooms and for bots
## Frames go sender -> host -> everyone else. Playback is positional at each speaker's head.
## Push-to-talk (T) or open mic with a level gate. Per-player mute is local.

signal speaking_changed(peer_id: int, speaking: bool)

const CODEC_STEAM := 0
const CODEC_PCM16 := 1
const PCM_RATE := 16000
const PCM_FRAME_S := 0.04   # 640 samples = 1280 bytes: stays under the ENet unreliable MTU
const MAX_FRAME_BYTES := 8 * 1024
const SPEAK_HOLD_S := 0.25

var enabled: bool = false            # mirrors LobbySettings.voice_enabled
var transmitting: bool = false
var muted: Dictionary = {}           # peer_id -> bool (local)
var _speaking: Dictionary = {}       # peer_id -> hold timer
var _levels: Dictionary = {}         # peer_id -> 0..1
var _players: Dictionary = {}        # peer_id -> AudioStreamPlayer3D / AudioStreamPlayer
var _playbacks: Dictionary = {}      # peer_id -> AudioStreamGeneratorPlayback
var _rates: Dictionary = {}          # peer_id -> mix rate of that generator

# capture (PCM path)
var _mic_player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _pcm_accum := PackedFloat32Array()
var _ptt_down := false
var _steam_recording := false
var _steam_rate := 48000


func _ready() -> void:
	Net.left.connect(_on_session_ended)
	Net.server_disconnected.connect(_on_session_ended)
	set_process(true)


func _on_session_ended() -> void:
	stop_capture()
	for p in _players.values():
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	_playbacks.clear()
	_rates.clear()
	_speaking.clear()
	_levels.clear()


# ---------------------------------------------------------------- control

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		stop_capture()


func is_speaking(peer_id: int) -> bool:
	return float(_speaking.get(peer_id, 0.0)) > 0.0


func level_of(peer_id: int) -> float:
	return float(_levels.get(peer_id, 0.0))


func set_muted(peer_id: int, value: bool) -> void:
	muted[peer_id] = value


func is_muted(peer_id: int) -> bool:
	return bool(muted.get(peer_id, false))


func uses_steam_codec() -> bool:
	return Net.is_steam_session() and SteamService.available


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("push_to_talk"):
		_ptt_down = true
	elif event.is_action_released("push_to_talk"):
		_ptt_down = false


func _process(delta: float) -> void:
	# speaking hold timers
	for id in _speaking.keys().duplicate():
		var t := float(_speaking[id]) - delta
		if t <= 0.0:
			_speaking.erase(id)
			_levels[id] = 0.0
			speaking_changed.emit(int(id), false)
		else:
			_speaking[id] = t
	if not Net.active or not enabled or Game.state == Game.State.MENU:
		if transmitting:
			stop_capture()
		return
	var want := _ptt_down if String(Settings.get_value("voice_mode", "ptt")) == "ptt" else true
	if Settings.cli.bot:
		want = false
	if want and not transmitting:
		start_capture()
	elif not want and transmitting:
		stop_capture()
	if transmitting:
		if uses_steam_codec():
			_pump_steam()
		else:
			_pump_pcm()


# ---------------------------------------------------------------- capture

func start_capture() -> void:
	if transmitting:
		return
	transmitting = true
	if uses_steam_codec():
		_steam_rate = int(SteamService.steam.call("getVoiceOptimalSampleRate"))
		SteamService.steam.call("startVoiceRecording")
		_steam_recording = true
	else:
		_ensure_mic()
		if _mic_player and not _mic_player.playing:
			_mic_player.play()
		if _capture:
			_capture.clear_buffer()


func stop_capture() -> void:
	if not transmitting:
		return
	transmitting = false
	if _steam_recording and SteamService.available:
		SteamService.steam.call("stopVoiceRecording")
		_steam_recording = false
	if _mic_player and _mic_player.playing:
		_mic_player.stop()
	_pcm_accum = PackedFloat32Array()


func _ensure_mic() -> void:
	if _mic_player:
		return
	var idx := AudioServer.get_bus_index("Record")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
		AudioServer.set_bus_mute(idx, true)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Record"
	add_child(_mic_player)


func _pump_steam() -> void:
	var s := SteamService.steam
	var avail = s.call("getAvailableVoice")
	if typeof(avail) != TYPE_DICTIONARY or int(avail.get("result", -1)) != 0:
		return
	var got = s.call("getVoice", MAX_FRAME_BYTES)
	if typeof(got) != TYPE_DICTIONARY or int(got.get("result", -1)) != 0:
		return
	var bytes: PackedByteArray = got.get("buffer", PackedByteArray())
	var written := int(got.get("written", bytes.size()))
	if written <= 0:
		return
	bytes = bytes.slice(0, mini(written, bytes.size()))
	_send(CODEC_STEAM, bytes)
	# Local level for the own mouth: decode a copy.
	var dec = s.call("decompressVoice", bytes, _steam_rate, 20480)
	if typeof(dec) == TYPE_DICTIONARY and int(dec.get("result", -1)) == 0:
		_mark_speaking(Game.local_id(), rms_of_pcm16(dec.get("uncompressed", PackedByteArray())))


func _pump_pcm() -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	var src_rate := AudioServer.get_mix_rate()
	var mono := downsample_mono(frames, src_rate, PCM_RATE)
	_pcm_accum.append_array(mono)
	var frame_len := int(PCM_RATE * PCM_FRAME_S)
	while _pcm_accum.size() >= frame_len:
		var chunk := _pcm_accum.slice(0, frame_len)
		_pcm_accum = _pcm_accum.slice(frame_len)
		var level := rms_of_floats(chunk)
		var open_mic := String(Settings.get_value("voice_mode", "ptt")) != "ptt"
		if open_mic and level < float(Settings.get_value("mic_gate", 0.03)):
			continue
		_send(CODEC_PCM16, pcm16_from_floats(chunk))
		_mark_speaking(Game.local_id(), level)


func _send(codec: int, bytes: PackedByteArray) -> void:
	if bytes.size() > MAX_FRAME_BYTES or bytes.is_empty():
		return
	if Net.is_host():
		_relay_from(Game.HOST_ID, codec, bytes)
	else:
		voice_frame.rpc_id(Game.HOST_ID, codec, bytes)


## Bots / tests: inject a synthetic PCM frame as if the mic produced it.
func send_test_tone(seconds: float = 0.06, freq: float = 440.0) -> void:
	var n := int(PCM_RATE * seconds)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in n:
		f[i] = sin(TAU * freq * i / PCM_RATE) * 0.5
	_send(CODEC_PCM16, pcm16_from_floats(f))
	_mark_speaking(Game.local_id(), 0.5)


# ------------------------------------------------------------------- RPCs

## Client -> Host (unreliable): a compressed/PCM frame from the sender's mic.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func voice_frame(codec: int, bytes: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not enabled or not Game.players.has(sender) or bytes.size() > MAX_FRAME_BYTES or bytes.is_empty():
		return
	if codec != CODEC_STEAM and codec != CODEC_PCM16:
		return
	_relay_from(sender, codec, bytes)


func _relay_from(sender: int, codec: int, bytes: PackedByteArray) -> void:
	for id in Game.connected_player_ids():
		if id == sender or id == Game.HOST_ID:
			continue
		voice_relay.rpc_id(id, sender, codec, bytes)
	if sender != Game.HOST_ID:
		_play(sender, codec, bytes)


## Host -> Client (unreliable): someone else's frame.
@rpc("authority", "call_remote", "unreliable_ordered")
func voice_relay(sender: int, codec: int, bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != Game.HOST_ID:
		return
	if not enabled or bytes.size() > MAX_FRAME_BYTES:
		return
	_play(sender, codec, bytes)


# ---------------------------------------------------------------- playback

func _play(sender: int, codec: int, bytes: PackedByteArray) -> void:
	if is_muted(sender):
		return
	var pcm := PackedByteArray()
	var rate := PCM_RATE
	if codec == CODEC_STEAM:
		if not SteamService.available:
			return
		rate = _steam_rate if _steam_rate > 0 else 48000
		var dec = SteamService.steam.call("decompressVoice", bytes, rate, 20480)
		if typeof(dec) != TYPE_DICTIONARY or int(dec.get("result", -1)) != 0:
			return
		pcm = dec.get("uncompressed", PackedByteArray())
	else:
		pcm = bytes
	if pcm.size() < 2:
		return
	_mark_speaking(sender, rms_of_pcm16(pcm))
	var pb := _playback_for(sender, rate)
	if pb == null:
		return
	var frames := floats_from_pcm16(pcm)
	var stereo := PackedVector2Array()
	stereo.resize(frames.size())
	for i in frames.size():
		stereo[i] = Vector2(frames[i], frames[i])
	if pb.can_push_buffer(stereo.size()):
		pb.push_buffer(stereo)


func _playback_for(peer_id: int, rate: int) -> AudioStreamGeneratorPlayback:
	if _players.has(peer_id) and is_instance_valid(_players[peer_id]) and int(_rates.get(peer_id, 0)) == rate:
		var p: Node = _players[peer_id]
		# Re-parent to the speaker's head if it exists now.
		_attach(p, peer_id)
		return _playbacks[peer_id]
	if _players.has(peer_id) and is_instance_valid(_players[peer_id]):
		_players[peer_id].queue_free()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.4
	var player := AudioStreamPlayer3D.new()
	player.stream = gen
	player.unit_size = 6.0
	player.max_distance = 30.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.volume_db = linear_to_db(clampf(float(Settings.get_value("voice_volume", 1.0)), 0.0001, 1.0))
	add_child(player)
	_attach(player, peer_id)
	player.play()
	_players[peer_id] = player
	_rates[peer_id] = rate
	_playbacks[peer_id] = player.get_stream_playback()
	return _playbacks[peer_id]


func _attach(player: Node, peer_id: int) -> void:
	var main := get_tree().current_scene
	var node: Node = main.player_node(peer_id) if main and main.has_method("player_node") else null
	if node and player.get_parent() != node:
		player.reparent(node, false)
		(player as Node3D).position = Vector3(0, 1.6, 0)


func _mark_speaking(peer_id: int, level: float) -> void:
	_levels[peer_id] = clampf(level * 4.0, 0.0, 1.0)
	var was := _speaking.has(peer_id)
	_speaking[peer_id] = SPEAK_HOLD_S
	if not was:
		speaking_changed.emit(peer_id, true)


# ------------------------------------------------------------ pure helpers

static func pcm16_from_floats(f: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(f.size() * 2)
	for i in f.size():
		var v := int(clampf(f[i], -1.0, 1.0) * 32767.0)
		out.encode_s16(i * 2, v)
	return out


static func floats_from_pcm16(b: PackedByteArray) -> PackedFloat32Array:
	var n := b.size() / 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(b.decode_s16(i * 2)) / 32768.0
	return out


static func rms_of_floats(f: PackedFloat32Array) -> float:
	if f.is_empty():
		return 0.0
	var acc := 0.0
	for v in f:
		acc += v * v
	return sqrt(acc / f.size())


static func rms_of_pcm16(b: PackedByteArray) -> float:
	return rms_of_floats(floats_from_pcm16(b))


## Stereo frames at src_rate -> mono floats at dst_rate (nearest-sample decimation with averaging).
static func downsample_mono(frames: PackedVector2Array, src_rate: float, dst_rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if frames.is_empty() or src_rate <= 0.0:
		return out
	var ratio := src_rate / float(dst_rate)
	var n := int(floor(frames.size() / ratio))
	out.resize(n)
	for i in n:
		var start := int(i * ratio)
		var end := mini(frames.size(), int((i + 1) * ratio))
		var acc := 0.0
		var cnt := 0
		for j in range(start, maxi(end, start + 1)):
			var v := frames[j]
			acc += (v.x + v.y) * 0.5
			cnt += 1
		out[i] = acc / maxf(1.0, cnt)
	return out
