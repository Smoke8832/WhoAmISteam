extends Control
## Writing phase: pick a name (and picture) for your target. Search Wikipedia, upload a file,
## or paste a URL. Preview shows the real post-it. Confirm sends it to the host.

signal closed

const INK := Color("1c1a17")
const CANDIDATE_LIMIT := 5

var target_peer: int = 0
var _search: ImageSearch
var _picture_bytes := PackedByteArray()
var _picture_tex: Texture2D = null
var _debounce: SceneTreeTimer = null
var _busy := false
var _confirmed := false
var _last_checked := ""

@onready var title: Label = %Title
@onready var name_edit: LineEdit = %NameEdit
@onready var lang_option: OptionButton = %LangOption
@onready var search_button: Button = %SearchButton
@onready var candidates: VBoxContainer = %Candidates
@onready var upload_button: Button = %UploadButton
@onready var url_edit: LineEdit = %UrlEdit
@onready var fetch_button: Button = %FetchButton
@onready var preview_pic: TextureRect = %PreviewPic
@onready var preview_name: Label = %PreviewName
@onready var preview_hint: Label = %PreviewHint
@onready var warning_label: Label = %Warning
@onready var status_label: Label = %Status
@onready var confirm_button: Button = %ConfirmButton
@onready var clear_button: Button = %ClearPicButton
@onready var timer_label: Label = %TimerLabel
@onready var file_dialog: FileDialog = %FileDialog


func _ready() -> void:
	_search = ImageSearch.new()
	add_child(_search)
	target_peer = RoundManager.target_of(Game.local_id())
	title.text = Locale.f("WRITE_TITLE", {"name": Game.player_name(target_peer)})
	for l in ImageSearch.WIKI_LANGS:
		lang_option.add_item(l.to_upper())
	var pref := String(Settings.get_value("wiki_lang", "en"))
	lang_option.selected = maxi(0, ImageSearch.WIKI_LANGS.find(pref))
	lang_option.item_selected.connect(func(i): Settings.set_value("wiki_lang", ImageSearch.WIKI_LANGS[i]))
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(func(_t): _do_search())
	search_button.pressed.connect(_do_search)
	upload_button.pressed.connect(func(): file_dialog.popup_centered_ratio(0.7))
	file_dialog.file_selected.connect(load_file)
	fetch_button.pressed.connect(_do_fetch_url)
	url_edit.text_submitted.connect(func(_t): _do_fetch_url())
	confirm_button.pressed.connect(confirm)
	clear_button.pressed.connect(_clear_picture)
	RoundManager.name_warning_received.connect(_on_name_warning)
	Game.state_changed.connect(_on_state_changed)
	_refresh_preview()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	name_edit.grab_focus()


func _process(_delta: float) -> void:
	timer_label.text = "%ds" % ceili(Game.seconds_left)


func _on_state_changed(_o: int, n: int) -> void:
	if n != Game.State.WRITING:
		_close()


# ----------------------------------------------------------------- name

func _on_name_changed(text: String) -> void:
	_refresh_preview()
	if _debounce:
		_debounce.timeout.disconnect(_on_debounce)
	_debounce = get_tree().create_timer(0.7)
	_debounce.timeout.connect(_on_debounce)


func _on_debounce() -> void:
	_debounce = null
	var n := name_edit.text.strip_edges()
	if n.length() >= 2 and n != _last_checked:
		_last_checked = n
		RoundManager.check_name_local(target_peer, n)
	if n.length() >= 3 and _picture_bytes.is_empty() and not _busy:
		_do_search()


func _on_name_warning(is_dup: bool) -> void:
	warning_label.visible = is_dup
	warning_label.text = tr("WRITE_DUP")


# --------------------------------------------------------------- search

func _do_search() -> void:
	var q := name_edit.text.strip_edges()
	if q.length() < 2 or _busy:
		return
	_busy = true
	_set_status(tr("WRITE_SEARCHING"))
	_clear_candidates()
	var lang: String = ImageSearch.WIKI_LANGS[lang_option.selected]
	var results := await _search.search(q, lang)
	if results.is_empty():
		results = await _search.search_google(q)
	if not is_inside_tree():
		return
	_busy = false
	if results.is_empty():
		_set_status(tr("WRITE_NO_RESULTS"))
		return
	_set_status("")
	for res in results.slice(0, CANDIDATE_LIMIT):
		_add_candidate(res)


func _clear_candidates() -> void:
	for c in candidates.get_children():
		c.queue_free()


func _add_candidate(res: Dictionary) -> void:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 48)
	var desc := String(res.description)
	btn.text = "%s%s" % [String(res.title), ("  ·  " + desc) if desc != "" else ""]
	btn.clip_text = true
	btn.pressed.connect(_pick_candidate.bind(res))
	candidates.add_child(btn)
	# Thumbnail loads lazily into the button icon.
	if String(res.thumb_url) != "":
		_load_thumb_into(btn, String(res.thumb_url))


