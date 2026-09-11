class_name CharacterRig
extends Node3D
## Procedural cartoon character built from primitives, driven by a Customization dictionary.
## Also owns the face decal, the post-it, and the procedural animations (walk, sit, emotes).

enum Anim { IDLE, WALK, JUMP, CROUCH, SIT }
enum Emote { WAVE, LAUGH, FACEPALM }

const HIP_Y := 0.70
const SHOULDER_Y := 1.26
const NECK_Y := 1.30
const HEAD_R := 0.28
const HEAD_OFFSET := 0.25   # head centre above the neck pivot
const HEAD_SHAPES := [Vector3(1, 1, 1), Vector3(0.9, 1.15, 0.9), Vector3(1.15, 0.92, 1.05)]
const GLASSES_COLORS := [Color("1c1a17"), Color("c9184a"), Color("4d6fd1")]

var custom: Dictionary = {}
var postit: PostIt = null

var _head_pivot: Node3D
var _head_mesh: MeshInstance3D
var _torso: MeshInstance3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _face: Decal
var _time := 0.0
var _emote := -1
var _emote_t := 0.0
var _talk_open := false
var _talk_hold := 0.0
var _head_pitch := 0.0
var _current_anim: int = Anim.IDLE


func _ready() -> void:
	if custom.is_empty():
		apply(Customization.defaults())


# ------------------------------------------------------------------- build

func apply(c: Dictionary) -> void:
	custom = Customization.sanitize(c)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var skin: Color = Customization.SKIN_COLORS[custom.skin]
	var hair_col: Color = Customization.HAIR_COLORS[custom.hair_color]
	var shirt: Color = Customization.SHIRT_COLORS[custom.shirt]
	var pants: Color = Customization.PANTS_COLORS[custom.pants]
	var shoes: Color = Customization.SHOE_COLORS[custom.shoes]
	var accent := shirt.darkened(0.35) if shirt.get_luminance() > 0.5 else shirt.lightened(0.45)
	var shirt_tex := ToonMaterials.pattern_texture(int(custom.pattern), accent)

	# Legs
	_leg_l = _pivot("LegL", Vector3(-0.13, HIP_Y, 0))
	_leg_r = _pivot("LegR", Vector3(0.13, HIP_Y, 0))
	for leg in [_leg_l, _leg_r]:
		_capsule(leg, 0.11, 0.62, Vector3(0, -0.33, 0), pants)
		_box(leg, Vector3(0.17, 0.1, 0.27), Vector3(0, -0.66, -0.05), shoes)
	# Torso
	_torso = _capsule(self, 0.29, 0.72, Vector3(0, 0.98, 0), shirt, shirt_tex)
	# Arms
	_arm_l = _pivot("ArmL", Vector3(-0.36, SHOULDER_Y, 0))
	_arm_r = _pivot("ArmR", Vector3(0.36, SHOULDER_Y, 0))
	for arm in [_arm_l, _arm_r]:
		_capsule(arm, 0.08, 0.5, Vector3(0, -0.26, 0), shirt, shirt_tex)
		_sphere(arm, 0.1, Vector3(0, -0.55, 0), skin)
	# Head
	_head_pivot = _pivot("Head", Vector3(0, NECK_Y, 0))
	_head_mesh = _sphere(_head_pivot, HEAD_R, Vector3(0, HEAD_OFFSET, 0), skin)
	_head_mesh.scale = HEAD_SHAPES[custom.head]
	_build_face()
	_build_hair(hair_col)
	_build_facial_hair(hair_col)
	_build_accessory(shirt, accent)
	# Post-it (hidden until a round sticks one on)
	postit = PostIt.new()
	postit.name = "PostIt"
	postit.position = Vector3(0, HEAD_OFFSET + 0.07, -(HEAD_R + 0.035))
	postit.visible = false
	_head_pivot.add_child(postit)


func _pivot(name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = ToonMaterials.make(color, tex)
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, tex: Texture2D = null) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return _mesh(parent, m, pos, color, tex)


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 24
	m.rings = 12
	return _mesh(parent, m, pos, color)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, pos, color)


func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return _mesh(parent, m, pos, color)


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 12
	return _mesh(parent, m, pos, color)


func _build_face() -> void:
	_face = Decal.new()
	_face.name = "Face"
	_face.texture_albedo = FacePainter.texture(int(custom.eyes), int(custom.brows), int(custom.mouth), int(custom.blush), false)
	_face.size = Vector3(0.52, 0.5, 0.52)
	_face.position = Vector3(0, HEAD_OFFSET + 0.03, -0.12)
	_face.rotation_degrees = Vector3(-90, 0, 0)
	_face.albedo_mix = 1.0
	_face.upper_fade = 0.0
	_face.lower_fade = 0.0
	_face.cull_mask = 0xFFFFF & ~PostIt.LAYER_BIT   # never project onto the post-it
	_head_pivot.add_child(_face)


