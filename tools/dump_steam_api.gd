extends SceneTree
## Dev tool: prints the GodotSteam API actually exposed by the loaded GDExtension
## (methods + signals matching a filter), and tries steamInitEx to see if Steam is running.
## Run: godot_console --headless --path . -s tools/dump_steam_api.gd [filter]

const FILTERS := ["init", "isSteamRunning", "run_callbacks", "P2P", "Lobby", "lobby", "Persona", "RichPresence", "Overlay", "Voice", "voice", "getSteamID", "LaunchCommandLine", "join_requested", "MessageToUser", "MessagesOnChannel", "Session", "getAppID", "restartApp"]


func _init() -> void:
	if not Engine.has_singleton("Steam"):
		print("NO Steam singleton")
		quit()
		return
	var steam := Engine.get_singleton("Steam")
	print("Steam class: %s" % steam.get_class())
	var methods := steam.get_method_list()
	methods.sort_custom(func(a, b): return String(a.name) < String(b.name))
	print("=== METHODS ===")
	for m in methods:
		var name := String(m.name)
		if not _match(name):
			continue
		var args: Array[String] = []
		for a in m.args:
			args.append("%s: %s" % [a.name, _type(a)])
		var defaults: Array = m.get("default_args", [])
		print("%s(%s) -> %s%s" % [name, ", ".join(args), _type(m["return"]), ("  defaults=" + str(defaults)) if not defaults.is_empty() else ""])
	print("=== SIGNALS ===")
	for s in steam.get_signal_list():
		var name := String(s.name)
		if not _match(name):
			continue
		var args: Array[String] = []
		for a in s.args:
			args.append("%s: %s" % [a.name, _type(a)])
		print("signal %s(%s)" % [name, ", ".join(args)])
	print("=== CONSTANTS (subset) ===")
	for c in ["P2P_SEND_UNRELIABLE", "P2P_SEND_UNRELIABLE_NO_DELAY", "P2P_SEND_RELIABLE", "P2P_SEND_RELIABLE_WITH_BUFFERING", "LOBBY_TYPE_PRIVATE", "LOBBY_TYPE_FRIENDS_ONLY", "LOBBY_TYPE_PUBLIC", "CHAT_MEMBER_STATE_CHANGE_ENTERED", "CHAT_MEMBER_STATE_CHANGE_LEFT", "CHAT_MEMBER_STATE_CHANGE_DISCONNECTED", "CHAT_ROOM_ENTER_RESPONSE_SUCCESS", "VOICE_RESULT_OK", "VOICE_RESULT_NO_DATA", "VOICE_RESULT_NOT_RECORDING", "STEAM_API_INIT_RESULT_OK", "NETWORKING_SEND_RELIABLE", "NETWORKING_SEND_UNRELIABLE"]:
		var v = steam.get(c)
		print("%s = %s" % [c, str(v)])
	print("=== INIT ===")
	if steam.has_method("steamInitEx"):
		var res = steam.call("steamInitEx", 480, true)
		print("steamInitEx(480, true) -> %s" % str(res))
		if typeof(res) == TYPE_DICTIONARY and int(res.get("status", -1)) == 0:
			print("persona=%s steam_id=%s" % [str(steam.call("getPersonaName")), str(steam.call("getSteamID"))])
	print("isSteamRunning=%s" % str(steam.call("isSteamRunning")))
	quit()


func _match(name: String) -> bool:
	for f in FILTERS:
		if f in name:
			return true
	return false


func _type(a: Dictionary) -> String:
	var t := int(a.get("type", 0))
	var cls := String(a.get("class_name", ""))
	if cls != "":
		return cls
	return type_string(t)
