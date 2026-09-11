extends Node
## Test runner scene. Discovers res://tests/test_*.gd, runs them, prints a report,
## and exits with code 0 (all passed) or 1 (failures). Autoloads are available.

const TEST_DIR := "res://tests/"


func _ready() -> void:
	var total_passed := 0
	var total_failed := 0
	var all_failures: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		printerr("Cannot open %s" % TEST_DIR)
		get_tree().quit(2)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	for file in files:
		var script: GDScript = load(TEST_DIR + file)
		if script == null:
			all_failures.append("%s: failed to load" % file)
			total_failed += 1
			continue
		var case = script.new()
		if not (case is TestCase):
			all_failures.append("%s: does not extend TestCase" % file)
			total_failed += 1
			continue
		var result: Array = case.run_all()
		total_passed += result[0]
		total_failed += result[1]
		print("%-32s passed %2d  failed %2d" % [file, result[0], result[1]])
		for msg in result[2]:
			all_failures.append("%s › %s" % [file, msg])
	print("---")
	print("TOTAL passed %d failed %d" % [total_passed, total_failed])
	for msg in all_failures:
		printerr("FAIL " + msg)
	await get_tree().process_frame
	get_tree().quit(0 if total_failed == 0 else 1)
