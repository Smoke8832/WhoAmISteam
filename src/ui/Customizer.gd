extends Control
## Wardrobe: pick a look and a name. Live preview in a SubViewport; Save sends it to the host.

signal closed

const ORDER := ["skin", "head", "hair", "hair_color", "facial_hair", "eyes", "brows", "mouth", "blush", "shirt", "pattern", "pants", "shoes", "accessory"]
const INK := Color("1c1a17")

var custom: Dictionary = {}
var _value_labels: Dictionary = {}
var _rig: CharacterRig
var _preview_root: Node3D
var _spin := 0.0

@onready var rows: VBoxContainer = %Rows
@onready var name_edit: LineEdit = %NameEdit
@onready var viewport: SubViewport = %Preview
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var random_button: Button = %RandomButton


func _ready() -> void:
	custom = Customization.local().duplicate()
	name_edit.text = Settings.player_name()
	_build_rows()
	_build_preview()
	save_button.pressed.connect(_on_save)
	cancel_button.pressed.connect(_close)
	random_button.pressed.connect(_on_random)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	_spin += delta * 0.6
	if _preview_root:
		_preview_root.rotation.y = _spin
	if _rig:
		_rig.set_anim(CharacterRig.Anim.IDLE, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _build_rows() -> void:
	for key in ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = tr("CUSTOM_" + key.to_upper())
		label.custom_minimum_size = Vector2(130, 0)
		label.add_theme_color_override("font_color", INK)
		row.add_child(label)
		var prev := Button.new()
		prev.text = "◀"
		prev.custom_minimum_size = Vector2(40, 0)
		prev.pressed.connect(_step.bind(key, -1))
		row.add_child(prev)
		var value := Label.new()
		value.custom_minimum_size = Vector2(60, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color", INK)
		row.add_child(value)
		_value_labels[key] = value
		var next := Button.new()
		next.text = "▶"
		next.custom_minimum_size = Vector2(40, 0)
		next.pressed.connect(_step.bind(key, 1))
		row.add_child(next)
		rows.add_child(row)
	_refresh_values()


func _step(key: String, dir: int) -> void:
	var count := int(Customization.OPTIONS[key])
	custom[key] = posmod(int(custom[key]) + dir, count)
	_refresh_values()
	_rig.apply(custom)
	Audio.play("ui_click")


func _refresh_values() -> void:
	for key in ORDER:
		_value_labels[key].text = "%d / %d" % [int(custom[key]) + 1, int(Customization.OPTIONS[key])]


func _build_preview() -> void:
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	var world := Node3D.new()
	viewport.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 2.9)
	cam.fov = 45
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	light.light_energy = 1.1
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.4
	world.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.96, 0.95, 0.92, 0.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)
	_preview_root = Node3D.new()
	world.add_child(_preview_root)
	_rig = CharacterRig.new()
	_preview_root.add_child(_rig)
	_rig.apply(custom)
	# A little pedestal
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 0.06
	disc.mesh = cyl
	disc.position.y = -0.03
	disc.material_override = ToonMaterials.make(Color("e8dcb5"))
	_preview_root.add_child(disc)


func _on_random() -> void:
	custom = Customization.randomized()
	_refresh_values()
	_rig.apply(custom)
	Audio.play("ui_click")


func _on_save() -> void:
	var clean_name := Game.sanitize_name(name_edit.text)
	Customization.save_local(custom)
	Settings.set_value("player_name", clean_name)
	Game.submit_customization_local(clean_name, custom)
	Audio.play("ui_confirm")
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
