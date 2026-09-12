extends CharacterBody3D
## Player pawn. The owning peer (multiplayer authority) simulates movement and writes
## the net_* properties; every other peer interpolates toward them.
## Sitting and prop holding are decided by the host and arrive through Game snapshots / Prop sync.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 2.2
const JUMP_VELOCITY := 5.2
const ACCEL := 14.0
const GRAVITY := 14.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 0.95
const SIT_EYE_HEIGHT := 1.15
const PITCH_LIMIT := deg_to_rad(85.0)
const INTERACT_RANGE := 2.6
const THROW_FORCE := 7.5

enum Anim { IDLE, WALK, JUMP, CROUCH, SIT }
enum Emote { WAVE, LAUGH, FACEPALM }
const EMOTE_TEXT := ["waves 👋", "laughs 😂", "facepalms 🤦"]

var peer_id: int = 0
var spawn_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))

# Replicated (authority -> everyone)
var net_pos: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: bool = false
var net_anim: int = Anim.IDLE

# Bot control (only read on the authority when Settings.cli.bot)
var bot_move: Vector2 = Vector2.ZERO
var bot_jump: bool = false
var bot_look: Vector2 = Vector2.ZERO

var yaw: float = 0.0
var pitch: float = 0.0
var crouching: bool = false
var mouse_captured: bool = false
var third_person: bool = false
var seated: bool = false
var seat_chair: int = -1
var held_prop: int = -1
var _squash: float = 1.0
var _emote_timer: float = 0.0
var _look_target: Node3D = null   # what the local player is looking at (interactable)

@onready var collider: CollisionShape3D = $Collider
@onready var body: Node3D = $Body
@onready var rig: CharacterRig = $Body/Rig
@onready var fp_postfx: MeshInstance3D = $Head/Camera3D/PostFX
@onready var tp_postfx: MeshInstance3D = $Head/SpringArm3D/TPCamera/PostFX
var _custom_hash: int = 0
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var tp_camera: Camera3D = $Head/SpringArm3D/TPCamera
@onready var hold_point: Node3D = $Head/HoldPoint
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var name_tag: Label3D = $NameTag
@onready var emote_bubble: Label3D = $EmoteBubble


func is_local() -> bool:
	return peer_id == Net.local_id()


func _ready() -> void:
	add_to_group("players")
	if is_multiplayer_authority():
		global_transform = spawn_transform
		yaw = spawn_transform.basis.get_euler().y
		net_pos = global_position
		net_yaw = yaw
	else:
		global_position = net_pos if net_pos != Vector3.ZERO else spawn_transform.origin
	third_person = bool(Settings.get_value("third_person", false)) and is_local()
	var c: Dictionary = Game.player(peer_id).get("customization", Customization.local() if is_local() else Customization.defaults())
	_custom_hash = hash(c)
	rig.apply(c)
	_apply_camera_mode()
	_refresh_name_tag()
	emote_bubble.visible = false
	Game.players_changed.connect(_on_players_changed)
	Game.players_changed.connect(_refresh_name_tag)
	spring_arm.add_excluded_object(get_rid())
	interact_ray.add_exception(self)
	if is_local() and not Settings.cli.bot:
		_set_mouse_captured(true)


func _refresh_name_tag() -> void:
	name_tag.text = Game.player_name(peer_id)
	name_tag.visible = not is_local() or third_person


func _apply_camera_mode() -> void:
	var local := is_local()
	camera.current = local and not third_person
	tp_camera.current = local and third_person
	# Layer 2 = own body, hidden from the first-person camera only.
	rig.set_visual_layers(2 if local else 1)
	camera.cull_mask = 1 | (1 << 10)
	tp_camera.cull_mask = 1 | 2 | (1 << 10)
	fp_postfx.visible = camera.current
	tp_postfx.visible = tp_camera.current
	name_tag.visible = not local or third_person


func _set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	var hud := _hud()
	if hud and hud.has_method("is_modal_open") and hud.is_modal_open():
		if mouse_captured:
			_set_mouse_captured(false)
		return
	if event is InputEventMouseMotion and mouse_captured:
		var sens := float(Settings.get_value("mouse_sensitivity", 0.0025))
		var inv := -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens * inv, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("toggle_camera"):
		set_third_person(not third_person)
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("throw"):
		if mouse_captured and held_prop >= 0:
			throw_held()
		elif not mouse_captured and not Settings.cli.bot and get_viewport().gui_get_focus_owner() == null:
			_set_mouse_captured(true)
	elif event.is_action_pressed("emote_1"):
		emote(Emote.WAVE)
	elif event.is_action_pressed("emote_2"):
		emote(Emote.LAUGH)
	elif event.is_action_pressed("emote_3"):
		emote(Emote.FACEPALM)


