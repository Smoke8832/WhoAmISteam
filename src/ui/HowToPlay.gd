extends Control
## Four cards that explain the game. Shown on first launch and from the menus.

signal closed

const CARDS := ["HOWTO_1", "HOWTO_2", "HOWTO_3", "HOWTO_4"]
const ICONS := ["✍️", "📝", "❓", "🎉"]

var _index := 0

@onready var icon_label: Label = %Icon
@onready var text_label: Label = %Text
@onready var step_label: Label = %Step
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	prev_button.pressed.connect(func(): _go(-1))
	next_button.pressed.connect(func(): _go(1))
	close_button.pressed.connect(_close)
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_go(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_go(-1)


func _go(dir: int) -> void:
	if _index + dir >= CARDS.size():
		_close()
		return
	_index = clampi(_index + dir, 0, CARDS.size() - 1)
	_refresh()
	Audio.play("ui_click")


func _refresh() -> void:
	icon_label.text = ICONS[_index]
	text_label.text = tr(CARDS[_index])
	step_label.text = "%d / %d" % [_index + 1, CARDS.size()]
	prev_button.disabled = _index == 0
	next_button.text = tr("HOWTO_DONE") if _index == CARDS.size() - 1 else tr("HOWTO_NEXT")


func _close() -> void:
	Settings.set_value("first_launch", false)
	closed.emit()
	queue_free()
