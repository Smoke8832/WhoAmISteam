class_name PostIt
extends Node3D
## The post-it stuck to a forehead: yellow paper, a strip of tape, the picture, the name.
## Faces the character's forward direction (-Z). Wobbles on a little spring when the head moves.

const PAPER := Color("ffe14d")
const TAPE := Color("8cc4e8")
const INK := Color("2b2611")
const SIZE := 0.34
## Visual layer bit that keeps the face decal off the paper (decal cull mask excludes it).
const LAYER_BIT := 1 << 10

var _paper: MeshInstance3D
var _tape: MeshInstance3D
var _picture: MeshInstance3D
var _frame: MeshInstance3D
var _label: Label3D
var _back_label: Label3D
var _tilt := 0.0
var _spring := 0.0
var _spring_v := 0.0
var _last_pos := Vector3.ZERO
var _solved := false


func _ready() -> void:
	_tilt = deg_to_rad(randf_range(-8.0, 8.0))
	rotation.z = _tilt
	_paper = _quad("Paper", Vector2(SIZE, SIZE), Vector3(0, 0, 0), PAPER)
	_tape = _quad("Tape", Vector2(0.13, 0.045), Vector3(0.0, SIZE / 2.0 - 0.005, -0.004), TAPE)
	_tape.rotation.z = deg_to_rad(4.0)
	_frame = _quad("Frame", Vector2(0.245, 0.245), Vector3(0, 0.03, -0.002), INK)
	_picture = _quad("Picture", Vector2(0.225, 0.225), Vector3(0, 0.03, -0.004), Color.WHITE)
	_label = Label3D.new()
	_label.name = "Name"
	_label.font_size = 40
	_label.pixel_size = 0.0022
	_label.modulate = INK
	_label.outline_size = 0
	_label.width = 210.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector3(0, -0.125, -0.005)
	_label.rotation.y = PI
	_label.font = load("res://assets/fonts/PatrickHand-Regular.ttf")
	add_child(_label)
	_back_label = Label3D.new()
	_back_label.name = "Back"
	_back_label.text = "GOT IT!"
	_back_label.font_size = 64
	_back_label.pixel_size = 0.0022
	_back_label.modulate = INK
	_back_label.position = Vector3(0, 0, 0.005)
	_back_label.visible = false
	_back_label.font = _label.font
	add_child(_back_label)
	var back := _quad("PaperBack", Vector2(SIZE, SIZE), Vector3(0, 0, 0.001), PAPER)
	back.rotation.y = 0.0   # faces +Z (the back side)
	set_blank()
	set_visual_layers(1)
	_last_pos = global_position


func _quad(name: String, size: Vector2, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = PI   # QuadMesh faces +Z; the character faces -Z
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	mi.material_override = m
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	if not visible:
		return
	# Spring: head motion kicks the paper, it swings around its top edge and settles.
	var vel := (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	var kick := clampf(vel.y * 0.15 + vel.length() * 0.02, -1.0, 1.0)
	_spring_v += (-_spring * 60.0 - _spring_v * 6.0 + kick * 8.0) * delta
	_spring += _spring_v * delta
	_spring = clampf(_spring, -0.6, 0.6)
	rotation.x = _spring
	rotation.z = _tilt + _spring * 0.2


func set_picture(tex: Texture2D) -> void:
	var m := _picture.material_override as StandardMaterial3D
	m.albedo_texture = tex
	m.albedo_color = Color.WHITE
	_picture.visible = true
	_frame.visible = true
	_label.position.y = -0.125
	_label.font_size = 40


func set_label(text: String) -> void:
	_label.text = text


## No picture available: the name alone, big, in marker.
func set_text_only(text: String) -> void:
	_picture.visible = false
	_frame.visible = false
	_label.text = text
	_label.position.y = 0.0
	_label.font_size = 44 if text.length() <= 14 else 36


## Shown to the target themselves (and before a round): a big question mark.
func set_blank() -> void:
	_picture.visible = false
	_frame.visible = false
	_label.text = "?"
	_label.position.y = 0.0
	_label.font_size = 120


func flip_solved() -> void:
	if _solved:
		return
	_solved = true
	_back_label.visible = true
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", PI, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func reset() -> void:
	_solved = false
	_back_label.visible = false
	rotation.y = 0.0
	set_blank()


func set_visual_layers(mask: int) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = mask | LAYER_BIT
	for l in find_children("*", "Label3D", true, false):
		(l as Label3D).layers = mask | LAYER_BIT
