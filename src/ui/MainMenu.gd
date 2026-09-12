extends Control
## Main menu: host or join. Steam buttons light up when SteamTransport is available (M6).

signal howto_requested
signal options_requested

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var how_button: Button = %HowButton
@onready var steam_host_button: Button = %SteamHostButton
@onready var steam_label: Label = %SteamLabel


func _ready() -> void:
	name_edit.text = Settings.player_name()
	name_edit.text_changed.connect(_on_name_changed)
	host_button.pressed.connect(_on_host)
	steam_host_button.pressed.connect(_on_host_steam)
	SteamService.initialized.connect(func(_ok): _refresh_steam())
	_refresh_steam()
	join_button.pressed.connect(_on_join)
	quit_button.pressed.connect(func(): get_tree().quit())
	how_button.pressed.connect(func(): howto_requested.emit())
	%OptionsButton.pressed.connect(func(): options_requested.emit())
	address_edit.text = "127.0.0.1"
	address_edit.text_submitted.connect(func(_t): _on_join())
	status_label.text = ""


func _on_name_changed(text: String) -> void:
	Settings.set_value("player_name", Game.sanitize_name(text) if text.strip_edges().length() >= Game.MIN_NAME else text)


func _on_host() -> void:
	_commit_name()
	show_status(tr("STATUS_HOSTING"))
	Net.host(Transport.KIND_ENET, int(Game.settings.max_players), {"port": Settings.cli.port})


func _refresh_steam() -> void:
	var ok := SteamService.available
	steam_host_button.visible = ok
	steam_label.text = Locale.f("MENU_STEAM_STATUS", {"name": SteamService.persona}) if ok else tr("MENU_STEAM_OFF")
	if ok and name_edit.text.strip_edges() == "":
		name_edit.text = Settings.player_name()


func _on_host_steam() -> void:
	_commit_name()
	show_status(tr("STATUS_HOSTING"))
	Net.host(Transport.KIND_STEAM, int(Game.settings.max_players), {"friends_only": bool(Game.settings.friends_only)})


func _on_join() -> void:
	_commit_name()
	show_status(tr("STATUS_CONNECTING"))
	var address := address_edit.text.strip_edges()
	# A bare number that is too long for a port is a Steam lobby id pasted from a friend.
	if address.is_valid_int() and address.length() >= 12:
		if not SteamService.available:
			show_status(tr("STATUS_STEAM_NEEDED"))
			return
		Net.join(Transport.KIND_STEAM, address, {})
		return
	Net.join(Transport.KIND_ENET, address, {"port": Settings.cli.port})


func _commit_name() -> void:
	var clean := Game.sanitize_name(name_edit.text)
	name_edit.text = clean
	Settings.set_value("player_name", clean)


func show_status(text: String) -> void:
	status_label.text = text