func _hair_cap(color: Color, scale_y: float = 0.62, lift: float = 0.1, x_shift: float = 0.0) -> MeshInstance3D:
	var cap := _sphere(_head_pivot, HEAD_R + 0.02, Vector3(x_shift, HEAD_OFFSET + lift, 0), color)
	cap.scale = Vector3(1.0, scale_y, 1.0)
	return cap


func _build_hair(color: Color) -> void:
	var y := HEAD_OFFSET
	match int(custom.hair):
		0:
			pass
		1:  # buzz
			_hair_cap(color, 0.55, 0.12)
		2:  # curly
			_hair_cap(color, 0.6, 0.1)
			for i in 7:
				var a := i * TAU / 7.0
				_sphere(_head_pivot, 0.11, Vector3(cos(a) * 0.24, y + 0.2 + sin(a * 2.0) * 0.04, sin(a) * 0.24), color)
		3:  # mohawk
			_box(_head_pivot, Vector3(0.09, 0.18, 0.5), Vector3(0, y + 0.3, 0.02), color)
		4:  # bun
			_hair_cap(color, 0.6, 0.1)
			_sphere(_head_pivot, 0.11, Vector3(0, y + 0.3, 0.14), color)
		5:  # long
			_hair_cap(color, 0.65, 0.1)
			_box(_head_pivot, Vector3(0.1, 0.5, 0.32), Vector3(-0.27, y - 0.05, 0.06), color)
			_box(_head_pivot, Vector3(0.1, 0.5, 0.32), Vector3(0.27, y - 0.05, 0.06), color)
			_box(_head_pivot, Vector3(0.5, 0.5, 0.1), Vector3(0, y - 0.05, 0.27), color)
		6:  # side part
			_hair_cap(color, 0.58, 0.12, 0.04)
			_box(_head_pivot, Vector3(0.42, 0.1, 0.14), Vector3(0.04, y + 0.2, -0.2), color)
		7:  # afro
			_sphere(_head_pivot, 0.42, Vector3(0, y + 0.08, 0.02), color)


func _build_facial_hair(color: Color) -> void:
	var y := HEAD_OFFSET
	match int(custom.facial_hair):
		0:
			pass
		1:  # stubble
			var s := _sphere(_head_pivot, HEAD_R + 0.005, Vector3(0, y - 0.13, -0.01), color.darkened(0.2))
			s.scale = Vector3(1.0, 0.4, 1.0)
		2:  # goatee
			_box(_head_pivot, Vector3(0.12, 0.11, 0.08), Vector3(0, y - 0.26, -0.21), color)
		3:  # full beard
			var b := _sphere(_head_pivot, HEAD_R + 0.02, Vector3(0, y - 0.14, -0.005), color)
			b.scale = Vector3(1.02, 0.55, 1.02)
		4:  # mustache
			for sx in [-1.0, 1.0]:
				var m := _capsule(_head_pivot, 0.03, 0.12, Vector3(sx * 0.065, y - 0.06, -0.275), color)
				m.rotation_degrees = Vector3(0, 0, 90 - sx * 12.0)


func _build_accessory(shirt: Color, accent: Color) -> void:
	var y := HEAD_OFFSET
	var acc := int(custom.accessory)
	if acc >= 1 and acc <= 3:  # glasses
		var col: Color = GLASSES_COLORS[acc - 1]
		for sx in [-1.0, 1.0]:
			var ring := _torus(_head_pivot, 0.05, 0.075, Vector3(sx * 0.1, y + 0.03, -0.27), col)
			ring.rotation_degrees = Vector3(90, 0, 0)
		_box(_head_pivot, Vector3(0.06, 0.015, 0.02), Vector3(0, y + 0.03, -0.29), col)
		for sx in [-1.0, 1.0]:
			_box(_head_pivot, Vector3(0.015, 0.015, 0.26), Vector3(sx * 0.27, y + 0.04, -0.13), col)
	elif acc == 4:  # headset
		var band := _torus(_head_pivot, HEAD_R + 0.02, HEAD_R + 0.055, Vector3(0, y + 0.02, 0), Color("2b2b2b"))
		band.rotation_degrees = Vector3(0, 0, 90)
		band.scale = Vector3(1.0, 1.0, 1.0)
		for sx in [-1.0, 1.0]:
			var cup := _cylinder(_head_pivot, 0.075, 0.06, Vector3(sx * (HEAD_R + 0.02), y, 0), Color("2b2b2b"))
			cup.rotation_degrees = Vector3(0, 0, 90)
			_cylinder(_head_pivot, 0.05, 0.02, Vector3(sx * (HEAD_R + 0.055), y, 0), Color("e0523e")).rotation_degrees = Vector3(0, 0, 90)
		var mic := _cylinder(_head_pivot, 0.012, 0.22, Vector3(-0.2, y - 0.1, -0.16), Color("2b2b2b"))
		mic.rotation_degrees = Vector3(70, 0, 30)
		_sphere(_head_pivot, 0.03, Vector3(-0.1, y - 0.16, -0.27), Color("2b2b2b"))
	elif acc == 5:  # cap
		_cylinder(_head_pivot, HEAD_R + 0.02, 0.13, Vector3(0, y + 0.2, 0), shirt)
		var top := _sphere(_head_pivot, HEAD_R + 0.02, Vector3(0, y + 0.2, 0), shirt)
		top.scale = Vector3(1.0, 0.5, 1.0)
		_box(_head_pivot, Vector3(0.3, 0.03, 0.22), Vector3(0, y + 0.15, -0.36), accent)
	elif acc == 6:  # beanie
		var b := _sphere(_head_pivot, HEAD_R + 0.03, Vector3(0, y + 0.1, 0), accent)
		b.scale = Vector3(1.05, 0.75, 1.05)
		var rim := _torus(_head_pivot, HEAD_R - 0.02, HEAD_R + 0.06, Vector3(0, y + 0.06, 0), accent.darkened(0.2))
		rim.scale = Vector3(1.0, 0.7, 1.0)
		_sphere(_head_pivot, 0.06, Vector3(0, y + 0.42, 0), accent.darkened(0.2))
	elif acc == 7:  # bow
		var pink := Color("f15bb5")
		for sx in [-1.0, 1.0]:
			var wing := _box(_head_pivot, Vector3(0.14, 0.09, 0.06), Vector3(sx * 0.09, y + 0.3, 0.02), pink)
			wing.rotation_degrees = Vector3(0, 0, sx * 25.0)
		_sphere(_head_pivot, 0.035, Vector3(0, y + 0.3, 0.02), pink.darkened(0.25))