func _load_thumb_into(btn: Button, url: String) -> void:
	var bytes := await _search.fetch_image(url)
	if not is_instance_valid(btn) or bytes.is_empty():
		return
	var img := ImageNormalize.decode(bytes, ImageNormalize.MAX_SOURCE_DIM)
	if img == null:
		return
	var side := mini(img.get_width(), img.get_height())
	var crop := Image.create(side, side, false, Image.FORMAT_RGBA8)
	crop.blit_rect(img, Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side), Vector2i.ZERO)
	crop.resize(40, 40)
	btn.icon = ImageTexture.create_from_image(crop)
	btn.set_meta("bytes", bytes)


func _pick_candidate(res: Dictionary) -> void:
	if _busy:
		return
	name_edit.text = String(res.title)
	_last_checked = ""
	_on_debounce()
	var url := String(res.thumb_url)
	if url == "":
		_set_status(tr("WRITE_NO_PICTURE"))
		_refresh_preview()
		return
	_busy = true
	_set_status(tr("WRITE_FETCHING"))
	var bytes := await _search.fetch_image(url)
	_busy = false
	if not is_inside_tree():
		return
	_apply_picture_bytes(bytes)


# ------------------------------------------------------- upload / url

func load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_set_status(tr("WRITE_BAD_IMAGE"))
		return
	if f.get_length() > 20 * 1024 * 1024:
		_set_status(tr("WRITE_TOO_BIG"))
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var ext := path.get_extension().to_lower()
	var fmt := ImageNormalize.detect_format(bytes)
	var ext_ok := (ext in ["png"] and fmt == "png") or (ext in ["jpg", "jpeg"] and fmt == "jpg") or (ext == "webp" and fmt == "webp")
	if not ext_ok:
		_set_status(tr("WRITE_BAD_IMAGE"))
		return
	_apply_picture_bytes(bytes)


func _do_fetch_url() -> void:
	var url := url_edit.text.strip_edges()
	if url == "" or _busy:
		return
	if not ImageSearch.is_allowed_url(url, true):
		_set_status(tr("WRITE_BAD_URL"))
		return
	_busy = true
	_set_status(tr("WRITE_FETCHING"))
	var bytes := await _search.fetch_user_url(url)
	_busy = false
	if not is_inside_tree():
		return
	_apply_picture_bytes(bytes)


func _apply_picture_bytes(bytes: PackedByteArray) -> void:
	var wire := ImageNormalize.normalize(bytes)
	if wire.is_empty():
		_set_status(tr("WRITE_BAD_IMAGE"))
		return
	_picture_bytes = wire
	_picture_tex = ImageNormalize.texture_from_wire(wire)
	_set_status("")
	_refresh_preview()


func _clear_picture() -> void:
	_picture_bytes = PackedByteArray()
	_picture_tex = null
	_refresh_preview()


# ------------------------------------------------------------ preview

func _refresh_preview() -> void:
	preview_pic.texture = _picture_tex
	preview_pic.visible = _picture_tex != null
	clear_button.visible = _picture_tex != null
	var n := name_edit.text.strip_edges()
	preview_name.text = n if n != "" else "…"
	preview_hint.visible = _picture_tex == null
	confirm_button.disabled = n.length() < 2 or _confirmed


func _set_status(text: String) -> void:
	status_label.text = text


# ------------------------------------------------------------ confirm

func confirm() -> void:
	if _confirmed:
		return
	var n := name_edit.text.strip_edges().substr(0, RoundManager.MAX_WRITTEN_NAME)
	if n.length() < 2:
		return
	_confirmed = true
	RoundManager.submit_local(target_peer, n, _picture_bytes)
	Audio.play("ui_confirm")
	_set_status(tr("WRITE_SENT"))
	for c in [search_button, upload_button, fetch_button, lang_option, clear_button, confirm_button]:
		c.disabled = true
	name_edit.editable = false
	url_edit.editable = false
	_clear_candidates()
	await get_tree().create_timer(1.2).timeout
	_close()


## Bot / test entry: set everything and confirm in one go.
func bot_fill(name: String, picture: PackedByteArray) -> void:
	name_edit.text = name
	if not picture.is_empty():
		_apply_picture_bytes(picture)
	_refresh_preview()
	confirm()


## Bot: run a live Wikipedia search and take the first candidate with a picture.
func bot_search_and_pick(name: String) -> void:
	name_edit.text = name
	var lang: String = ImageSearch.WIKI_LANGS[lang_option.selected]
	var results := await _search.search(name, lang)
	if not is_inside_tree():
		return
	for res in results:
		if String(res.thumb_url) != "":
			var bytes := await _search.fetch_image(String(res.thumb_url))
			if not is_inside_tree():
				return
			if not bytes.is_empty():
				name_edit.text = String(res.title)
				_apply_picture_bytes(bytes)
				break
	confirm()


func _close() -> void:
	closed.emit()
	queue_free()