func set_third_person(value: bool) -> void:
	third_person = value
	if not Settings.cli.bot:
		Settings.set_value("third_person", value)
	_apply_camera_mode()


# --------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate(delta)
	else:
		_interpolate(delta)
	_animate(delta)
	if is_local():
		_update_look_target()


func _simulate(delta: float) -> void:
	var input_dir := Vector2.ZERO
	var want_jump := false
	var want_crouch := false
	var want_sprint := false
	var typing := get_viewport().gui_get_focus_owner() != null
	if Settings.cli.bot:
		input_dir = bot_move
		want_jump = bot_jump
		bot_jump = false
		yaw += bot_look.x * delta
		pitch = clampf(pitch + bot_look.y * delta, -PITCH_LIMIT, PITCH_LIMIT)
	elif not typing:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_jump = Input.is_action_just_pressed("jump")
		want_crouch = Input.is_action_pressed("crouch")
		want_sprint = Input.is_action_pressed("sprint")

	if seated:
		velocity = Vector3.ZERO
		if want_jump or (input_dir.length() > 0.5 and not Settings.cli.bot):
			request_stand()
		rotation.y = yaw
		head.rotation.x = pitch
		_write_net(Anim.SIT)
		return

	_set_crouch(want_crouch)

	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if want_sprint else WALK_SPEED)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := (right * input_dir.x + forward * -input_dir.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target_h := wish * speed
	velocity.x = move_toward(velocity.x, target_h.x, ACCEL * delta * speed)
	velocity.z = move_toward(velocity.z, target_h.z, ACCEL * delta * speed)

	if is_on_floor():
		if want_jump and not crouching:
			velocity.y = JUMP_VELOCITY
			_squash = 1.25
			Audio.play_at("jump", global_position, get_parent())
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	rotation.y = yaw
	head.rotation.x = pitch

	var anim := Anim.IDLE
	if not is_on_floor():
		anim = Anim.JUMP
	elif crouching:
		anim = Anim.CROUCH
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		anim = Anim.WALK
	_write_net(anim)


func _write_net(anim: int) -> void:
	net_pos = global_position
	net_yaw = yaw
	net_pitch = pitch
	net_crouch = crouching
	net_anim = anim


func _set_crouch(value: bool) -> void:
	if crouching == value:
		return
	if not value:
		var shape := collider.shape as CapsuleShape3D
		var was := shape.height
		shape.height = STAND_HEIGHT
		collider.position.y = STAND_HEIGHT / 2.0
		if test_move(global_transform, Vector3.ZERO):
			shape.height = was
			collider.position.y = was / 2.0
			return
	crouching = value
	var shape2 := collider.shape as CapsuleShape3D
	shape2.height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	collider.position.y = shape2.height / 2.0


func _interpolate(delta: float) -> void:
	var t := clampf(delta * 12.0, 0.0, 1.0)
	global_position = global_position.lerp(net_pos, t)
	yaw = lerp_angle(yaw, net_yaw, t)
	pitch = lerpf(pitch, net_pitch, t)
	rotation.y = yaw
	head.rotation.x = pitch
	if crouching != net_crouch:
		crouching = net_crouch
		var shape := collider.shape as CapsuleShape3D
		shape.height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
		collider.position.y = shape.height / 2.0


func _animate(delta: float) -> void:
	var anim := net_anim
	var eye := EYE_HEIGHT
	if anim == Anim.SIT:
		eye = SIT_EYE_HEIGHT
	elif crouching:
		eye = CROUCH_EYE_HEIGHT
	head.position.y = lerpf(head.position.y, eye, clampf(delta * 10.0, 0.0, 1.0))
	_squash = lerpf(_squash, 1.0, clampf(delta * 6.0, 0.0, 1.0))
	var body_scale_y := (0.7 if crouching else 1.0) * _squash
	body.scale = Vector3(1.0 / sqrt(_squash), body_scale_y, 1.0 / sqrt(_squash))
	# Sitting lowers the hips to seat height; the rig folds the legs forward.
	body.position.y = lerpf(body.position.y, -0.25 if anim == Anim.SIT else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	rig.set_head_pitch(pitch)
	rig.set_anim(anim, delta)
	if _emote_timer > 0.0:
		_emote_timer -= delta
		if _emote_timer <= 0.0:
			emote_bubble.visible = false


# ------------------------------------------------------------ interaction

func _update_look_target() -> void:
	var prev := _look_target
	_look_target = null
	var prompt := ""
	if seated:
		prompt = tr("PROMPT_STAND")
	elif held_prop >= 0:
		prompt = tr("PROMPT_THROW")
	else:
		interact_ray.target_position = Vector3(0, 0, -INTERACT_RANGE)
		interact_ray.force_raycast_update()
		if interact_ray.is_colliding():
			var hit := interact_ray.get_collider()
			var node := hit as Node
			while node != null and not node.is_in_group("interactable") and not node.is_in_group("wardrobe"):
				node = node.get_parent()
			if node is Chair:
				_look_target = node
				prompt = tr("PROMPT_SIT") if (node as Chair).is_free() else tr("PROMPT_TAKEN")
			elif node is Prop:
				_look_target = node
				prompt = tr("PROMPT_GRAB") if (node as Prop).held_by == 0 else ""
			elif node != null and node.is_in_group("wardrobe"):
				_look_target = node
				prompt = tr("PROMPT_WARDROBE")
	var hud := _hud()
	if hud:
		hud.set_prompt(prompt)
	if prev != _look_target and _look_target is Chair:
		pass


func _hud() -> Node:
	var main := get_tree().current_scene
	return main.get("hud") if main else null


## E pressed by the local player.
func interact() -> void:
	if not is_local():
		return
	if seated:
		request_stand()
		return
	if held_prop >= 0:
		Game.req_throw_local(Vector3.DOWN, 0.0)
		return
	if _look_target is Chair:
		var c := _look_target as Chair
		if c.is_free():
			Game.req_sit_local(c.chair_id)
	elif _look_target is Prop:
		Game.req_grab_local((_look_target as Prop).prop_id)
	elif _look_target != null and _look_target.is_in_group("wardrobe"):
		var hud := _hud()
		if hud and hud.has_method("open_customizer"):
			hud.open_customizer()


func request_stand() -> void:
	if is_local() and seated:
		Game.req_stand_local()


func throw_held() -> void:
	if held_prop < 0:
		return
	var dir := -camera.global_transform.basis.z
	Game.req_throw_local(dir, THROW_FORCE)


## World transform where a held prop should sit (used by the host to move the prop).
func hold_transform() -> Transform3D:
	return hold_point.global_transform


## Called on every peer when the players dictionary changes: apply seat + held state.
func _on_players_changed() -> void:
	var p: Dictionary = Game.player(peer_id)
	if p.is_empty():
		return
	var new_seat := int(p.get("seat", -1))
	if new_seat != seat_chair:
		seat_chair = new_seat
		_apply_seat()
	held_prop = int(p.get("held_prop", -1))
	var c: Dictionary = p.get("customization", {})
	if not c.is_empty() and hash(c) != _custom_hash:
		_custom_hash = hash(c)
		rig.apply(c)
		_apply_camera_mode()


func _apply_seat() -> void:
	var level := Game.level()
	var chair: Chair = level.chair(seat_chair) if level and seat_chair >= 0 else null
	if chair:
		seated = true
		collider.disabled = true
		_set_crouch(false)
		if is_multiplayer_authority():
			var t := chair.seat_transform()
			global_position = t.origin
			yaw = chair.facing_yaw()
			pitch = 0.0
			velocity = Vector3.ZERO
			_write_net(Anim.SIT)
	else:
		var was_seated := seated
		seated = false
		collider.disabled = false
		if was_seated and is_multiplayer_authority():
			var prev_chair: Chair = level.chair(_last_chair) if level else null
			if prev_chair:
				var st := prev_chair.stand_transform()
				global_position = st.origin
				yaw = prev_chair.facing_yaw()
			velocity = Vector3.ZERO
			_write_net(Anim.IDLE)
	_last_chair = seat_chair if seated else _last_chair

var _last_chair: int = -1


# ------------------------------------------------------------------ emotes

func emote(id: int) -> void:
	if not is_multiplayer_authority():
		return
	play_emote.rpc(id)


@rpc("any_peer", "call_local", "reliable")
func play_emote(id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	id = clampi(id, 0, EMOTE_TEXT.size() - 1)
	emote_bubble.text = EMOTE_TEXT[id]
	emote_bubble.visible = true
	_emote_timer = 2.2
	_squash = 1.15
	rig.play_emote(id)
	Audio.play_at("emote_%d" % id, global_position, get_parent())


# ---------------------------------------------------------------- helpers

## Point the view at a world position (used by bots and by the sit animation).
func face_toward(target: Vector3) -> void:
	var eye := global_position + Vector3(0, EYE_HEIGHT, 0)
	var d := target - eye
	if d.length() < 0.01:
		return
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_LIMIT, PITCH_LIMIT)


func teleport(to: Transform3D) -> void:
	global_transform = to
	yaw = to.basis.get_euler().y
	velocity = Vector3.ZERO
	net_pos = global_position
	net_yaw = yaw


func look_target() -> Node3D:
	return _look_target