# --------------------------------------------------------------- animation

func set_head_pitch(pitch: float) -> void:
	_head_pitch = clampf(pitch, -0.9, 0.9)


func set_anim(anim: int, delta: float) -> void:
	_current_anim = anim
	var speed := 9.0 if anim == Anim.WALK else 2.0
	_time += delta * speed
	var t := _time
	var arm_l := 0.0
	var arm_r := 0.0
	var leg_l := 0.0
	var leg_r := 0.0
	var arm_z := 0.12   # arms slightly away from the body
	var head_x := _head_pitch * 0.6
	var bob := 0.0
	match anim:
		Anim.WALK:
			leg_l = sin(t) * 0.7
			leg_r = -sin(t) * 0.7
			arm_l = -sin(t) * 0.6
			arm_r = sin(t) * 0.6
			bob = absf(sin(t)) * 0.035
		Anim.IDLE:
			arm_l = sin(t * 0.5) * 0.05
			arm_r = -sin(t * 0.5) * 0.05
		Anim.JUMP:
			arm_l = -2.6
			arm_r = -2.6
			leg_l = 0.4
			leg_r = -0.3
		Anim.CROUCH:
			leg_l = 0.5
			leg_r = 0.5
			arm_l = 0.3
			arm_r = 0.3
		Anim.SIT:
			leg_l = PI / 2.0
			leg_r = PI / 2.0
			arm_l = 0.55
			arm_r = 0.55
			arm_z = 0.05
	# Emotes override arms/head briefly
	if _emote >= 0:
		_emote_t -= delta
		var k := clampf(_emote_t / 2.2, 0.0, 1.0)
		match _emote:
			Emote.WAVE:
				arm_r = -2.9
				_arm_r.rotation.z = -0.35 + sin(_time * 6.0) * 0.45
			Emote.LAUGH:
				head_x = -0.35 + sin(_time * 8.0) * 0.08
				bob = absf(sin(_time * 8.0)) * 0.03
				arm_l = -0.6
				arm_r = -0.6
			Emote.FACEPALM:
				arm_r = -2.3
				_arm_r.rotation.z = -0.55
				head_x = 0.35
		if _emote_t <= 0.0:
			_emote = -1
			_arm_r.rotation.z = 0.0
			k = 0.0
	else:
		_arm_l.rotation.z = arm_z
		_arm_r.rotation.z = -arm_z
	_leg_l.rotation.x = leg_l
	_leg_r.rotation.x = leg_r
	_arm_l.rotation.x = arm_l
	_arm_r.rotation.x = arm_r
	_head_pivot.rotation.x = head_x
	position.y = bob
	# Breathing
	_torso.scale = Vector3(1.0, 1.0 + sin(_time * 0.9) * 0.015, 1.0)
	# Talking mouth hold-off
	if _talk_hold > 0.0:
		_talk_hold -= delta
		if _talk_hold <= 0.0 and _talk_open:
			_set_mouth_open(false)


func play_emote(id: int) -> void:
	_emote = clampi(id, 0, 2)
	_emote_t = 2.2


## 0..1 microphone level; opens the mouth while the player talks.
func set_talking(level: float) -> void:
	if level > 0.06:
		_talk_hold = 0.15
		if not _talk_open:
			_set_mouth_open(true)


func _set_mouth_open(open: bool) -> void:
	_talk_open = open
	if _face:
		_face.texture_albedo = FacePainter.texture(int(custom.eyes), int(custom.brows), int(custom.mouth), int(custom.blush), open)


func set_visual_layers(mask: int) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = mask
	if postit:
		postit.set_visual_layers(mask)


func head_node() -> Node3D:
	return _head_pivot
