extends Node3D
## Dev tool: renders one Kenney model from +Z (camera looks toward -Z) and saves a PNG.
## Run: godot_console --path . tools/ModelViewer.tscn -- --model chair --out screenshots/chair.png


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var model := "chair"
	var out := "screenshots/model.png"
	for i in args.size():
		if args[i] == "--model" and i + 1 < args.size():
			model = args[i + 1]
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene: PackedScene = load("res://assets/models/kenney/%s.glb" % model)
	var inst: Node3D = scene.instantiate()
	inst.scale = Vector3.ONE * 2.0
	add_child(inst)
	var aabb := RoomBuilder.model_aabb(inst)
	var c := aabb.get_center() * 2.0
	inst.position = -Vector3(c.x, 0, c.z)
	# Axis markers: red = +X, blue = +Z
	_marker(Vector3(1.5, 0.1, 0), Color.RED)
	_marker(Vector3(0, 0.1, 1.5), Color.BLUE)
	var cam := Camera3D.new()
	cam.position = Vector3(1.2, 1.4, 3.0)
	add_child(cam)
	cam.look_at(Vector3(0, 0.5, 0))
	cam.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.9, 0.9, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved %s" % out)
	get_tree().quit()


func _marker(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.08
	s.height = 0.16
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = pos
	add_child(mi)
