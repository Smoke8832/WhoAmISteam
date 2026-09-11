extends SceneTree
## Dev tool: prints the AABB of every GLB in assets/models/kenney so room layout can be planned.
## Run: godot_console --headless --path . -s tools/inspect_models.gd

const DIR := "res://assets/models/kenney/"


func _init() -> void:
	var dir := DirAccess.open(DIR)
	var names: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	for n in names:
		var scene: PackedScene = load(DIR + n)
		if scene == null:
			print("%s: failed to load" % n)
			continue
		var inst := scene.instantiate()
		var aabb := _merged_aabb(inst)
		print("%-28s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f)" % [n, aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.x, aabb.position.y, aabb.position.z])
		inst.free()
	quit()


func _merged_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
		# accumulate parent transforms manually (not in tree)
		var p := m.get_parent()
		while p != null and p != node and p is Node3D:
			a = (p as Node3D).transform * a
			p = p.get_parent()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
