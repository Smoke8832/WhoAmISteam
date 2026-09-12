extends Control
## Guessing-phase controls at the bottom of the screen. Not a modal: you can still walk around.
## Guesser: Ask (Q) opens an answer vote, I know it! (G) opens a guess vote.
## Everyone else: YES (Y) / NO (N) / shrug (U) on answers, Correct (Y) / Wrong (N) on guesses.

const YES_COLOR := Color("3fa66b")
const NO_COLOR := Color("e0523e")
const SHRUG_COLOR := Color("9a958c")

@onready var turn_label: Label = %TurnLabel
@onready var sub_label: Label = %SubLabel
@onready var timer_label: Label = %TimerLabel
@onready var guesser_row: HBoxContainer = %GuesserRow
@onready var ask_button: Button = %AskButton
@onready var claim_button: Button = %ClaimButton
@onready var vote_row: HBoxContainer = %VoteRow
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton
@onready var shrug_button: Button = %ShrugButton
@onready var tally_label: Label = %TallyLabel
@onready var result_label: Label = %ResultLabel
@onready var end_button: Button = %EndButton

var _last_seq := 0
var _local_turn_left := 0.0
var _local_vote_left := 0.0
var _result_tween: Tween


func _ready() -> void:
	ask_button.pressed.connect(func(): RoundManager.ask_local())
	claim_button.pressed.connect(func(): RoundManager.claim_local())
	yes_button.pressed.connect(_vote_yes)
	no_button.pressed.connect(_vote_no)
	shrug_button.pressed.connect(func(): RoundManager.vote_answer_local(RoundManager.VOTE_SHRUG))
	end_button.pressed.connect(func(): RoundManager.end_round_local())
	yes_button.add_theme_color_override("font_color", YES_COLOR)
	no_button.add_theme_color_override("font_color", NO_COLOR)
	shrug_button.add_theme_color_override("font_color", SHRUG_COLOR)
	RoundManager.round_changed.connect(refresh)
	RoundManager.vote_changed.connect(refresh)
	Game.players_changed.connect(refresh)
	Game.state_changed.connect(func(_o, _n): refresh())
	result_label.modulate.a = 0.0
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_local_turn_left = maxf(0.0, _local_turn_left - delta)
	_local_vote_left = maxf(0.0, _local_vote_left - delta)
	var v := RoundManager.open_vote()
	if v.is_empty():
		timer_label.text = Locale.f("GUESS_TURN_TIMER", {"s": ceili(_local_turn_left)})
	else:
		timer_label.text = Locale.f("GUESS_VOTE_TIMER", {"s": ceili(_local_vote_left)})


func _unhandled_input(event: InputEvent) -> void:
	if not visible or Game.state != Game.State.GUESSING:
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	if event.is_action_pressed("vote_yes") and RoundManager.can_vote():
		_vote_yes()
	elif event.is_action_pressed("vote_no") and RoundManager.can_vote():
		_vote_no()
	elif event.is_action_pressed("vote_shrug") and RoundManager.can_vote() and String(RoundManager.open_vote().kind) == "answer":
		RoundManager.vote_answer_local(RoundManager.VOTE_SHRUG)
	elif event.is_action_pressed("ask") and RoundManager.is_my_turn() and RoundManager.open_vote().is_empty():
		RoundManager.ask_local()
	elif event.is_action_pressed("claim") and RoundManager.is_my_turn() and RoundManager.open_vote().is_empty():
		RoundManager.claim_local()


func _vote_yes() -> void:
	var v := RoundManager.open_vote()
	if v.is_empty():
		return
	if String(v.kind) == "answer":
		RoundManager.vote_answer_local(RoundManager.VOTE_YES)
	else:
		RoundManager.vote_guess_local(true)
	Audio.play("vote")


func _vote_no() -> void:
	var v := RoundManager.open_vote()
	if v.is_empty():
		return
	if String(v.kind) == "answer":
		RoundManager.vote_answer_local(RoundManager.VOTE_NO)
	else:
		RoundManager.vote_guess_local(false)
	Audio.play("vote")


func refresh() -> void:
	var in_guessing := Game.state == Game.State.GUESSING
	visible = in_guessing
	if not in_guessing:
		return
	var me := Game.local_id()
	var guesser := RoundManager.current_guesser()
	var my_turn := guesser == me
	var v := RoundManager.open_vote()
	_local_turn_left = float(RoundManager.r.get("turn_seconds_left", 0.0))
	_local_vote_left = float(v.get("seconds_left", 0.0)) if not v.is_empty() else 0.0
	var solved: Dictionary = RoundManager.r.get("solved", {})
	end_button.visible = Game.is_admin()

	if my_turn:
		turn_label.text = tr("GUESS_YOUR_TURN")
		if v.is_empty():
			sub_label.text = tr("GUESS_YOUR_TURN_HINT")
		elif String(v.kind) == "answer":
			sub_label.text = tr("GUESS_WAIT_ANSWER")
		else:
			sub_label.text = tr("GUESS_WAIT_JUDGE")
	else:
		turn_label.text = Locale.f("TV_TURN", {"name": Game.player_name(guesser)})
		if solved.has(me):
			sub_label.text = Locale.f("GUESS_YOU_SOLVED", {"rank": int(solved[me])})
		elif v.is_empty():
			sub_label.text = tr("GUESS_LISTEN")
		elif String(v.kind) == "answer":
			sub_label.text = tr("GUESS_ANSWER_NOW")
		else:
			sub_label.text = Locale.f("GUESS_JUDGE_NOW", {"name": Game.player_name(guesser)})

	guesser_row.visible = my_turn and v.is_empty()
	var can_vote := RoundManager.can_vote()
	vote_row.visible = can_vote
	if can_vote:
		var is_answer := String(v.kind) == "answer"
		yes_button.text = tr("VOTE_YES") if is_answer else tr("VOTE_CORRECT")
		no_button.text = tr("VOTE_NO") if is_answer else tr("VOTE_WRONG")
		shrug_button.visible = is_answer
		var mine = RoundManager.my_vote()
		yes_button.disabled = mine != null
		no_button.disabled = mine != null
		shrug_button.disabled = mine != null
	tally_label.visible = not v.is_empty()
	if not v.is_empty():
		tally_label.text = RoundManager.describe_vote(v)

	var res := RoundManager.last_result()
	var seq := int(res.get("seq", 0))
	if seq != 0 and seq != _last_seq:
		_last_seq = seq
		_flash(RoundManager.describe_result(res), res)


func _flash(text: String, res: Dictionary) -> void:
	result_label.text = text
	var kind := String(res.get("kind", ""))
	var good := (kind == "answer" and String(res.get("answer", "")) == "YES") or (kind == "guess" and bool(res.get("correct", false)))
	var bad := (kind == "answer" and String(res.get("answer", "")) == "NO") or (kind == "guess" and not bool(res.get("correct", false))) or kind == "timeout"
	result_label.add_theme_color_override("font_color", YES_COLOR if good else (NO_COLOR if bad else Color.WHITE))
	if _result_tween:
		_result_tween.kill()
	result_label.modulate.a = 1.0
	result_label.scale = Vector2.ONE * 1.2
	_result_tween = create_tween()
	_result_tween.tween_property(result_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_result_tween.tween_interval(1.8)
	_result_tween.tween_property(result_label, "modulate:a", 0.0, 0.5)
	if kind == "guess" and bool(res.get("correct", false)):
		Audio.play("confetti")
	elif good:
		Audio.play("ding_yes")
	elif bad:
		Audio.play("ding_no")
