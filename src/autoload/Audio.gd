extends Node
## Sound effects and music. Streams are registered by name; missing names fail silently
## so gameplay code can call Audio.play("postit_stick") before the asset exists.

const SFX_DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"

var _sfx: Dictionary = {}
var _music_player: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
const POOL_SIZE := 12


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_scan(SFX_DIR)
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and (f.ends_with(".wav") or f.ends_with(".ogg") or f.ends_with(".mp3")):
			var stream := load(dir_path + f)
			if stream:
				_sfx[f.get_basename()] = stream
		f = dir.get_next()


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(Settings.get_value("master_volume", 1.0)), 0.0001, 1.0)))
	_music_player.volume_db = linear_to_db(clampf(float(Settings.get_value("music_volume", 0.6)), 0.0001, 1.0))


## Play a 2D (non-positional) sound effect by name.
func play(name: String, pitch_jitter: float = 0.08) -> void:
	var stream: AudioStream = _sfx.get(name)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.volume_db = linear_to_db(clampf(float(Settings.get_value("sfx_volume", 1.0)), 0.0001, 1.0))
			p.play()
			return


## Play a positional sound at a 3D location (spawns a temporary AudioStreamPlayer3D).
func play_at(name: String, position: Vector3, parent: Node = null) -> void:
	var stream: AudioStream = _sfx.get(name)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-0.08, 0.08)
	p.unit_size = 6.0
	p.volume_db = linear_to_db(clampf(float(Settings.get_value("sfx_volume", 1.0)), 0.0001, 1.0))
	(parent if parent else get_tree().current_scene).add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()


func play_music(file_name: String) -> void:
	var path := MUSIC_DIR + file_name
	if not ResourceLoader.exists(path):
		return
	var stream := load(path)
	if _music_player.stream == stream and _music_player.playing:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func has(name: String) -> bool:
	return _sfx.has(name)
