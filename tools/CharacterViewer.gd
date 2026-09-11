extends Node3D
## Dev tool: renders a line-up of characters (one per hair style, random everything else,
## plus a row of accessories) and saves a PNG. Also exercises the ink post-process.
## Run: godot_console --path . --resolution 1600x700 tools/CharacterViewer.tscn -- --out screenshots/characters.png [--seed 7]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "screenshots/characters.png"
	var seed_v := 3
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		if args[i] == "--seed" and i + 1 < args.size():
			seed_v = int(args[i + 1])
	seed(seed_v)
	var closeup := "--closeup" in args
	if closeup:
		# Two characters, close: one text-only post-it, one with a picture.
		var a := Customization.randomized()
		a.accessory = 1
		a.hair = 6
		a.facial_hair = 4
		var ra := CharacterRig.new()
		add_child(ra)
		ra.apply(a)
		ra.position = Vector3(-0.7, 0, 0)
		ra.rotation.y = PI
		ra.set_anim(CharacterRig.Anim.IDLE, 0.2)
		ra.postit.visible = true
		ra.postit.set_text_only("Michael Jackson")
		var b := Customization.randomized()
		b.accessory = 4
		b.hair = 5
		b.blush = 1
		var rb := CharacterRig.new()
		add_child(rb)
		rb.apply(b)
		rb.position = Vector3(0.7, 0, 0)
		rb.rotation.y = PI
		rb.set_anim(CharacterRig.Anim.IDLE, 0.2)
		rb.set_talking(1.0)
		rb.postit.visible = true
		rb.postit.set_picture(load("res://icon.svg"))
		rb.postit.set_label("Sarah")
	# Row 1: hair styles 0..7; Row 2: accessories 0..7 with facial hair cycling
	for i in (0 if closeup else 8):
		var c := Customization.randomized()
		c.hair = i
		c.accessory = 0
		_place(c, Vector3(-5.6 + i * 1.6, 0, 0), i)
		var c2 := Customization.randomized()
		c2.accessory = i
		c2.facial_hair = i % 5
		c2.hair = (i + 3) % 8
		_place(c2, Vector3(-5.6 + i * 1.6, 0, 2.4), i + 8)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 12)
	floor_mesh.mesh = pm
	floor_mesh.material_override = ToonMaterials.make(Color("c69c6d"))
	add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 4, 0.2)
	wall.mesh = bm
	wall.position = Vector3(0, 2, -1.6)
	wall.material_override = ToonMaterials.make(Color("f3e9d2"))
	add_child(wall)
	var cam := Camera3D.new()
	if closeup:
		cam.position = Vector3(0, 1.5, 2.6)
		cam.fov = 50
		add_child(cam)
		cam.look_at(Vector3(0, 1.3, 0))
	else:
		cam.position = Vector3(0, 2.6, 8.2)
		cam.fov = 55
		add_child(cam)
		cam.look_at(Vector3(0, 1.0, 1.0))
	cam.current = true
	var fx := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	fx.mesh = q
	fx.extra_cull_margin = 16384.0
	fx.material_override = load("res://src/shaders/ink_post.tres")
	cam.add_child(fx)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.85, 0.9, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved %s" % out)
	get_tree().quit()


func _place(c: Dictionary, pos: Vector3, idx: int) -> void:
	var rig := CharacterRig.new()
	add_child(rig)
	rig.apply(c)
	rig.position = pos
	rig.rotation.y = PI + deg_to_rad(randf_range(-20, 20))   # characters face -Z; turn them to the camera
	var anims: Array[int] = [CharacterRig.Anim.IDLE, CharacterRig.Anim.WALK, CharacterRig.Anim.SIT, CharacterRig.Anim.JUMP]
	var anim: int = anims[idx % 4]
	rig.set_anim(anim, 0.4)
	if idx % 5 == 2:
		rig.play_emote(idx % 3)
		rig.set_anim(anim, 0.1)
	if idx == 4 or idx == 11:
		rig.postit.visible = true
		rig.postit.set_text_only("Michael Jackson")
	if idx == 6:
		rig.postit.visible = true
		rig.set_talking(1.0)
