extends Control
## Main menu: host or join. Steam buttons light up when SteamTransport is available (M6).

signal howto_requested

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var how_button: Button = %HowButton


func _ready() -> void:
	name_edit.text = Settings.player_name()
	name_edit.text_changed.connect(_on_name_changed)
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	quit_button.pressed.connect(func(): get_tree().quit())
	how_button.pressed.connect(func(): howto_requested.emit())
	address_edit.text = "127.0.0.1"
	address_edit.text_submitted.connect(func(_t): _on_join())
	status_label.text = ""


func _on_name_changed(text: String) -> void:
	Settings.set_value("player_name", Game.sanitize_name(text) if text.strip_edges().length() >= Game.MIN_NAME else text)


func _on_host() -> void:
	_commit_name()
	show_status(tr("STATUS_HOSTING"))
	Net.host(Transport.KIND_ENET, int(Game.settings.max_players), {"port": Settings.cli.port})


func _on_join() -> void:
	_commit_name()
	show_status(tr("STATUS_CONNECTING"))
	Net.join(Transport.KIND_ENET, address_edit.text.strip_edges(), {"port": Settings.cli.port})


func _commit_name() -> void:
	var clean := Game.sanitize_name(name_edit.text)
	name_edit.text = clean
	Settings.set_value("player_name", clean)


func show_status(text: String) -> void:
	status_label.text = text
