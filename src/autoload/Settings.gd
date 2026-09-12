extends Node
## Local, per-machine settings (user://settings.cfg) plus parsed command-line flags.
## Never synced to other players. The optional Google key lives here and nowhere else.

const SETTINGS_PATH := "user://settings.cfg"

signal changed

## Command-line flags parsed from OS.get_cmdline_user_args() (everything after "--").
var cli: Dictionary = {
	"host": false,
	"join": "",
	"port": 7777,
	"name": "",
	"bot": false,
	"no_steam": false,
	"screenshot_dir": "",
	"settings_path": "",
	"quit_after": 0.0,
	"window_pos": Vector2i(-1, -1),
	"fast": false,
	"rejoin_token": "",
}

var data: Dictionary = {
	"player_name": "",
	"mouse_sensitivity": 0.0025,
	"invert_y": false,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 0.6,
	"voice_volume": 1.0,
	"voice_mode": "ptt",          # "ptt" | "open"
	"mic_gate": 0.03,
	"wiki_lang": "en",
	"google_api_key": "",
	"google_cx": "",
	"third_person": false,
	"first_launch": true,
	"rejoin_token": "",
}


func _ready() -> void:
	_parse_cli()
	load_settings()


func _parse_cli() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var next: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--host":
				cli.host = true
			"--join":
				cli.join = next if next != "" else "127.0.0.1"
				i += 1
			"--port":
				cli.port = int(next)
				i += 1
			"--name":
				cli.name = next
				i += 1
			"--bot":
				cli.bot = true
			"--no-steam":
				cli.no_steam = true
			"--fast":
				cli.fast = true
			"--rejoin-token":
				cli.rejoin_token = next
				i += 1
			"--screenshot-dir":
				cli.screenshot_dir = next
				i += 1
			"--settings":
				cli.settings_path = next
				i += 1
			"--quit-after":
				cli.quit_after = float(next)
				i += 1
			"--window-pos":
				var parts := next.split(",")
				if parts.size() == 2:
					cli.window_pos = Vector2i(int(parts[0]), int(parts[1]))
				i += 1
		i += 1


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in data.keys():
			data[key] = cfg.get_value("settings", key, data[key])
	if cli.name != "":
		data.player_name = cli.name
	if data.player_name == "":
		data.player_name = "Player%d" % (randi() % 900 + 100)
	if String(cli.rejoin_token) != "":
		data.rejoin_token = cli.rejoin_token   # dev: relaunch with the same token to test rejoin
	elif String(data.rejoin_token) == "" or cli.bot:
		# Random per install (bots: per process, so several bots on one PC do not collide).
		var crypto := Crypto.new()
		data.rejoin_token = crypto.generate_random_bytes(16).hex_encode()
		if not cli.bot:
			save_settings()
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("settings", key, data[key])
	cfg.save(SETTINGS_PATH)
	changed.emit()


func get_value(key: String, default = null):
	return data.get(key, default)


func set_value(key: String, value) -> void:
	data[key] = value
	save_settings()


func player_name() -> String:
	return String(data.player_name)
