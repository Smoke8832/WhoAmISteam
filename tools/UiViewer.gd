extends Control
## Dev tool: instantiates a UI scene, waits a moment, saves a screenshot, quits.
## Run: godot_console --path . --resolution 1280x720 tools/UiViewer.tscn -- --scene res://src/ui/Customizer.tscn --out screenshots/ui.png


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := "res://src/ui/Customizer.tscn"
	var out := "screenshots/ui.png"
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			scene_path = args[i + 1]
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	var scene: PackedScene = load(scene_path)
	var inst := scene.instantiate()
	add_child(inst)
	print("instanced %s: %s size=%s" % [scene_path, inst.get_class(), str(inst.size) if inst is Control else "-"])
	for i in 20:
		await get_tree().process_frame
	if inst is Control:
		print("after layout: size=%s visible=%s children=%d" % [str(inst.size), str(inst.visible), inst.get_child_count()])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved %s" % out)
	get_tree().quit()
