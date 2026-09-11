extends CharacterBody3D
## Player pawn. The owning peer (multiplayer authority) simulates movement and writes
## the net_* properties; every other peer interpolates toward them.

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
const PITCH_LIMIT := deg_to_rad(85.0)

enum Anim { IDLE, WALK, JUMP, CROUCH, SIT }

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
var _squash: float = 1.0

@onready var collider: CollisionShape3D = $Collider
@onready var body: Node3D = $Body
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var name_tag: Label3D = $NameTag


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
	camera.current = is_local()
	_refresh_name_tag()
	Game.players_changed.connect(_refresh_name_tag)
	if is_local() and not Settings.cli.bot:
		_set_mouse_captured(true)
	# The local player should not see their own body from the first-person camera.
	if is_local():
		_set_body_visible_to_camera(false)


func _refresh_name_tag() -> void:
	name_tag.text = Game.player_name(peer_id)
	name_tag.visible = not is_local()


func _set_body_visible_to_camera(visible: bool) -> void:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1 if visible else 2
	camera.cull_mask = 1 | (1 << 10)  # layer 1 (world + others) + layer 11 (UI 3D), not layer 2 (own body)


func _set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not is_local():
		return
	if event is InputEventMouseMotion and mouse_captured:
		var sens := float(Settings.get_value("mouse_sensitivity", 0.0025))
		var inv := -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens * inv, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("menu"):
		_set_mouse_captured(not mouse_captured)
	elif event is InputEventMouseButton and event.pressed and not mouse_captured and not Settings.cli.bot:
		if not get_viewport().gui_get_focus_owner():
			_set_mouse_captured(true)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate(delta)
	else:
		_interpolate(delta)
	_animate(delta)


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

	net_pos = global_position
	net_yaw = yaw
	net_pitch = pitch
	net_crouch = crouching
	if not is_on_floor():
		net_anim = Anim.JUMP
	elif crouching:
		net_anim = Anim.CROUCH
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		net_anim = Anim.WALK
	else:
		net_anim = Anim.IDLE


func _set_crouch(value: bool) -> void:
	if crouching == value:
		return
	if not value:
		# Only stand up if there is room above.
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
	# Procedural cartoon motion: head height follows crouch, body squashes on jump.
	var eye := CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT
	head.position.y = lerpf(head.position.y, eye, clampf(delta * 10.0, 0.0, 1.0))
	_squash = lerpf(_squash, 1.0, clampf(delta * 6.0, 0.0, 1.0))
	var body_scale_y := (0.65 if crouching else 1.0) * _squash
	body.scale = Vector3(1.0 / sqrt(_squash), body_scale_y, 1.0 / sqrt(_squash))
	if has_node("Body/Rig"):
		$Body/Rig.set_anim(net_anim if not is_multiplayer_authority() else _local_anim())


func _local_anim() -> int:
	return net_anim


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
